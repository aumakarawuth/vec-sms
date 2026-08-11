/**
 * นำเข้าข้อมูลนักศึกษาและบุคลากร
 *
 * ─── ทำไมต้องตรวจก่อนนำเข้าเสมอ ───
 * `apply_student_import()` ทำงานแบบทั้งหมดหรือไม่ทำเลย — มีแถวใดผิดจะไม่เขียน
 * อะไรลงไปสักแถว เพราะข้อมูลที่เข้าไปครึ่งเดียวแก้ยากกว่าไม่เข้าเลย
 * ขั้นตรวจจึงไม่ใช่พิธีกรรม แต่เป็นวิธีเดียวที่จะรู้ว่าไฟล์ใช้ได้ก่อนกดจริง
 *
 * ─── ทำไมไฟล์ตั้งบทบาทไม่ได้ ───
 * ทุกค่าใน `staff_role_kind` เห็นข้อมูลทั้งวิทยาลัย ถ้าไฟล์ตั้งได้
 * คนที่แก้ไฟล์ได้ก็แต่งตั้งตัวเองเป็นผู้ดูแลได้ — การเป็นครูอยู่ที่
 * `is_teacher` ซึ่งไฟล์ตั้งได้ ส่วนบทบาทต้องแต่งตั้งทีละคนเสมอ
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { thaiDateTime } from '../core/fmt';
import { AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync } from '../ui/kit';

interface Batch {
  id: string;
  kind: string;
  source_name: string;
  status: string;
  total_rows: number;
  ok_rows: number;
  error_rows: number;
  created_at?: string;
  applied_at?: string | null;
}

const KIND: Record<string, string> = {
  student: 'นักศึกษา',
  staff: 'บุคลากร',
  academic_history: 'ประวัติการเรียนเดิม',
};

const STATUS: Record<string, { label: string; kind: 'default' | 'warn' | 'ok' | 'danger' }> = {
  draft: { label: 'ยังไม่ตรวจ', kind: 'default' },
  validated: { label: 'ตรวจแล้ว พร้อมนำเข้า', kind: 'warn' },
  applied: { label: 'นำเข้าแล้ว', kind: 'ok' },
  failed: { label: 'มีแถวผิด', kind: 'danger' },
};

/** ตัวอย่างหัวตารางของแต่ละชนิด — ต้องตรงกับที่ validate_*_row อ่านจริง */
const TEMPLATE: Record<string, string> = {
  student:
    'student_code,prefix_th,first_name_th,last_name_th,admitted_year_be,gender,birth_date,phone,email',
  staff:
    'staff_code,prefix_th,first_name_th,last_name_th,employment_kind,is_teacher,department_code,position_th',
};

