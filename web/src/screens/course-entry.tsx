/**
 * ลงข้อมูลรายวิชาเข้าหลักสูตร — วางทั้งตารางจากหนังสือหลักสูตรทีเดียว
 *
 * ═══ เทียบกับวิธีของ SISA (ดูจากหน้าจอจริง Grades/Subjects.php) ═══
 *
 * SISA ให้กรอกทีละช่องในตารางที่แก้ได้ทั้งหน้า — หนึ่งฟอร์มมี input 430 ช่อง
 * ต่อ 31 รายวิชา คือ 12 ช่องต่อวิชา (CODE · ENG_CODE · TITLE · ENG_TITLE ·
 * SHORT_NAME · ENG_SHORT_NAME · CREDIT · HR · STATUS · GROUP_ID ·
 * COURSE_TYPE · COMMENT) หลักสูตรจริงฉบับหนึ่งมีร้อยกว่ารายวิชา แปลว่า
 * ต้องพิมพ์เกินพันช่องด้วยมือต่อวิทยาลัยที่เปิดใหม่หนึ่งแห่ง
 *
 * ─── สามอย่างที่ทำต่างจาก SISA โดยตั้งใจ ───
 *
 * **1. เก็บ ท-ป-น ไม่ใช่ "หน่วยกิต + คาบ + ประเภท"**
 * SISA เก็บ CREDIT, HR และ STATUS(ทฤษฎี/ปฏิบัติ/ทั้งสอง) แยกกัน ซึ่ง
 * **ประกอบกลับเป็น ท-ป-น ไม่ได้** — วิชา 2 หน่วยกิต 3 คาบ แบบ "ทฤษฎีและ
 * ปฏิบัติ" เป็นได้ทั้ง 1-2-2 และ 2-1-2 ทั้งที่ ท-ป-น คือรูปที่พิมพ์อยู่บน
 * หนังสือหลักสูตรและบนเอกสารที่ยื่น สอศ. จริง
 * ที่นี่กรอก ท-ป-น แล้ว **คำนวณ** คาบต่อสัปดาห์กับประเภทวิชาให้ — ทิศทาง
 * ตรงข้ามกัน และไม่มีทางเสียข้อมูลระหว่างทาง
 *
 * **2. หมวดวิชาเป็นต้นไม้ ไม่ใช่ dropdown สองอันที่ทับกันเอง**
 * SISA มี GROUP_ID (กลุ่มวิชา) กับ COURSE_TYPE (หมวดวิชา) เป็นรายการแบน
 * สองชุดที่มีค่าซ้ำกันเกือบทั้งหมด — "กลุ่มสมรรถนะวิชาชีพพื้นฐาน" อยู่ใน
 * ทั้งสองชุด ไม่มีอะไรกันการเลือกที่ขัดกันเอง และในข้อมูลจริงของวิทยาลัย
 * ก็เกิดขึ้นแล้ว (TOEIC 3 อยู่กลุ่ม "กิจกรรมเสริมหลักสูตร" แต่หมวด
 * "สมรรถนะแกนกลาง" ส่วน TOEIC 4-6 ที่เหลืออยู่ "กิจกรรมเสริมหลักสูตร")
 * ของเราหมวดวิชามี `parent_id` อยู่แล้ว จึงเลือกครั้งเดียวได้ทั้งสาย
 *
 * **3. ตรวจ ท-ป-น กับหน่วยกิตให้ แต่ไม่บล็อก**
 * เกณฑ์ สอศ. คือ ทฤษฎี 1 ชม. = 1 นก. · ปฏิบัติ 2–3 ชม. = 1 นก. ซึ่งทำให้
 * หน่วยกิตที่ถูกต้องเป็น **ช่วง** ไม่ใช่ค่าเดียว — คำนวณแทนคนไม่ได้ แต่บอก
 * ได้ว่าค่าที่พิมพ์มาหลุดช่วง ซึ่งมักแปลว่าพิมพ์ผิดหนึ่งหลัก
 * ไม่บล็อกเพราะรายวิชาฝึกงาน (0-320-4) หลุดเกณฑ์นี้โดยชอบ — ระบบที่บล็อก
 * จะทำให้คนกรอกต้องหาทางหลอกมันแทนที่จะกรอกตามหนังสือ
 */
import { useMemo, useState } from 'react';
import { api } from '../core/api';
import { ActionButton, Card, Field, Notice } from '../ui/kit';

export interface CategoryOption {
  id: string;
  parent_id: string | null;
  code: string;
  name_th: string;
}

