/**
 * วิชาชุมนุม/ชมรม — บันทึกพื้นฐาน
 *
 * ยังไม่ผูกกับเกณฑ์จบ "กิจกรรมเสริมหลักสูตรผ่านทุกภาคเรียน" หรือหน่วยกิต
 * กิจกรรม — ที่นี่บันทึกได้แค่ชื่อชมรม ผู้ดูแล และสมาชิกรายปีการศึกษา
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { fetchTerms } from '../core/catalog';
import { thaiDate } from '../core/fmt';
import { ActionButton, AsyncView, Badge, Card, Field, PageHead, TableCard, useAsync } from '../ui/kit';

interface Club {
  id: string;
  code: string;
  name_th: string;
  category_th: string | null;
  active: boolean;
  advisor_code: string | null;
  advisor_name: string | null;
  members: string;
}

interface Member {
  id: string;
  role: string;
  joined_on: string;
  left_on: string | null;
  student_id: string;
  student_code: string;
  full_name: string;
}

interface StaffRow {
  id: string;
  person_id: string;
  staff_code: string;
  full_name: string;
}

interface StudentRow {
  id: string;
  student_code: string;
  full_name: string;
}

function CreateClubCard({ staff, onDone }: { staff: StaffRow[]; onDone: () => void }) {
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');
  const [categoryTh, setCategoryTh] = useState('');
  const [advisorId, setAdvisorId] = useState('');

  return (
    <Card title="เพิ่มชมรม/วิชาชุมนุม">
      <div className="row">
        <Field label="รหัสชมรม">
          <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น CLB-01" style={{ maxWidth: 120 }} />
        </Field>
        <Field label="ชื่อชมรม">
          <input value={nameTh} onChange={(e) => setNameTh(e.target.value)} placeholder="เช่น ชมรมดนตรีไทย" />
        </Field>
        <Field label="ประเภท (ถ้ามี)">
          <input value={categoryTh} onChange={(e) => setCategoryTh(e.target.value)} placeholder="เช่น ศิลปะ, กีฬา, วิชาการ" />
        </Field>
        <label className="field" style={{ flex: 2 }}>
          <span>ครูที่ปรึกษา (ถ้ามี)</span>
          <select value={advisorId} onChange={(e) => setAdvisorId(e.target.value)}>
            <option value="">— ยังไม่ระบุ —</option>
            {staff.map((s) => (
              <option key={s.id} value={s.id}>{s.full_name} ({s.staff_code})</option>
            ))}
          </select>
        </label>
        <div className="shrink">
          <ActionButton
            className="primary"
            onRun={() => {
              if (!code.trim() || !nameTh.trim()) throw new Error('ต้องมีรหัสและชื่อชมรม');
              return api.post('/clubs', {
                code: code.trim(), nameTh: nameTh.trim(),
                ...(categoryTh.trim() ? { categoryTh: categoryTh.trim() } : {}),
                ...(advisorId ? { advisorStaffId: advisorId } : {}),
              });
            }}
            onDone={() => { setCode(''); setNameTh(''); setCategoryTh(''); setAdvisorId(''); onDone(); }}
          >
            เพิ่มชมรม
          </ActionButton>
        </div>
      </div>
    </Card>
  );
}

function AddMemberCard({
  clubId, academicYearId, onDone,
}: { clubId: string; academicYearId: string; onDone: () => void }) {
  const [q, setQ] = useState('');
  const [studentId, setStudentId] = useState('');
  const [role, setRole] = useState('member');

  const results = useAsync(
    () => (q.trim().length >= 2 ? api.get<StudentRow[]>(`/students${qs({ q, limit: 20 })}`) : Promise.resolve([])),
    [q],
  );

  return (
    <Card title="เพิ่มสมาชิก">
      {!academicYearId && <p className="hint">เลือกปีการศึกษาด้านบนก่อนจึงจะเพิ่มสมาชิกได้</p>}
      {academicYearId && (
        <div className="row">
          <Field label="ค้นหานักศึกษา (ชื่อหรือรหัส)">
            <input value={q} onChange={(e) => { setQ(e.target.value); setStudentId(''); }} placeholder="พิมพ์อย่างน้อย 2 ตัวอักษร" />
          </Field>
          <label className="field" style={{ flex: 2 }}>
            <span>ผลค้นหา</span>
            <AsyncView state={results}>
              {(rows) => (
                <select value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                  <option value="">— เลือกนักศึกษา —</option>
                  {rows.map((s) => (
                    <option key={s.id} value={s.id}>{s.student_code} {s.full_name}</option>
                  ))}
                </select>
              )}
            </AsyncView>
          </label>
          <Field label="บทบาท">
            <select value={role} onChange={(e) => setRole(e.target.value)}>
              <option value="member">สมาชิก</option>
              <option value="leader">หัวหน้าชมรม</option>
            </select>
          </Field>
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() => {
                if (!studentId) throw new Error('ยังไม่ได้เลือกนักศึกษา');
                return api.post(`/clubs/${clubId}/members`, { studentId, academicYearId, role });
              }}
              onDone={() => { setQ(''); setStudentId(''); onDone(); }}
            >
              เพิ่มสมาชิก
            </ActionButton>
          </div>
        </div>
      )}
    </Card>
  );
}

export function ClubsScreen() {
  const clubs = useAsync(() => api.get<Club[]>('/clubs'), []);
  const staff = useAsync(() => api.getPage<StaffRow>('/staff?limit=100'), []);
  const terms = useAsync(fetchTerms, []);
  const [clubId, setClubId] = useState('');
  const [academicYearId, setAcademicYearId] = useState('');

  const years = [...new Map(
    (terms.data ?? []).map((t) => [t.academic_year_id, { id: t.academic_year_id, year_be: t.year_be }]),
  ).values()].sort((a, b) => b.year_be - a.year_be);

  const members = useAsync(
    () => (clubId ? api.get<Member[]>(`/clubs/${clubId}/members${qs({ academicYearId })}`) : Promise.resolve([])),
    [clubId, academicYearId],
  );

  const club = clubs.data?.find((c) => c.id === clubId);

  return (
    <>
      <PageHead title="วิชาชุมนุม/ชมรม" sub="บันทึกพื้นฐาน — ชื่อชมรม ผู้ดูแล และสมาชิกรายปีการศึกษา" />

      <AsyncView state={staff}>
        {(page) => <CreateClubCard staff={page.items} onDone={() => clubs.reload()} />}
      </AsyncView>

      <TableCard title="ชมรมทั้งหมด">
        <AsyncView state={clubs} empty="ยังไม่มีชมรม">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 34 }} />
                  <th style={{ width: 100 }}>รหัส</th>
                  <th>ชื่อชมรม</th>
                  <th style={{ width: 130 }}>ประเภท</th>
                  <th>ครูที่ปรึกษา</th>
                  <th className="num" style={{ width: 100 }}>สมาชิก</th>
                  <th style={{ width: 100 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((c) => (
                  <tr key={c.id}>
                    <td>
                      <input type="radio" name="club" style={{ width: 'auto' }}
                        checked={clubId === c.id} onChange={() => setClubId(c.id)} />
                    </td>
                    <td className="mono">{c.code}</td>
                    <td>{c.name_th}</td>
                    <td>{c.category_th ?? '—'}</td>
                    <td>{c.advisor_name ?? '—'}</td>
                    <td className="num">{c.members}</td>
                    <td><Badge kind={c.active ? 'ok' : 'default'}>{c.active ? 'ใช้งานอยู่' : 'ปิดแล้ว'}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {club && (
        <>
          <Card title={`สมาชิกของ ${club.name_th}`}>
            <div className="row">
              <Field label="ปีการศึกษา">
                <select value={academicYearId} onChange={(e) => setAcademicYearId(e.target.value)}>
                  <option value="">— เลือกปีการศึกษา —</option>
                  {years.map((y) => <option key={y.id} value={y.id}>ปีการศึกษา {y.year_be}</option>)}
                </select>
              </Field>
            </div>
          </Card>

          <AddMemberCard clubId={club.id} academicYearId={academicYearId} onDone={() => members.reload()} />

          <TableCard title="รายชื่อสมาชิก">
            <AsyncView state={members} empty="ยังไม่มีสมาชิกในปีการศึกษานี้">
              {(rows) => (
                <table>
                  <thead>
                    <tr>
                      <th style={{ width: 120 }}>รหัสนักศึกษา</th>
                      <th>ชื่อ — นามสกุล</th>
                      <th style={{ width: 130 }}>บทบาท</th>
                      <th style={{ width: 130 }}>เข้าร่วมเมื่อ</th>
                      <th style={{ width: 100 }}>สถานะ</th>
                      <th style={{ width: 100 }} />
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((m) => (
                      <tr key={m.id}>
                        <td className="mono">{m.student_code}</td>
                        <td>{m.full_name}</td>
                        <td>{m.role === 'leader' ? 'หัวหน้าชมรม' : 'สมาชิก'}</td>
                        <td>{thaiDate(m.joined_on)}</td>
                        <td>
                          <Badge kind={m.left_on ? 'default' : 'ok'}>{m.left_on ? 'พ้นสภาพแล้ว' : 'อยู่'}</Badge>
                        </td>
                        <td>
                          {!m.left_on && (
                            <ActionButton
                              className="danger"
                              confirm={`นำ ${m.full_name} ออกจากชมรมนี้ ยืนยันหรือไม่`}
                              onRun={() => api.del(`/clubs/${club.id}/members/${m.id}`)}
                              onDone={() => members.reload()}
                            >
                              นำออก
                            </ActionButton>
                          )}
                        </td>
                      </tr>
                    ))}
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