export function ImportScreen() {
  const [kind, setKind] = useState('student');
  const [sourceName, setSourceName] = useState('');
  const [csv, setCsv] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const batches = useAsync(() => api.get<Batch[]>(`/import${qs({ kind })}`), [kind]);

  /**
   * แปลง CSV เป็นแถว — ตัดช่องว่างและข้ามบรรทัดว่าง
   * ค่าที่เป็นสตริงว่างจะไม่ถูกส่งไปเลย เพราะฐานข้อมูลแยก "ไม่กรอก"
   * ออกจาก "กรอกเป็นค่าว่าง" ในหลายคอลัมน์
   */
  function parse(): { rowNo: number; payload: Record<string, string> }[] {
    const lines = csv.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    if (lines.length < 2) return [];
    const head = lines[0]!.split(',').map((h) => h.trim());
    return lines.slice(1).map((line, i) => {
      const cells = line.split(',');
      const payload: Record<string, string> = {};
      head.forEach((h, j) => {
        const v = (cells[j] ?? '').trim();
        if (v !== '') payload[h] = v;
      });
      return { rowNo: i + 1, payload };
    });
  }

  const rows = parse();

  async function run(apply: boolean) {
    setBusy(true);
    setError(null);
    setMsg(null);
    try {
      const batch = await api.post<{ id: string }>('/import', {
        kind,
        sourceName: sourceName.trim() || 'วางจากตาราง',
        rows,
      });
      const v = await api.post<Batch>(`/import/${batch.id}/validate`);
      if (v.error_rows > 0) {
        setError(`ตรวจแล้วพบแถวผิด ${v.error_rows} จาก ${v.total_rows} แถว — ยังไม่นำเข้า`);
        batches.reload();
        return;
      }
      if (!apply) {
        setMsg(`ตรวจผ่านครบ ${v.total_rows} แถว — กด “นำเข้าจริง” เพื่อบันทึก`);
        batches.reload();
        return;
      }
      const a = await api.post<{ imported: number }>(`/import/${batch.id}/apply`);
      setMsg(`นำเข้าแล้ว ${a.imported} รายการ`);
      setCsv('');
      batches.reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'นำเข้าไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHead title="นำเข้าข้อมูล" />

      <Card title="วางข้อมูลจากตาราง">
        <div className="row">
          <Field label="ชนิดข้อมูล">
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="student">นักศึกษา</option>
              <option value="staff">บุคลากร</option>
            </select>
          </Field>
          <Field label="ชื่อไฟล์ต้นทาง">
            <input
              value={sourceName}
              onChange={(e) => setSourceName(e.target.value)}
              placeholder="เช่น นักศึกษาใหม่-2569.xlsx"
            />
          </Field>
        </div>

        <label className="field">
          <span>
            ข้อมูลแบบ CSV — บรรทัดแรกเป็นหัวตาราง (คัดลอกจาก Excel แล้ววางได้ ถ้าคั่นด้วยจุลภาค)
          </span>
          <textarea
            value={csv}
            onChange={(e) => setCsv(e.target.value)}
            rows={10}
            spellCheck={false}
            style={{ fontFamily: 'ui-monospace, Consolas, monospace', fontSize: 12 }}
            placeholder={TEMPLATE[kind]}
          />
        </label>

        <div className="row">
          <div className="shrink">
            <button disabled={busy || rows.length === 0} onClick={() => void run(false)}>
              ตรวจอย่างเดียว ({rows.length} แถว)
            </button>
          </div>
          <div className="shrink">
            <button
              className="primary"
              disabled={busy || rows.length === 0}
              onClick={() => void run(true)}
            >
              {busy ? 'กำลังทำ…' : 'ตรวจแล้วนำเข้าจริง'}
            </button>
          </div>
          <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
            มีแถวใดผิดจะไม่เขียนอะไรลงไปเลยสักแถว — ข้อมูลที่เข้าไปครึ่งเดียวแก้ยากกว่าไม่เข้าเลย
          </div>
        </div>

        {error && <Notice kind="error">{error}</Notice>}
        {msg && <Notice kind="ok">{msg}</Notice>}

        {kind === 'staff' && (
          <Notice kind="info">
            ไฟล์บุคลากร <strong>ตั้งบทบาทไม่ได้เลยสักค่า</strong> เพราะทุกบทบาทเห็นข้อมูล
            ทั้งวิทยาลัย ต้องแต่งตั้งทีละคนหลังนำเข้า — ส่วน <code>is_teacher</code> ตั้งได้
            (ค่าเริ่มต้นคือไม่ใช่ครู)
          </Notice>
        )}
      </Card>

      <TableCard title="ประวัติการนำเข้า">
        <AsyncView state={batches} empty="ยังไม่เคยนำเข้าข้อมูลชนิดนี้">
          {(list) => (
            <table>
              <thead>
                <tr>
                  <th>ไฟล์ต้นทาง</th>
                  <th style={{ width: 120 }}>ชนิด</th>
                  <th className="num" style={{ width: 90 }}>ทั้งหมด</th>
                  <th className="num" style={{ width: 90 }}>ผ่าน</th>
                  <th className="num" style={{ width: 90 }}>ผิด</th>
                  <th style={{ width: 170 }}>สถานะ</th>
                  <th style={{ width: 170 }}>เมื่อ</th>
                </tr>
              </thead>
              <tbody>
                {list.map((b) => {
                  const st = STATUS[b.status];
                  return (
                    <tr key={b.id}>
                      <td>{b.source_name}</td>
                      <td>{KIND[b.kind] ?? b.kind}</td>
                      <td className="num">{b.total_rows}</td>
                      <td className="num">{b.ok_rows}</td>
                      <td className="num">
                        {b.error_rows > 0 ? (
                          <Badge kind="danger">{b.error_rows}</Badge>
                        ) : (
                          b.error_rows
                        )}
                      </td>
                      <td>
                        <Badge kind={st?.kind ?? 'default'}>{st?.label ?? b.status}</Badge>
                      </td>
                      <td>{thaiDateTime(b.applied_at ?? b.created_at ?? null)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}
