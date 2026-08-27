/**
 * หลักสูตร — เลือกข้อมูลอ้างอิงจาก สอศ. แก้ชื่อ และนำเข้าเป็นฉบับร่าง
 *
 * ─── ทำไมปุ่ม "นำเข้ารายการที่เลือก" ต้องสร้างครบทั้งสาย ───
 * ต้นไม้ของเราลึกห้าชั้น (program_type → program → program_track →
 * curriculum → curriculum_version) แต่ชุดข้อมูลอ้างอิงมีแค่สองระดับ
 * (typeName กับ code+nameTh — ไม่มีรหัสของหมวดสาขาและไม่มีชั้นสาขางาน
 * เลย) ปุ่มนี้จึงต้องหา/สร้างชั้นที่ขาดให้ครบเอง ไม่ใช่แค่ insert แถวเดียว
 *
 * ─── ทำไม groupName (สาขาวิชา/กลุ่มอาชีพ) ไม่ผูกกับตารางไหนเลย ───
 * เทียบตัวอย่างในคอมเมนต์ schema แล้ว program.code ตัวอย่างคือ '20101'
 * ตรงกับ code ของแถวอ้างอิงเป๊ะ (ไม่ใช่ groupName) — groupName เป็นแค่
 * ตัวกรองแสดงผลของชุดข้อมูล สอศ. เอง ไม่ใช่ชั้นในต้นไม้ของเรา
 */
import { useMemo, useState } from 'react';
import { api } from '../core/api';
import { ActionButton, Notice, PageHead, useAsync } from '../ui/kit';

type Row = { level: 'PVC' | 'PVS'; typeName: string; groupName: string; code: string; nameTh: string };

interface ProgramTreeRow {
  program_type_id: string;
  type_code: string;
  type_name: string;
  program_id: string | null;
  program_code: string | null;
  program_level: string | null;
  track_id: string | null;
  track_code: string | null;
}

const fetchTree = () => api.get<ProgramTreeRow[]>('/curriculum/programs');

/** เลขรหัสสองหลักถัดไปที่ยังไม่ถูกใช้ในสถานศึกษานี้ — ใช้ตอนต้องสร้างหมวดสาขาใหม่ */
function nextCode(existing: string[], width: number): string {
  const max = existing.reduce((m, c) => Math.max(m, Number(c) || 0), 0);
  return String(max + 1).padStart(width, '0');
}

export function CurriculumLibraryScreen() {
  const [edition, setEdition] = useState('2567');
  const [level, setLevel] = useState<'all' | 'PVC' | 'PVS'>('all');
  const [q, setQ] = useState('');
  const [type, setType] = useState('');
  const [group, setGroup] = useState('');
  const [course, setCourse] = useState('');
  const data = useAsync(() => api.get<{ rows: Row[] }>('/curriculum/official/2567'), []);
  const tree = useAsync(fetchTree, []);

  const rows = useMemo(
    () => (data.data?.rows ?? []).filter(
      (r) => (level === 'all' || r.level === level)
        && (`${r.typeName} ${r.groupName} ${r.code} ${r.nameTh}`).toLowerCase().includes(q.toLowerCase()),
    ),
    [data.data, level, q],
  );
  const types = [...new Set(rows.map((r) => r.typeName))];
  const groups = [...new Set(rows.filter((r) => !type || r.typeName === type).map((r) => r.groupName))];
  const courses = rows.filter((r) => (!type || r.typeName === type) && (!group || r.groupName === group));
  const selected = courses.find((r) => r.code === course);
  const alreadyImported = selected
    ? (tree.data ?? []).some((t) => t.program_code === selected.code && t.program_level === selected.level)
    : false;

  return (
    <>
      <PageHead title="หลักสูตร" sub="เลือกข้อมูลอ้างอิงจาก สอศ. ตรวจสอบและแก้ชื่อก่อนนำเข้า" />
      <div className="curriculum-filter">
        <label>ปีหลักสูตร<select value={edition} onChange={(e) => setEdition(e.target.value)}><option>2557</option><option>2562</option><option>2564</option><option>2567</option></select></label>
        <label>ระดับ<select value={level} onChange={(e) => setLevel(e.target.value as typeof level)}><option value="all">ทุกระดับ</option><option value="PVC">ปวช.</option><option value="PVS">ปวส.</option></select></label>
        <label>ค้นหา<input value={q} onChange={(e) => setQ(e.target.value)} placeholder="รหัสหรือชื่อสาขา" /></label>
      </div>
      {edition !== '2567' && <Notice kind="info">กำลังเตรียมชุดข้อมูลหลักสูตร พ.ศ. {edition}; หน้านี้ยังแสดงชุดข้อมูล สอศ. พ.ศ. 2567 ที่นำเข้ามาแล้วเพื่อยืนยันรูปแบบ</Notice>}
      <div className="curriculum-library">
        <Column title="ประเภทวิชา" items={types} selected={type} onSelect={(v) => { setType(v); setGroup(''); setCourse(''); }} />
        <Column title="สาขาวิชา/กลุ่มอาชีพ" items={groups} selected={group} onSelect={(v) => { setGroup(v); setCourse(''); }} />
        <Column title="หลักสูตร" items={courses.map((r) => `${r.code} ${r.nameTh}`)} selected={selected ? `${selected.code} ${selected.nameTh}` : ''} onSelect={(v) => setCourse(v.slice(0, 5))} />
        {selected
          ? <ImportPanel key={selected.code} row={selected} alreadyImported={alreadyImported} onImported={() => tree.reload()} />
          : <section className="curriculum-column"><header>ระดับชั้นและชื่อก่อนนำเข้า</header><div className="empty">เลือกหลักสูตรเพื่อแก้ชื่อก่อนนำเข้า</div></section>}
      </div>
    </>
  );
}

