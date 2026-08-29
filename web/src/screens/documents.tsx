/**
 * ออกเอกสารการศึกษา
 *
 * ─── ทำไมปุ่มพิมพ์ซ้ำไม่ยิง issue ใหม่ ───
 * `issue_document()` กินเลขที่เอกสารหนึ่งเลขทุกครั้งที่เรียก การกดพิมพ์ซ้ำ
 * แล้วออกใบใหม่จึงทำให้เลขที่เดินไปเรื่อย ๆ โดยที่วิทยาลัยตอบไม่ได้ว่า
 * เอกสารเลขนั้นหายไปไหน — การพิมพ์ซ้ำต้องอ่านจาก `payload` ที่ตรึงไว้
 * ตั้งแต่วันที่ออกเท่านั้น (ดูหลักข้อ 5 ใน CLAUDE.md)
 *
 * ─── ทำไมยกเลิกต้องมีเหตุผล ───
 * `issued_document` แก้และลบไม่ได้ ยกเลิกได้อย่างเดียว และเหตุผลคือสิ่งเดียว
 * ที่อธิบายย้อนหลังได้ว่าทำไมเอกสารเลขนั้นถึงใช้ไม่ได้
 */
import { useState } from 'react';
import { api } from '../core/api';
import { thaiDate, thaiDateTime } from '../core/fmt';
import { href } from '../core/router';
import type { Role } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead,
  PrintButton, PrintPaperControl, printQuery, readPrintPaper, RestrictedNotice, TableCard,
  useAsync, useCan, type PrintPaper,
} from '../ui/kit';

const DOCUMENTS_ROLES: Role[] = ['registrar', 'academic', 'director', 'admin'];

const KIND: Record<string, string> = {
  transcript: 'ระเบียนแสดงผลการเรียน (รบ.)',
  certificate: 'ใบประกาศนียบัตร',
  certification: 'หนังสือรับรอง',
  grade_report: 'สมุดพก',
  cumulative_record: 'ระเบียนสะสม (ปพ.8)',
};

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
}

interface Doc {
  id: string;
  kind: string;
  doc_no: string;
  copy_no: number;
  issued_on: string;
  voided_at: string | null;
  void_reason: string | null;
}

