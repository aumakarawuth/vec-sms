/**
 * โครงสร้างหลักสูตร
 *
 * ─── ทำไมหน้านี้อ่านเป็นหลัก ───
 * หลักสูตรที่มีนักศึกษาเรียนอยู่แล้วแก้ไม่ได้ตามใจ — `curriculum_version`
 * เป็นฉบับที่ผูกกับปีที่เข้าศึกษา คนที่เข้าปี 2566 ยังอยู่ใต้ฉบับ 2562
 * แม้ปัจจุบันจะใช้ฉบับ 2567 แล้ว การแก้ฉบับเดิมจึงเท่ากับเปลี่ยนเกณฑ์จบ
 * ของคนที่เรียนไปแล้วครึ่งทาง วิธีที่ถูกคือ **โคลนเป็นฉบับใหม่**
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { num } from '../core/fmt';
import { AsyncView, Badge, Card, PageHead, TableCard, useAsync } from '../ui/kit';

interface Version {
  id: string;
  edition_be: number;
  effective_from_year_be: number;
  effective_to_year_be: number | null;
  status: string;
  min_total_credits: string;
  min_gpax: string;
  grade_scheme_code: string | null;
  courses: string | number;
  rules: string | number;
  students: string | number;
}

interface CourseInVersion {
  id: string;
  requirement: string;
  code: string;
  name_th: string;
  credits?: string;
  suggested_year?: number | null;
  suggested_term?: number | null;
}

interface Category {
  id: string;
  parent_id: string | null;
  kind: string;
  code: string;
  name_th: string;
  min_credits?: string | null;
  max_credits?: string | null;
  courses: CourseInVersion[];
}

interface GraduationRule {
  id: string;
  kind: string;
  name_th: string;
  threshold: string | null;
  is_blocking: boolean;
}

/** เส้นทางนี้คืนข้อมูลของฉบับหลักสูตรแบบแบน แล้วซ้อนรายวิชาไว้ในแต่ละหมวด */
interface Structure {
  edition_be: number;
  min_total_credits: string;
  min_gpax: string;
  min_practicum_hours: number | null;
  grade_scheme_name: string | null;
  categories: Category[];
  uncategorized: CourseInVersion[];
  graduationRules: GraduationRule[];
}

const REQUIREMENT: Record<string, string> = {
  required: 'บังคับ',
  elective: 'เลือก',
  free_elective: 'เลือกเสรี',
};