/** หนึ่งบรรทัดที่อ่านออกมาได้จากข้อความที่วางมา */
export interface ParsedRow {
  code: string;
  nameTh: string;
  theoryHours: number;
  practiceHours: number;
  credits: number;
  /** ปัญหาที่ทำให้ส่งไม่ได้ — ต้องแก้ก่อน */
  error?: string;
  /** ข้อสังเกตที่ยังส่งได้ — ให้คนตัดสินใจ */
  warning?: string;
  raw: string;
}

/* ═══ ตัวอ่านข้อความ ═══════════════════════════════════════════════ */

/**
 * ท-ป-น ที่อยู่ตรงไหนก็ได้ในบรรทัด
 *
 * รับทั้ง `2-0-2` · `2 - 0 - 2` · `(2-0-2)` · `2/0/2` เพราะข้อความที่คัดลอก
 * มาจาก PDF กับจาก Word ให้ตัวคั่นไม่เหมือนกัน และคนที่พิมพ์เองก็พิมพ์
 * คนละแบบ — ตัวอ่านที่รับแบบเดียวแปลว่าคนต้องมาจัดข้อความก่อนวาง
 * ซึ่งเป็นงานที่เพิ่งพยายามตัดทิ้ง
 */
const TPN = /\(?\s*(\d{1,3})\s*[-/–]\s*(\d{1,3})\s*[-/–]\s*(\d{1,2}(?:\.\d)?)\s*\)?/g;

/**
 * เอาตัวที่อยู่ **ท้ายสุด** ของบรรทัด ไม่ใช่ตัวแรก
 *
 * รหัสวิชาอาชีวะเป็นรูป `#####-####` ซึ่งมีขีดเดียวจึงไม่ชนกับ ท-ป-น
 * แต่รหัสของบางวิทยาลัยมีขีดมากกว่านั้น และชื่อวิชาก็มีตัวเลขกับขีดได้
 * (`คณิตศาสตร์ 1-2`) ส่วน ท-ป-น อยู่ท้ายบรรทัดเสมอในหนังสือทุกฉบับ
 * — เลือกตัวท้ายจึงเดาถูกในกรณีที่เลือกตัวแรกแล้วเดาผิด
 */
function lastTpn(line: string): RegExpExecArray | null {
  TPN.lastIndex = 0;
  let found: RegExpExecArray | null = null;
  let m: RegExpExecArray | null;
  while ((m = TPN.exec(line)) !== null) found = m;
  return found;
}

/** ช่วงหน่วยกิตที่เกณฑ์ สอศ. ยอมสำหรับ ท-ป ชุดนี้ */
export function creditRange(theory: number, practice: number): [number, number] {
  // ปฏิบัติ 3 ชม. = 1 นก. เป็นขอบล่าง · 2 ชม. = 1 นก. เป็นขอบบน
  const low = theory + Math.ceil(practice / 3);
  const high = theory + Math.floor(practice / 2);
  return [Math.min(low, high), Math.max(low, high)];
}

export function courseKind(theory: number, practice: number): string {
  if (theory > 0 && practice > 0) return 'ทฤษฎีและปฏิบัติ';
  if (practice > 0) return 'ปฏิบัติ';
  if (theory > 0) return 'ทฤษฎี';
  return '—';
}

/**
 * อ่านข้อความที่วางมาเป็นรายบรรทัด
 *
 * ─── ทำไมหา ท-ป-น ก่อน แล้วค่อยตัดชื่อ ───
 * เพราะชื่อวิชาไทยมีเว้นวรรคอยู่ข้างในเป็นปกติ ("การบัญชี เบื้องต้น")
 * การตัดด้วยช่องว่างจะได้ชื่อขาดครึ่ง ส่วน ท-ป-น มีรูปแบบตายตัวและอยู่
 * ท้ายบรรทัดเสมอในหนังสือทุกฉบับ จึงเป็นหลักยึดที่เชื่อได้มากที่สุด
 */