export function DocumentsScreen() {
  const canUse = useCan(...DOCUMENTS_ROLES);
  const [q, setQ] = useState('');
  const [studentId, setStudentId] = useState('');
  const [kind, setKind] = useState('transcript');
  const [reason, setReason] = useState('');
  const [paper, setPaper] = useState<PrintPaper>(readPrintPaper);

  const students = useAsync(
    () => (canUse ? api.get<StudentRow[]>(`/students?limit=200${q ? `&q=${encodeURIComponent(q)}` : ''}`) : Promise.resolve([])),
    [canUse, q],
  );
  const docs = useAsync(
    () => (canUse && studentId ? api.get<Doc[]>(`/documents/students/${studentId}`) : Promise.resolve([])),
    [canUse, studentId],
  );

  const student = students.data?.find((s) => s.id === studentId);

  return (
    <>
      <PageHead title="ออกเอกสารการศึกษา" sub={<a href={href('/registry')}>← ศูนย์งานทะเบียน</a>} />

      {!canUse ? (
        <RestrictedNotice roles={DOCUMENTS_ROLES} />
      ) : (
      <>
      <Card>
        <div className="row">
          <Field label="ค้นหานักศึกษา">
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="รหัสหรือชื่อ" />
          </Field>
          <label className="field" style={{ flex: 2 }}>
            <span>นักศึกษา</span>
            <AsyncView state={students}>
              {(rows) => (
                <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                  <option value="">— เลือกนักศึกษา —</option>
                  {rows.map((s) => (
                    <option key={s.id} value={s.id}>
                      {s.student_code} {s.full_name}
                    </option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
        </div>
      </Card>

      {studentId && (
        <>
          <Card title={`ออกเอกสารใหม่ — ${student?.full_name ?? ''}`}>
            <div className="row">
              <label className="field" style={{ flex: 2 }}>
                <span>ประเภทเอกสาร</span>
                <select value={kind} onChange={(e) => setKind(e.target.value)}>
                  {Object.entries(KIND).map(([v, l]) => (
                    <option key={v} value={v}>{l}</option>
                  ))}
                </select>
              </label>
              <div className="shrink">
                <ActionButton
                  className="primary"
                  confirm="ออกเอกสารใหม่จะกินเลขที่หนึ่งเลข และยกเลิกได้แต่ลบไม่ได้ ยืนยันหรือไม่"
                  onRun={() => api.post('/documents/issue', { studentId, kind })}
                  onDone={() => docs.reload()}
                >
                  ออกเอกสาร
                </ActionButton>
              </div>
              <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
                เนื้อหาทั้งใบถูกตรึงไว้ตั้งแต่วันที่ออก การพิมพ์ซ้ำจะได้ใบเดิมเสมอ
                ไม่ใช่ข้อมูลวันนี้
              </div>
              {/*
                ตัวเลือกกระดาษไม่ได้อยู่ใน payload โดยตั้งใจ — กระดาษที่ใส่
                ในเครื่องพิมพ์วันนี้กับระยะที่ถาดป้อนเหลื่อม เป็นเรื่องของการ
                พิมพ์ครั้งนี้ ใบเดิมต้องพิมพ์ลงกระดาษเปล่าได้ในปีหน้า
              */}
              <PrintPaperControl value={paper} onChange={setPaper} />
            </div>
          </Card>

          <TableCard title="เอกสารที่เคยออกให้นักศึกษาคนนี้">
            <AsyncView state={docs} empty="ยังไม่เคยออกเอกสารให้นักศึกษาคนนี้">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 170 }}>เลขที่</th>
                      <th>ประเภท</th>
                      <th className="num" style={{ width: 70 }}>ฉบับที่</th>
                      <th style={{ width: 120 }}>วันที่ออก</th>
                      <th style={{ width: 110 }}>สถานะ</th>
                      <th style={{ width: 230 }}>การทำงาน</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((d) => (
                      <tr key={d.id}>
                        <td className="mono">{d.doc_no}</td>
                        <td>{KIND[d.kind] ?? d.kind}</td>
                        <td className="num">{d.copy_no}</td>
                        <td>{thaiDate(d.issued_on)}</td>
                        <td>
                          {d.voided_at ? (
                            <Badge kind="danger">ยกเลิกแล้ว</Badge>
                          ) : (
                            <Badge kind="ok">ใช้ได้</Badge>
                          )}
                        </td>
                        <td>
                          {d.voided_at ? (
                            <span style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>
                              {thaiDateTime(d.voided_at)} · {d.void_reason}
                            </span>
                          ) : (
                            <>
                              <PrintButton
                                path={`/documents/${d.id}/print${printQuery(paper)}`}
                              >
                                พิมพ์จากต้นฉบับ
                              </PrintButton>
                              {' · '}
                              <VoidButton id={d.id} onDone={() => docs.reload()} reason={reason} setReason={setReason} />
                            </>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </AsyncView>
          </TableCard>

          <Notice kind="info">
            ลิงก์ “พิมพ์จากต้นฉบับ” อ่านจาก payload ที่ตรึงไว้ตอนออกเอกสาร
            ไม่ได้คำนวณใหม่ — เอกสารที่ออกไปแล้วจึงตรงกับที่นักศึกษาถืออยู่เสมอ
            แม้ผลการเรียนจะเปลี่ยนภายหลัง
          </Notice>
        </>
      )}
      </>
      )}
    </>
  );
}

function VoidButton({
  id,
  onDone,
  reason,
  setReason,
}: {
  id: string;
  onDone: () => void;
  reason: string;
  setReason: (v: string) => void;
}) {
  const [open, setOpen] = useState(false);

  if (!open) {
    return (
      <button className="link" onClick={() => setOpen(true)}>
        ยกเลิกเอกสาร
      </button>
    );
  }

  return (
    <span style={{ display: 'inline-flex', gap: 6, alignItems: 'center' }}>
      <input
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="เหตุผลที่ยกเลิก (บังคับ)"
        style={{ width: 200 }}
        autoFocus
      />
      <ActionButton
        className="danger"
        onRun={() => api.post(`/documents/${id}/void`, { reason: reason.trim() })}
        onDone={() => {
          setOpen(false);
          setReason('');
          onDone();
        }}
      >
        ยืนยัน
      </ActionButton>
      <button className="link" onClick={() => setOpen(false)}>
        ยกเลิก
      </button>
    </span>
  );
}
