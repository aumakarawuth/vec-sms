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
import { parseCsv } from '../core/csv';
import { thaiDateTime } from '../core/fmt';
import { mapGenericExcelRows } from '../core/generic-import-template';
import { mapGradeImportRow } from '../core/grade-import-template';
import { useScope } from '../core/scope';
import { isBlankSisaCsvRow, mapSisaCsvRow } from '../core/student-import-sisa-csv-template';
import { isBlankStudentRow, mapStudentImportRow, STUDENT_IMPORT_DATA_START_ROW } from '../core/student-import-template';
import type { Role } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, RestrictedNotice, TableCard, useAsync, useCan,
} from '../ui/kit';

const IMPORT_ROLES: Role[] = ['registrar', 'academic', 'director', 'admin'];
import { readXlsxFirstSheet } from '../core/xlsx';

interface Problem {
  row_no: number;
  errors: string[];
}

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
  problems?: Problem[];
}

const KIND: Record<string, string> = {
  student: 'นักศึกษา',
  staff: 'บุคลากร',
  academic_history: 'ประวัติการเรียนเดิม',
  grade: 'ผลการเรียน',
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
  academic_history:
    'student_code,source_th,term_label,course_code,course_name_th,credits,grade_symbol,grade_point,transfer_kind,mapped_course_code,note',
};

type ImportRow = { rowNo: number; payload: Record<string, string> };