export function parsePasted(text: string): ParsedRow[] {
  const seen = new Set<string>();

  return text
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter((l) => l.length > 0)
    .map((raw): ParsedRow => {
      const m = lastTpn(raw);
      if (!m) {
        return {
          raw, code: '', nameTh: '', theoryHours: 0, practiceHours: 0, credits: 0,
          error: 'หา ท-ป-น ในบรรทัดนี้ไม่เจอ',
        };
      }

      const theoryHours = Number(m[1]);
      const practiceHours = Number(m[2]);
      const credits = Number(m[3]);

      const before = raw.slice(0, m.index).trim();
      const parts = before.split(/[\t]+|\s{2,}/).map((s) => s.trim()).filter(Boolean);

      // คั่นด้วยแท็บหรือช่องว่างหลายตัวคือรูปที่คัดลอกจากตารางมา — เชื่อได้ตรง ๆ
      let code = parts[0] ?? '';
      let nameTh = parts.slice(1).join(' ').trim();

      // คั่นด้วยช่องว่างเดียว (คนพิมพ์เอง) — รหัสวิชาคือคำแรกเสมอ
      if (!nameTh && before.includes(' ')) {
        const i = before.indexOf(' ');
        code = before.slice(0, i).trim();
        nameTh = before.slice(i + 1).trim();
      }

      const row: ParsedRow = {
        raw, code, nameTh, theoryHours, practiceHours, credits,
      };

      if (!code) row.error = 'ไม่มีรหัสวิชา';
      else if (!nameTh) row.error = 'ไม่มีชื่อวิชา';
      else if (seen.has(code)) row.error = `รหัส ${code} ซ้ำกับบรรทัดก่อนหน้า`;
      else seen.add(code);

      if (!row.error) {
        const [low, high] = creditRange(theoryHours, practiceHours);
        if (credits < low || credits > high) {
          row.warning =
            `เกณฑ์ สอศ. ของ ${theoryHours}-${practiceHours} คือ ` +
            `${low === high ? low : `${low}–${high}`} หน่วยกิต`;
        }
      }

      return row;
    });
}

/* ═══ หน้าจอ ═══════════════════════════════════════════════════════ */

const SAMPLE = `20000-1101\tภาษาไทยพื้นฐาน\t2-0-2
20000-1102\tภาษาไทยเพื่ออาชีพ\t0-2-1
20000-1301\tวิทยาศาสตร์เพื่อพัฒนาทักษะชีวิต\t1-2-2`;

interface BulkResult {
  total: number;
  created: number;
  linked: number;
  already: number;
  mismatch: number;
  rows: { code: string; status: string; detail?: string }[];
}

const STATUS_LABEL: Record<string, string> = {
  created: 'สร้างใหม่',
  linked: 'เพิ่มเข้าหลักสูตร',
  already: 'มีอยู่แล้ว',
  mismatch: 'ท-ป-น ไม่ตรง',
};