function Column({ title, items, selected, onSelect }: { title: string; items: string[]; selected: string; onSelect: (v: string) => void }) {
  return (
    <section className="curriculum-column">
      <header>{items.length} {title}</header>
      <div>{items.map((item) => <button key={item} className={item === selected ? 'selected' : ''} onClick={() => onSelect(item)}>{item}</button>)}</div>
    </section>
  );
}

function ImportPanel({ row, alreadyImported, onImported }: { row: Row; alreadyImported: boolean; onImported: () => void }) {
  const [title, setTitle] = useState(row.nameTh);
  const [levelSel, setLevelSel] = useState<'PVC' | 'PVS'>(row.level);
  const [minCredits, setMinCredits] = useState('');
  const [fromYear, setFromYear] = useState(String(new Date().getFullYear() + 543));
  const [done, setDone] = useState<string | null>(null);

  return (
    <section className="curriculum-column">
      <header>ระดับชั้นและชื่อก่อนนำเข้า</header>
      <div className="curriculum-edit">
        <label>ชื่อหลักสูตร<input value={title} onChange={(e) => setTitle(e.target.value)} /></label>
        <label>ระดับ<select value={levelSel} onChange={(e) => setLevelSel(e.target.value as 'PVC' | 'PVS')}><option value="PVC">ปวช.</option><option value="PVS">ปวส.</option></select></label>
        <label>หน่วยกิตขั้นต่ำจบ<input value={minCredits} onChange={(e) => setMinCredits(e.target.value.replace(/\D/g, ''))} placeholder="เช่น 103" /></label>
        <label>ปีที่เริ่มใช้ฉบับ (พ.ศ.)<input value={fromYear} onChange={(e) => setFromYear(e.target.value.replace(/\D/g, ''))} /></label>
        {alreadyImported && <Notice kind="warn">หลักสูตรนี้เคยนำเข้าไปแล้ว — กดซ้ำจะสร้างหลักสูตรซ้อนอีกชุด</Notice>}
        {done ? (
          <Notice kind="info">นำเข้าสำเร็จ — สร้างเป็นฉบับร่างแล้ว ไปเพิ่มหมวดวิชา/รายวิชาต่อได้ที่เมนู "โครงสร้างหลักสูตร"</Notice>
        ) : !minCredits || !fromYear ? (
          // ActionButton โชว์ข้อความ error ให้เฉพาะ ApiError จากเซิร์ฟเวอร์
          // เท่านั้น — throw Error ธรรมดาจากช่องที่กรอกไม่ครบจะถูกแทนที่ด้วย
          // ข้อความกลาง "ทำรายการไม่สำเร็จ" ที่ไม่บอกว่าขาดอะไร จึงปิดปุ่ม
          // แทนการโยน error ตั้งแต่แรก ไม่ให้เดินไปถึง onRun เลย
          <>
            <Notice kind="warn">กรอกหน่วยกิตขั้นต่ำจบและปีที่เริ่มใช้ฉบับให้ครบก่อนนำเข้า</Notice>
            <button className="primary" disabled>นำเข้ารายการนี้</button>
          </>
        ) : (
          <ActionButton
            className="primary"
            onRun={async () => {
              const tree = await api.get<ProgramTreeRow[]>('/curriculum/programs');

              let typeRow = tree.find((t) => t.type_name === row.typeName);
              if (!typeRow) {
                const created = await api.post<{ id: string; code: string; name_th: string }>('/curriculum/program-types', {
                  code: nextCode(tree.map((t) => t.type_code), 2),
                  nameTh: row.typeName,
                });
                typeRow = { program_type_id: created.id, type_code: created.code, type_name: created.name_th, program_id: null, program_code: null, program_level: null, track_id: null, track_code: null };
              }

              let programId = tree.find((t) => t.program_code === row.code && t.program_level === levelSel)?.program_id ?? null;
              if (!programId) {
                const created = await api.post<{ id: string }>('/curriculum/programs', {
                  programTypeId: typeRow.program_type_id, level: levelSel, code: row.code, nameTh: title.trim(),
                });
                programId = created.id;
              }

              // curriculum ผูกกับ program_track แบบหนึ่งต่อหนึ่ง (unique
              // constraint) — ห้ามใช้สาขางานเดิมซ้ำ ต้องสร้างสาขางานใหม่
              // ให้ทุกครั้งที่นำเข้า ต่อให้ตัวสาขาวิชา (program) มีอยู่แล้ว
              const existingTrackCodes = tree.filter((t) => t.program_id === programId && t.track_code).map((t) => t.track_code!);
              let trackSeq = 1;
              while (existingTrackCodes.includes(`${row.code}${String(trackSeq).padStart(2, '0')}`)) trackSeq += 1;
              const track = await api.post<{ id: string }>('/curriculum/program-tracks', {
                programId, code: `${row.code}${String(trackSeq).padStart(2, '0')}`, nameTh: title.trim(),
              });

              const curriculum = await api.post<{ id: string }>('/curriculum/curricula', {
                programTrackId: track.id, nameTh: title.trim(),
              });
              await api.post('/curriculum/versions', {
                curriculumId: curriculum.id, editionBe: 2567,
                effectiveFromYearBe: Number(fromYear), minTotalCredits: Number(minCredits),
              });
              return curriculum.id;
            }}
            onDone={(id) => { setDone(id as string); onImported(); }}
          >
            นำเข้ารายการนี้
          </ActionButton>
        )}
        <small>รายการจะถูกสร้างเป็นฉบับร่าง เพื่อให้ตรวจและเพิ่มรายวิชาก่อนเปิดใช้</small>
      </div>
    </section>
  );
}