export function ImportScreen() {
  const canUse = useCan(...IMPORT_ROLES);
  const scope = useScope();
  const admittedYearBe = scope.year ? String(scope.year.year_be) : '';
  const [kind, setKind] = useState('student');
  const [sourceName, setSourceName] = useState('');
  const [excelRows, setExcelRows] = useState<ImportRow[]>([]);
  const [fileBusy, setFileBusy] = useState(false);
  const [fileError, setFileError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [problems, setProblems] = useState<Problem[]>([]);
  const [errorRowsTotal, setErrorRowsTotal] = useState(0);
  const [skippedGradeRows, setSkippedGradeRows] = useState(0);
  const [lastFileUsedScopeYear, setLastFileUsedScopeYear] = useState(false);

  const batches = useAsync(
    () => (canUse ? api.get<Batch[]>(`/import${qs({ kind })}`) : Promise.resolve([])),
    [canUse, kind],
  );

  const rows = excelRows;
  const fileDisabled = fileBusy;
  // นักศึกษารับได้สองแบบ อ่านนามสกุลไฟล์เพื่อเลือกตัวแมปให้เองแทนการให้เลือกเมนูซ้ำ
  const isCsvKind = kind === 'grade';

  async function handleExcelFile(file: File) {
    setFileBusy(true);
    setFileError(null);
    setMsg(null);
    setError(null);
    setProblems([]); setErrorRowsTotal(0); setSkippedGradeRows(0); setLastFileUsedScopeYear(false);
    try {
      let mapped: ImportRow[];
      if (kind === 'student' && /\.csv$/i.test(file.name)) {
        const rows = parseCsv(await file.text());
        const dataRows = rows.slice(1).filter((r) => !isBlankSisaCsvRow(r));
        if (dataRows.length === 0) {
          throw new Error('ไม่พบแถวข้อมูลในไฟล์ (แถวแรกต้องเป็นหัวตาราง แล้วข้อมูลเริ่มแถวที่ 2)');
        }
        mapped = dataRows.map((r, i) => ({ rowNo: i + 1, payload: mapSisaCsvRow(r) }));
      } else if (kind === 'grade') {
        const rows = parseCsv(await file.text());
        const skipped0 = rows.length > 0 ? rows.length - 1 : 0;
        let skippedUngraded = 0;
        mapped = [];
        for (const r of rows.slice(1)) {
          const payload = mapGradeImportRow(r);
          if (payload) {
            mapped.push({ rowNo: mapped.length + 1, payload });
          } else {
            skippedUngraded += 1;
          }
        }
        if (mapped.length === 0) {
          throw new Error(
            skipped0 === 0
              ? 'ไม่พบแถวข้อมูลในไฟล์ (แถวแรกต้องเป็นหัวตาราง แล้วข้อมูลเริ่มแถวที่ 2)'
              : 'ทุกแถวยังไม่มีผลการเรียน (คอลัมน์ "ผลการเรียน" เป็น "-" หรือไม่มีคะแนน) ไม่มีอะไรให้นำเข้า',
          );
        }
        setSkippedGradeRows(skippedUngraded);
      } else if (kind === 'student') {
        if (!admittedYearBe) {
          throw new Error(
            'ไฟล์แม่แบบ .xlsx ไม่มีคอลัมน์ปีที่เข้าศึกษา — เลือกปีการศึกษาที่เมนูด้านบนก่อน แล้วค่อยเลือกไฟล์ใหม่อีกครั้ง',
          );
        }
        const sheet = await readXlsxFirstSheet(file);
        const dataRows = sheet.slice(STUDENT_IMPORT_DATA_START_ROW).filter((r) => !isBlankStudentRow(r ?? []));
        if (dataRows.length === 0) {
          throw new Error('ไม่พบแถวข้อมูลในไฟล์ (ต้องเริ่มที่แถวที่ 3 ตามแม่แบบ)');
        }
        mapped = dataRows.map((r, i) => ({
          rowNo: i + 1,
          payload: mapStudentImportRow(r ?? [], admittedYearBe),
        }));
        setLastFileUsedScopeYear(true);
      } else {
        const sheet = await readXlsxFirstSheet(file);
        mapped = mapGenericExcelRows(sheet);
        if (mapped.length === 0) {
          throw new Error(
            'ไม่พบแถวข้อมูล — แถวแรกของชีตต้องเป็นหัวตาราง (ดูตัวอย่างชื่อคอลัมน์ด้านล่าง) แล้วข้อมูลเริ่มแถวที่ 2',
          );
        }
      }
      setExcelRows(mapped);
      setSourceName(file.name);
    } catch (e) {
      setExcelRows([]);
      setFileError(e instanceof Error ? e.message : 'อ่านไฟล์ไม่สำเร็จ');
    } finally {
      setFileBusy(false);
    }
  }

  async function run(apply: boolean, rowsOverride?: ImportRow[]) {
    const rowsToSend = rowsOverride ?? rows;
    setBusy(true);
    setError(null);
    setMsg(null);
    setProblems([]); setErrorRowsTotal(0);
    try {
      const batch = await api.post<{ id: string }>('/import', {
        kind,
        sourceName: sourceName.trim() || 'ไฟล์ที่อัปโหลด',
        rows: rowsToSend,
      });
      const v = await api.post<Batch>(`/import/${batch.id}/validate`);
      if (v.error_rows > 0) {
        setError(`ตรวจแล้วพบแถวผิด ${v.error_rows} จาก ${v.total_rows} แถว — ยังไม่นำเข้า`);
        setProblems(v.problems ?? []);
        setErrorRowsTotal(v.error_rows);
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
      setExcelRows([]);
      batches.reload();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'นำเข้าไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  }

  /**
   * ตัดแถวที่มีปัญหาออกแล้วนำเข้าแถวที่เหลือทันทีในคลิกเดียว — ไม่ต้องกด
   * "ตรวจแล้วนำเข้าจริง" ซ้ำอีกรอบ เพราะรายชื่อแถวที่ถูกตัดออกก็โชว์อยู่
   * ในตารางด้านล่างอยู่แล้วก่อนกดปุ่มนี้ ไม่มีอะไรถูกซ่อนจากผู้ใช้
   */
  async function skipProblemRows() {
    const bad = new Set(problems.map((p) => p.row_no));
    const remaining = excelRows.filter((r) => !bad.has(r.rowNo));
    setExcelRows(remaining);
    setError(null);
    await run(true, remaining);
  }

  return (
    <>
      <PageHead title="นำเข้าข้อมูล" />

      {!canUse ? (
        <RestrictedNotice roles={IMPORT_ROLES} />
      ) : (
      <>
      <Card title="วางข้อมูลจากตาราง">
        <div className="row">
          <Field label="ชนิดข้อมูล">
            <select
              value={kind}
              onChange={(e) => {
                setKind(e.target.value);
                setExcelRows([]);
                setFileError(null);
                setProblems([]); setErrorRowsTotal(0); setSkippedGradeRows(0); setLastFileUsedScopeYear(false);
                setError(null);
              }}
            >
              <option value="student">นักศึกษา</option>
              <option value="staff">บุคลากร</option>
              <option value="academic_history">ประวัติการเรียนเดิม</option>
              <option value="grade">ผลการเรียน</option>
            </select>
          </Field>
        </div>

        <Card
          title={
            kind === 'grade'
              ? 'อัปโหลดไฟล์ .csv ผลการเรียน (finalgrades.csv)'
              : kind === 'student'
                ? 'อัปโหลดไฟล์นักศึกษา (.xlsx ตามแม่แบบ หรือ .csv จากระบบทะเบียนกลาง)'
                : 'อัปโหลดไฟล์ Excel — แถวแรกเป็นหัวตาราง'
          }
        >
          <Field label={kind === 'student' ? 'ไฟล์ .xlsx หรือ .csv' : isCsvKind ? 'ไฟล์ .csv' : 'ไฟล์ .xlsx'}>
            <input
              type="file"
              accept={kind === 'student' ? '.xlsx,.csv' : isCsvKind ? '.csv' : '.xlsx'}
              disabled={fileDisabled}
              onChange={(e) => {
                const f = e.target.files?.[0];
                e.target.value = '';
                if (f) void handleExcelFile(f);
              }}
            />
          </Field>

          {kind === 'student' && (
            <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
              เลือกไฟล์ตามระบบชนิดใดก็ได้ ระบบดูจากนามสกุลไฟล์เอง — ไฟล์ .xlsx (แม่แบบ
              ImportFull_VocationalEducation.xlsx) ไม่มีคอลัมน์ปีที่เข้าศึกษา ต้องเลือกปีการศึกษาที่เมนู
              ด้านบนก่อน ส่วนไฟล์ .csv จากระบบทะเบียนกลางมีคอลัมน์นี้อยู่แล้วในไฟล์ ไม่ต้องเลือกปีก่อน
              {admittedYearBe ? '' : ' (ยังไม่ได้เลือกปีการศึกษา — จำเป็นเฉพาะไฟล์ .xlsx เท่านั้น)'}
            </div>
          )}

          {kind === 'grade' && (
            <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
              หัวตาราง: ภาคเรียน,ปี,รหัส,รหัสวิชา,ชื่อวิชา,คะแนน,ผลการเรียน,หน่วยกิต — ข้ามแถวที่ยังไม่มี
              ผลการเรียน ("-") หรือไม่มีคะแนนตัวเลขให้อัตโนมัติ นำเข้าเป็นคะแนนในสมุดคะแนนของแต่ละ
              กลุ่มเรียน แล้วยังต้องกด "ส่งเกรด" และผ่านสายอนุมัติตามปกติที่หน้าสมุดคะแนน
            </div>
          )}

          {kind !== 'student' && kind !== 'grade' && (
            <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
              แถวแรกของชีตต้องเป็นชื่อคอลัมน์ตรงตามนี้ (คัดลอกไปวางเป็นหัวตารางในไฟล์ Excel ได้เลย)
              <br />
              <code style={{ fontSize: 11 }}>{TEMPLATE[kind]}</code>
            </div>
          )}

          {fileBusy && <Notice kind="info">กำลังอ่านไฟล์…</Notice>}
          {fileError && <Notice kind="error">{fileError}</Notice>}
          {excelRows.length > 0 && (
            <Notice kind="ok">
              อ่านไฟล์ได้ {excelRows.length} แถว
              {lastFileUsedScopeYear && ` (ปีที่เข้าศึกษา ${admittedYearBe})`}
              {kind === 'grade' && skippedGradeRows > 0 && ` (ข้ามแถวที่ยังไม่มีผลการเรียนไป ${skippedGradeRows} แถว)`} —
              ตรวจสอบด้านล่างแล้วกดนำเข้า
              {kind === 'student' &&
                ' (คอลัมน์ประเภทวิชา/สาขาวิชา/หลักสูตร/ระดับชั้น/ห้องในไฟล์ไม่ได้ผูกอัตโนมัติ ' +
                  'ต้องไปจัดที่หน้า "ลงทะเบียนเรียน" อีกที — ดูเหตุผลในหมายเหตุของแม่แบบ)'}{' '}
              <button className="link" onClick={() => { setExcelRows([]); setProblems([]); setErrorRowsTotal(0); setSkippedGradeRows(0); setLastFileUsedScopeYear(false); setError(null); }}>
                ล้างไฟล์ที่อ่านไว้
              </button>
            </Notice>
          )}
        </Card>

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

        {problems.length > 0 && (
          <Card title={`แถวที่มีปัญหา (${problems.length}${errorRowsTotal > problems.length ? ` จาก ${errorRowsTotal}` : ''})`}>
            <div className="row">
              <button className="primary" disabled={busy} onClick={() => void skipProblemRows()}>
                {busy ? 'กำลังทำ…' : `ข้ามแถวที่มีปัญหา แล้วนำเข้าเฉพาะแถวที่เหลือ (${rows.length - problems.length} แถว)`}
              </button>
            </div>
            {errorRowsTotal > problems.length && (
              <p className="hint">
                แสดงได้สูงสุด {problems.length} แถวต่อรอบ — ถ้าตัดรอบนี้แล้วยังไม่ผ่าน ให้กดข้ามซ้ำอีกรอบเพื่อไล่แถวที่เหลือ
              </p>
            )}
            <table>
              <thead>
                <tr>
                  <th style={{ width: 70 }}>แถวที่</th>
                  <th>ปัญหา</th>
                </tr>
              </thead>
              <tbody>
                {problems.map((p) => (
                  <tr key={p.row_no}>
                    <td className="num">{p.row_no}</td>
                    <td>{p.errors.join(' · ')}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        )}

        {kind === 'staff' && (
          <Notice kind="info">
            ไฟล์บุคลากร <strong>ตั้งบทบาทไม่ได้เลยสักค่า</strong> เพราะทุกบทบาทเห็นข้อมูล
            ทั้งวิทยาลัย ต้องแต่งตั้งทีละคนหลังนำเข้า — ส่วน <code>is_teacher</code> ตั้งได้
            (ค่าเริ่มต้นคือไม่ใช่ครู)
          </Notice>
        )}

        {kind === 'academic_history' && (
          <Notice kind="info">
            แต่ละแถวต้องเป็นของ<strong>นักศึกษาที่มีอยู่ในระบบแล้ว</strong> (นำเข้านักศึกษา
            ก่อนแล้วค่อยนำเข้าประวัติ) · <code>transfer_kind</code> เว้นว่างได้ ค่าเริ่มต้นคือ
            เทียบโอนความรู้และประสบการณ์ (ให้หน่วยกิตอย่างเดียว ไม่นับ GPA) — ใส่{' '}
            <code>transferred_grade</code> เมื่อยกเกรดเดิมมาด้วยเพื่อให้นับ GPA ·{' '}
            <code>mapped_course_code</code> เว้นว่างได้ ถ้าระบุต้องตรงกับรหัสวิชาที่มีในหลักสูตร
            ของวิทยาลัยนี้
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
                  <th style={{ width: 70 }} />
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
                      <td>
                        {b.status !== 'applied' && (
                          <ActionButton
                            className="ghost danger"
                            confirm={`ลบรอบนำเข้า "${b.source_name}" นี้ใช่หรือไม่ — ยังไม่ได้นำเข้าจริง ลบแล้วเรียกคืนไม่ได้`}
                            onRun={() => api.del(`/import/${b.id}`)}
                            onDone={() => batches.reload()}
                          >
                            ลบ
                          </ActionButton>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
      </>
      )}
    </>
  );
}
