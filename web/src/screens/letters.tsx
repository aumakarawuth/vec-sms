/**
 * หนังสือถึงผู้ปกครองและใบรับรองความประพฤติ
 *
 * ─── ทำไมเริ่มจากรายชื่อ ไม่ใช่จากช่องค้นหา ───
 * งานปกครองไม่ได้เปิดหน้านี้มาเพื่อออกหนังสือให้คนที่คิดไว้แล้ว แต่เปิดมา
 * เพื่อ**หาว่าต้องออกให้ใครบ้าง** — `absence_notice_candidates()` ตอบคำถามนั้น
 * ตรง ๆ พร้อมบอกว่าใครเคยได้รับไปแล้วเมื่อไร ถ้าให้ค้นหาทีละคน เจ้าหน้าที่
 * ต้องรู้ชื่อก่อน ซึ่งเป็นสิ่งที่ระบบควรบอก ไม่ใช่สิ่งที่คนต้องจำ
 *
 * ─── ทำไมช่อง "เคยส่งเมื่อ" สำคัญ ───
 * ว่างแปลว่า**ยังไม่เคยส่ง** ไม่ใช่ส่งแล้วไม่ได้ผล ถ้าไม่แสดง เจ้าหน้าที่จะ
 * ส่งซ้ำคนเดิมทุกสัปดาห์ แล้วผู้ปกครองจะเลิกอ่าน
 *
 * ─── ทำไมเปิดหน้าพิมพ์ในแท็บใหม่ ───
 * เส้นทางพิมพ์คืน HTML ตรง ๆ ไม่ใช่ JSON การเปิดในแท็บใหม่ทำให้กด Ctrl+P
 * ได้ทันทีและงานที่ค้างในหน้านี้ไม่หาย
 */
import { useState } from 'react';
import { api } from '../core/api';
import { num, thaiDate } from '../core/fmt';
import type { Role } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, RestrictedNotice, TableCard, useAsync, useCan,
  PrintPaperControl,
  printQuery,
  readPrintPaper,
  type PrintPaper,
} from '../ui/kit';
import { TermSelect, useTermPicker } from '../ui/term-picker';

/**
 * POST /documents/letters (ออกหนังสือ) ผูก registrar/academic/student_affairs/
 * director/admin — GET /documents/absence-candidates เปิดกว้างกว่า (มี teacher
 * ด้วย) แต่ GET /documents/students/:id (ประวัติที่เคยออก) ไม่มี student_affairs
 * เลยด้วยซ้ำ หน้านี้จึงกันด้วยชุดที่ "ออกหนังสือได้จริง" ซึ่งเป็นจุดประสงค์หลัก
 * ของหน้านี้ — teacher เห็นได้แค่รายชื่อผู้ที่เวลาเรียนต่ำกว่าเกณฑ์แต่ออก
 * หนังสือไม่ได้อยู่แล้ว จึงไม่ได้เสียฟังก์ชันที่เคยใช้ได้จริง
 */
const LETTERS_ROLES: Role[] = ['registrar', 'academic', 'student_affairs', 'director', 'admin'];

interface Candidate {
  student_id: string;
  student_code: string;
  full_name: string;
  courses_at_risk: number;
  worst_pct: string | number;
  last_notice_on: string | null;
}

interface IssuedLetter {
  id: string;
  kind: string;
  doc_no: string;
  copy_no: number;
  issued_on: string;
  voided_at: string | null;
}

const LETTER_KIND: Record<string, string> = {
  absence_notice: 'จดหมายแจ้งขาดเรียน',
  guardian_invitation: 'หนังสือเชิญผู้ปกครอง',
  conduct_certificate: 'ใบรับรองความประพฤติ',
};

const ALL_KIND: Record<string, string> = {
  ...LETTER_KIND,
  transcript: 'ระเบียนแสดงผลการเรียน',
  certificate: 'ใบประกาศนียบัตร',
  certification: 'หนังสือรับรอง',
  grade_report: 'สมุดพก',
  cumulative_record: 'ระเบียนสะสม (ปพ.8)',
};