export function CourseEntry({
  versionId,
  editionBe,
  categories,
  onDone,
}: {
  versionId: string;
  editionBe: number;
  categories: CategoryOption[];
  onDone: () => void;
}) {
  const [text, setText] = useState('');
  const [categoryId, setCategoryId] = useState('');
  const [result, setResult] = useState<BulkResult | null>(null);

  const rows = useMemo(() => parsePasted(text), [text]);
  const bad = rows.filter((r) => r.error);
  const warned = rows.filter((r) => !r.error && r.warning);
  const good = rows.filter((r) => !r.error);

  /** หมวดวิชาแบบต้นไม้ — เยื้องตามชั้นเพื่อให้เห็นว่าอันไหนอยู่ใต้อันไหน */
  const options = useMemo(() => {
    const byParent = new Map<string | null, CategoryOption[]>();
    for (const c of categories) {
      const list = byParent.get(c.parent_id) ?? [];
      list.push(c);
      byParent.set(c.parent_id, list);
    }
    const out: { id: string; label: string }[] = [];
    const walk = (parent: string | null, depth: number) => {
      for (const c of byParent.get(parent) ?? []) {
        out.push({ id: c.id, label: `${'  '.repeat(depth)}${c.name_th}` });
        walk(c.id, depth + 1);
      }
    };
    walk(null, 0);
    return out;
  }, [categories]);

  return (
    <Card title="ลงข้อมูลรายวิชา — วางจากหนังสือหลักสูตร">
      <p className="hint">
        คัดลอกตารางรายวิชาจากหนังสือหลักสูตรมาวางได้ทั้งก้อน หนึ่งบรรทัดต่อหนึ่งรายวิชา
        รูปแบบ <span className="mono">รหัส ชื่อวิชา ท-ป-น</span> —
        คาบต่อสัปดาห์และประเภทวิชาระบบคำนวณให้เอง ไม่ต้องกรอก
      </p>

      <Field label="ข้อความจากหนังสือหลักสูตร">
        <textarea
          rows={7}
          value={text}
          spellCheck={false}
          placeholder={SAMPLE}
          onChange={(e) => {
            setText(e.target.value);
            setResult(null);
          }}
          style={{ fontFamily: 'var(--mono, monospace)', whiteSpace: 'pre', width: '100%' }}
        />
      </Field>

      <Field label={`หมวดวิชาที่จะเพิ่มเข้าไป (ฉบับ ${editionBe})`}>
        <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
          <option value="">— เลือกหมวดวิชา —</option>
          {options.map((o) => (
            <option key={o.id} value={o.id}>{o.label}</option>
          ))}
        </select>
      </Field>

      {rows.length > 0 && (
        <>
          <p className="hint">
            อ่านได้ <b>{good.length}</b> รายวิชา
            {warned.length > 0 && <> · น่าตรวจซ้ำ <b>{warned.length}</b></>}
            {bad.length > 0 && <> · แก้ก่อน <b>{bad.length}</b></>}
          </p>

          <div className="scroll-x">
            <table>
              <thead>
                <tr>
                  <th style={{ width: 110 }}>รหัสวิชา</th>
                  <th>ชื่อวิชา</th>
                  <th className="num" style={{ width: 80 }}>ท-ป-น</th>
                  <th className="num" style={{ width: 90 }}>คาบ/สัปดาห์</th>
                  <th style={{ width: 130 }}>ประเภท</th>
                  <th style={{ width: 240 }}>หมายเหตุ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={i}>
                    <td className="mono">{r.code || '—'}</td>
                    <td style={{ whiteSpace: 'normal' }}>
                      {r.nameTh || <span className="hint">{r.raw}</span>}
                    </td>
                    <td className="num mono">
                      {r.error === 'หา ท-ป-น ในบรรทัดนี้ไม่เจอ'
                        ? '—'
                        : `${r.theoryHours}-${r.practiceHours}-${r.credits}`}
                    </td>
                    {/* สองคอลัมน์นี้คำนวณมา ไม่ใช่ช่องกรอก — SISA ให้กรอกเองแล้วเพี้ยนจาก ท-ป-น ได้ */}
                    <td className="num">{r.error ? '—' : r.theoryHours + r.practiceHours}</td>
                    <td>{r.error ? '—' : courseKind(r.theoryHours, r.practiceHours)}</td>
                    <td style={{ whiteSpace: 'normal' }}>
                      {r.error && <span className="danger">{r.error}</span>}
                      {r.warning && <span className="warn">{r.warning}</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      {bad.length > 0 && (
        <Notice kind="error">
          มี {bad.length} บรรทัดที่อ่านไม่ออก — แก้ในกล่องข้อความด้านบนแล้วตารางจะอัปเดตเอง
          ระบบจะไม่ข้ามบรรทัดที่เสียให้เงียบ ๆ เพราะรายวิชาที่หายไปหนึ่งตัวคือเกณฑ์จบที่ผิดทั้งรุ่น
        </Notice>
      )}

      <div className="row">
        <ActionButton
          className="primary"
          onRun={async () => {
            if (!categoryId) throw new Error('ยังไม่ได้เลือกหมวดวิชา');
            return api.post<BulkResult>(`/curriculum/versions/${versionId}/courses/bulk`, {
              curriculumCategoryId: categoryId,
              rows: good.map((r) => ({
                code: r.code,
                nameTh: r.nameTh,
                theoryHours: r.theoryHours,
                practiceHours: r.practiceHours,
                credits: r.credits,
              })),
            });
          }}
          onDone={(r) => {
            setResult(r as BulkResult);
            onDone();
          }}
        >
          เพิ่ม {good.length} รายวิชาเข้าหลักสูตร
        </ActionButton>
      </div>

      {result && (
        <>
          <Notice kind={result.mismatch > 0 ? 'warn' : 'ok'}>
            สร้างใหม่ {result.created} · เพิ่มเข้าหลักสูตร {result.linked} ·
            มีอยู่แล้ว {result.already}
            {result.mismatch > 0 && ` · ท-ป-น ไม่ตรงกับที่มีในระบบ ${result.mismatch}`}
          </Notice>
          {result.mismatch > 0 && (
            <div className="scroll-x">
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 110 }}>รหัสวิชา</th>
                    <th>สิ่งที่ต่าง</th>
                  </tr>
                </thead>
                <tbody>
                  {result.rows
                    .filter((r) => r.status === 'mismatch')
                    .map((r) => (
                      <tr key={r.code}>
                        <td className="mono">{r.code}</td>
                        <td style={{ whiteSpace: 'normal' }}>
                          {r.detail} <span className="hint">({STATUS_LABEL[r.status]})</span>
                        </td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </Card>
  );
}