export function CurriculumScreen() {
  const versions = useAsync(() => api.get<Version[]>('/curriculum/versions'), []);
  const [versionId, setVersionId] = useState('');
  const [q, setQ] = useState('');

  const structure = useAsync(
    () =>
      versionId
        ? api.get<Structure>(`/curriculum/versions/${versionId}`)
        : Promise.resolve(null as unknown as Structure),
    [versionId],
  );
  const courses = useAsync(
    () => api.get<{ id: string; code: string; name_th: string; credits: string }[]>(
      `/curriculum/courses${qs({ q })}`,
    ),
    [q],
  );

  return (
    <>
      <PageHead title="โครงสร้างหลักสูตร" />

      <TableCard title="ฉบับหลักสูตร">
        <AsyncView state={versions} empty="ยังไม่มีหลักสูตรในระบบ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 34 }} />
                  <th style={{ width: 90 }}>ฉบับ</th>
                  <th style={{ width: 150 }}>ปีที่ใช้</th>
                  <th className="num" style={{ width: 110 }}>หน่วยกิตขั้นต่ำ</th>
                  <th className="num" style={{ width: 90 }}>GPAX</th>
                  <th className="num" style={{ width: 90 }}>รายวิชา</th>
                  <th className="num" style={{ width: 80 }}>กฎจบ</th>
                  <th className="num" style={{ width: 100 }}>นักศึกษา</th>
                  <th style={{ width: 100 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((v) => (
                  <tr key={v.id}>
                    <td>
                      <input
                        type="radio"
                        name="cv"
                        style={{ width: 'auto' }}
                        checked={versionId === v.id}
                        onChange={() => setVersionId(v.id)}
                      />
                    </td>
                    <td>{v.edition_be}</td>
                    <td>
                      {v.effective_from_year_be}
                      {v.effective_to_year_be ? `–${v.effective_to_year_be}` : ' เป็นต้นไป'}
                    </td>
                    <td className="num">{num(v.min_total_credits)}</td>
                    <td className="num">{num(v.min_gpax, 2)}</td>
                    <td className="num">{v.courses}</td>
                    <td className="num">{v.rules}</td>
                    <td className="num">{v.students}</td>
                    <td>
                      <Badge kind={v.status === 'active' ? 'ok' : 'default'}>
                        {v.status === 'active' ? 'ใช้งานอยู่' : v.status}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>

      {versionId && (
        <AsyncView state={structure}>
          {(s) => (
            <>
              <TableCard title="เกณฑ์การจบของฉบับนี้">
                <table>
                  <thead>
                    <tr>
                      <th>เกณฑ์</th>
                      <th className="num" style={{ width: 120 }}>ค่าที่ต้องถึง</th>
                      <th style={{ width: 110 }}>บังคับไหม</th>
                    </tr>
                  </thead>
                  <tbody>
                    {s.graduationRules.map((r) => (
                      <tr key={r.id}>
                        <td style={{ whiteSpace: 'normal' }}>{r.name_th}</td>
                        <td className="num">{r.threshold === null ? '—' : num(r.threshold, 2)}</td>
                        <td>
                          <Badge kind={r.is_blocking ? 'danger' : 'default'}>
                            {r.is_blocking ? 'บังคับ' : 'ไม่บังคับ'}
                          </Badge>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </TableCard>

              {s.categories.map((c) => (
                <TableCard
                  key={c.id}
                  title={
                    <>
                      <span className="mono">{c.code}</span> {c.name_th}
                      {c.min_credits && ` — อย่างน้อย ${num(c.min_credits)} หน่วยกิต`}
                      {` · ${c.courses.length} วิชา`}
                    </>
                  }
                >
                  {c.courses.length === 0 ? (
                    <div className="empty">ยังไม่มีรายวิชาในหมวดนี้</div>
                  ) : (
                    <table>
                      <thead>
                        <tr>
                          <th style={{ width: 120 }}>รหัสวิชา</th>
                          <th>ชื่อวิชา</th>
                          <th className="num" style={{ width: 70 }}>นก.</th>
                          <th style={{ width: 110 }}>ประเภท</th>
                          <th style={{ width: 150 }}>แนะนำให้เรียน</th>
                        </tr>
                      </thead>
                      <tbody>
                        {c.courses.map((co) => (
                          <tr key={co.id}>
                            <td className="mono">{co.code}</td>
                            <td>{co.name_th}</td>
                            <td className="num">{co.credits ? num(co.credits) : '—'}</td>
                            <td>
                              <Badge kind={co.requirement === 'required' ? 'info' : 'default'}>
                                {REQUIREMENT[co.requirement] ?? co.requirement}
                              </Badge>
                            </td>
                            <td>
                              {co.suggested_year
                                ? `ชั้นปีที่ ${co.suggested_year}${co.suggested_term ? ` ภาค ${co.suggested_term}` : ''}`
                                : '—'}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  )}
                </TableCard>
              ))}

              {s.uncategorized.length > 0 && (
                <Card title={`รายวิชาที่ยังไม่ได้จัดหมวด — ${s.uncategorized.length} วิชา`}>
                  {s.uncategorized.map((co) => (
                    <div key={co.id}>
                      <span className="mono">{co.code}</span> {co.name_th}
                    </div>
                  ))}
                </Card>
              )}
            </>
          )}
        </AsyncView>
      )}

      <TableCard title="คลังรายวิชาของวิทยาลัย">
        <div style={{ padding: 12, borderBottom: '1px solid var(--line-soft)' }}>
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="ค้นหาด้วยรหัสหรือชื่อวิชา"
            style={{ maxWidth: 320 }}
          />
        </div>
        <AsyncView state={courses} empty="ไม่พบรายวิชา">
          {(rows) => (
            <div style={{ maxHeight: 320, overflowY: 'auto' }}>
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 120 }}>รหัสวิชา</th>
                    <th>ชื่อวิชา</th>
                    <th className="num" style={{ width: 80 }}>หน่วยกิต</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((c) => (
                    <tr key={c.id}>
                      <td className="mono">{c.code}</td>
                      <td>{c.name_th}</td>
                      <td className="num">{num(c.credits)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}