export function LettersScreen() {
  const canUse = useCan(...LETTERS_ROLES);
  const { terms, termId, setTerm } = useTermPicker();
  const [result, setResult] = useState<string | null>(null);

  const candidates = useAsync(
    () =>
      canUse && termId
        ? api.get<Candidate[]>(`/documents/absence-candidates/${termId}`)
        : Promise.resolve([]),
    [canUse, termId],
  );

  // นักศึกษาที่กำลังทำงานด้วย — เลือกจากรายชื่อหรือจากผลค้นหา
  const [studentId, setStudentId] = useState('');
  const [studentLabel, setStudentLabel] = useState('');
  const issued = useAsync(
    () =>
      canUse && studentId
        ? api.get<IssuedLetter[]>(`/documents/students/${studentId}`)
        : Promise.resolve([]),
    [canUse, studentId],
  );

  const [kind, setKind] = useState('guardian_invitation');
  const [meetOn, setMeetOn] = useState('');
  const [meetTime, setMeetTime] = useState('');
  const [placeTh, setPlaceTh] = useState('');
  const [withTh, setWithTh] = useState('');
  const [reasonTh, setReasonTh] = useState('');
  const [purposeTh, setPurposeTh] = useState('');
  const [note, setNote] = useState('');

  const [paper, setPaper] = useState<PrintPaper>(readPrintPaper);

  function openPrint(id: string) {
    // เปิดผ่าน api.openPrintable เพราะลิงก์ตรงตั้งเฮดเดอร์ token ไม่ได้
    void api.openPrintable(`/documents/${id}/print${printQuery(paper)}`);
  }

  function pick(c: Candidate) {
    setStudentId(c.student_id);
    setStudentLabel(`${c.student_code} ${c.full_name}`);
    setKind('absence_notice');
  }

  return (
    <>
      <PageHead
        title="หนังสือถึงผู้ปกครอง"
        actions={
          <div style={{ width: 240 }}>
            <AsyncView state={terms}>
              {(list) => <TermSelect terms={list} termId={termId} onChange={setTerm} />}
            </AsyncView>
          </div>
        }
      />

      {!canUse ? (
        <RestrictedNotice roles={LETTERS_ROLES} />
      ) : (
      <>
      <Notice kind="info">
        ตัวเลขเวลาเรียนและคะแนนความประพฤติบนหนังสือ <strong>ตรึง ณ วันที่ออก</strong> —
        พิมพ์ซ้ำจะได้ใบเดิมเสมอ ถ้าตัวเลขเปลี่ยนไปแล้วต้องออกใบใหม่
        (ซึ่งกินเลขที่เอกสารเพิ่มหนึ่งเลข)
      </Notice>

      {/*
        หนังสือถึงผู้ปกครองมักพิมพ์ลงกระดาษหัวจดหมายของวิทยาลัย ตัวเลือกนี้
        จึงอยู่ตรงนี้ด้วย — ค่าเก็บที่เครื่อง ไม่ใช่ที่เอกสาร
      */}
      <Card>
        <PrintPaperControl value={paper} onChange={setPaper} />
      </Card>

      {result && <Notice kind="ok">{result}</Notice>}

      <TableCard
        title="ผู้ที่เวลาเรียนต่ำกว่าเกณฑ์ในภาคเรียนนี้"
        actions={
          <span style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>
            เรียงจากคนที่คาดการณ์ต่ำที่สุด
          </span>
        }
      >
        <AsyncView state={candidates} empty="ไม่มีนักศึกษาที่เวลาเรียนต่ำกว่าเกณฑ์ในภาคเรียนนี้">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                  <th>ชื่อ — นามสกุล</th>
                  <th className="num" style={{ width: 110 }}>วิชาที่ตกเกณฑ์</th>
                  <th className="num" style={{ width: 120 }}>ต่ำสุด (คาดการณ์)</th>
                  <th style={{ width: 160 }}>เคยส่งจดหมายเมื่อ</th>
                  <th style={{ width: 230 }}>การทำงาน</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((c) => (
                  <tr key={c.student_id}>
                    <td className="mono">{c.student_code}</td>
                    <td>{c.full_name}</td>
                    <td className="num">{c.courses_at_risk}</td>
                    <td className="num">{num(c.worst_pct, 1)}%</td>
                    <td>
                      {c.last_notice_on
                        ? <Badge kind="info">{thaiDate(c.last_notice_on)}</Badge>
                        : <Badge kind="warn">ยังไม่เคยส่ง</Badge>}
                    </td>
                    <td>
                      <span style={{ display: 'inline-flex', gap: 8 }}>
                        <ActionButton
                          className="primary"
                          confirm={`ออกจดหมายแจ้งขาดเรียนให้ ${c.full_name} — กินเลขที่เอกสารหนึ่งเลข ยืนยันหรือไม่`}
                          onRun={() =>
                            api.post<{ id: string; doc_no: string }>('/documents/letters', {
                              studentId: c.student_id, kind: 'absence_notice', termId,
                            })
                          }
                          onDone={(r) => {
                            const d = r as { id: string; doc_no: string };
                            setResult(`ออกจดหมายเลขที่ ${d.doc_no} แล้ว`);
                            candidates.reload();
                            openPrint(d.id);
                          }}
                        >
                          ออกจดหมาย + พิมพ์
                        </ActionButton>
                        <button onClick={() => pick(c)}>เลือกเพื่อออกใบอื่น</button>
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      <Card title="ออกหนังสือฉบับอื่น">
        <div className="row">
          <Field label="นักศึกษาที่เลือก">
            <input
              value={studentLabel || '— กด “เลือกเพื่อออกใบอื่น” จากตารางด้านบน —'}
              readOnly
            />
          </Field>
          <Field label="ประเภทหนังสือ">
            <select value={kind} onChange={(e) => setKind(e.target.value)}>
              {Object.entries(LETTER_KIND).map(([k, v]) => (
                <option key={k} value={k}>{v}</option>
              ))}
            </select>
          </Field>
        </div>

        {kind === 'guardian_invitation' && (
          <div className="row">
            <Field label="วันนัดพบ">
              <input type="date" value={meetOn} onChange={(e) => setMeetOn(e.target.value)} />
            </Field>
            <Field label="เวลา">
              <input
                value={meetTime}
                onChange={(e) => setMeetTime(e.target.value)}
                placeholder="เช่น 10:00 น."
              />
            </Field>
            <Field label="สถานที่">
              <input
                value={placeTh}
                onChange={(e) => setPlaceTh(e.target.value)}
                placeholder="เช่น ห้องงานปกครอง อาคาร 1"
              />
            </Field>
            <Field label="พบกับ">
              <input
                value={withTh}
                onChange={(e) => setWithTh(e.target.value)}
                placeholder="เว้นว่างจะใช้ชื่อครูที่ปรึกษา"
              />
            </Field>
          </div>
        )}

        {kind === 'guardian_invitation' && (
          <div className="row">
            <Field label="เรื่องที่จะปรึกษา">
              <input value={reasonTh} onChange={(e) => setReasonTh(e.target.value)} />
            </Field>
          </div>
        )}

        {kind === 'conduct_certificate' && (
          <div className="row">
            <Field label="ออกให้เพื่อ">
              <input
                value={purposeTh}
                onChange={(e) => setPurposeTh(e.target.value)}
                placeholder="เช่น สมัครงาน · ศึกษาต่อ"
              />
            </Field>
          </div>
        )}

        <div className="row">
          <Field label="หมายเหตุ (พิมพ์ลงบนหนังสือ)">
            <input value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          <div className="shrink">
            <ActionButton
              className="primary"
              confirm="ออกหนังสือฉบับนี้ — กินเลขที่เอกสารหนึ่งเลข ยืนยันหรือไม่"
              onRun={() =>
                api.post<{ id: string; doc_no: string }>('/documents/letters', {
                  studentId,
                  kind,
                  termId: kind === 'absence_notice' ? termId : undefined,
                  meetOn: meetOn || undefined,
                  meetTime: meetTime || undefined,
                  placeTh: placeTh || undefined,
                  withTh: withTh || undefined,
                  reasonTh: reasonTh || undefined,
                  purposeTh: purposeTh || undefined,
                  note: note || undefined,
                })
              }
              onDone={(r) => {
                const d = r as { id: string; doc_no: string };
                setResult(`ออก${LETTER_KIND[kind]}เลขที่ ${d.doc_no} แล้ว`);
                issued.reload();
                openPrint(d.id);
              }}
            >
              ออกหนังสือ + พิมพ์
            </ActionButton>
          </div>
        </div>

        {kind === 'guardian_invitation' && !meetOn && (
          <Notice kind="warn">
            หนังสือเชิญผู้ปกครอง<strong>ต้องระบุวันนัดพบ</strong> — ถ้าเว้นไว้เติมด้วยปากกา
            ทีหลัง จะไม่มีหลักฐานว่าเคยนัดวันไหน เมื่อผู้ปกครองบอกว่าไม่เคยได้รับแจ้ง
          </Notice>
        )}
      </Card>

      {studentId && (
        <TableCard title={`เอกสารที่เคยออกให้ ${studentLabel}`}>
          <AsyncView state={issued} empty="ยังไม่เคยออกเอกสารให้นักศึกษารายนี้">
            {(rows) => (
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 220 }}>ประเภท</th>
                    <th style={{ width: 130 }}>เลขที่</th>
                    <th style={{ width: 140 }}>วันที่ออก</th>
                    <th style={{ width: 110 }}>สถานะ</th>
                    <th style={{ width: 120 }} />
                  </tr>
                </thead>
                <tbody>
                  {rows.map((d) => (
                    <tr key={d.id}>
                      <td>{ALL_KIND[d.kind] ?? d.kind}</td>
                      <td className="mono">{d.doc_no}</td>
                      <td>{thaiDate(d.issued_on)}</td>
                      <td>
                        {d.voided_at
                          ? <Badge kind="danger">ยกเลิกแล้ว</Badge>
                          : <Badge kind="ok">ใช้ได้</Badge>}
                      </td>
                      <td>
                        <button onClick={() => openPrint(d.id)}>พิมพ์ซ้ำ</button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </AsyncView>
          <Notice kind="info">
            การพิมพ์ซ้ำอ่านจากเนื้อหาที่ตรึงไว้ตอนออก <strong>ไม่ได้คำนวณใหม่</strong> —
            ใบที่พิมพ์วันนี้จึงตรงกับกระดาษที่ผู้ปกครองถืออยู่เสมอ
          </Notice>
        </TableCard>
      )}
      </>
      )}
    </>
  );
}
