/**
 * ระเบียนนักศึกษาฉบับเต็ม — แปดกลุ่มข้อมูลตาม migration 0053
 *
 * ─── ทำไมแท็บข้อมูลอ่อนไหวถึงไม่หายไปเมื่อไม่มีสิทธิ์ ───
 * ถ้าซ่อนแท็บทิ้ง ครูผู้สอนจะเข้าใจว่าระบบไม่มีข้อมูลนั้น แล้วไปถามเจ้าตัว
 * หรือถามผู้ปกครองแทน ซึ่งเป็นการเก็บข้อมูลอ่อนไหวนอกระบบ — แย่กว่าเดิม
 * จึงแสดงแท็บไว้พร้อมบอกตรง ๆ ว่าใครดูได้ และให้ติดต่อใคร
 *
 * ─── ทำไมทุกฟอร์มโหลดระเบียนใหม่ทั้งใบหลังบันทึก ───
 * ค่าที่เห็นหลังบันทึกต้องเป็นค่าที่**ฐานข้อมูลเก็บจริง** ไม่ใช่ค่าที่พิมพ์ไว้
 * เพราะ trigger และ constraint แก้ค่าได้ (เช่น `updated_at` หรือค่าที่ถูก
 * ปฏิเสธบางส่วน) การอัปเดตหน้าจอจาก state ที่พิมพ์เองจะทำให้เจ้าหน้าที่
 * เห็นสิ่งที่ไม่ตรงกับของจริงโดยไม่มีอะไรฟ้อง
 */
import { useEffect, useState } from 'react';
import { api } from '../core/api';
import { STUDENT_STATUS, thaiDate, thaiDateTime, money, num } from '../core/fmt';
import { useSession, type Role } from '../core/session';
import { ActionButton, Badge, Card, Field, Notice, TableCard } from '../ui/kit';

/* ─── ชนิดข้อมูล ────────────────────────────────────────────────── */

export interface Sensitive {
  ethnicity: string | null;
  religion: string | null;
  blood_type: string | null;
  drug_allergy: string | null;
  chronic_disease: string | null;
  weight_kg: string | number | null;
  height_cm: string | number | null;
  distinguishing: string | null;
  disability: string | null;
  disability_note: string | null;
  note: string | null;
  updated_at: string;
}

export interface Address {
  id: string;
  kind: string;
  address_line: string;
  subdistrict_th: string | null;
  district_th: string | null;
  province_th: string | null;
  postal_code: string | null;
}

export interface Parent {
  id: string;
  role: string;
  prefix_th: string | null;
  first_name_th: string;
  last_name_th: string | null;
  birth_date: string | null;
  occupation_th: string | null;
  income_monthly: string | number | null;
  status: string;
  phone: string | null;
  work_phone: string | null;
  email: string | null;
  address_line: string | null;
  subdistrict_th: string | null;
  district_th: string | null;
  province_th: string | null;
  postal_code: string | null;
  has_national_id: boolean;
}

export interface PriorEducation {
  id: string;
  level_th: string;
  completed_year_be: number | null;
  gpax: string | number | null;
  program_th: string | null;
  program_type_th: string | null;
  school_th: string | null;
  province_th: string | null;
  verified_at: string | null;
  note: string | null;
}

export interface Advisor {
  id: string;
  staff_id: string;
  is_primary: boolean;
  assigned_on: string;
  ended_on: string | null;
  note: string | null;
  advisor_name: string;
  year_be: number | null;
}

export interface Guardian {
  id: string;
  relation: string;
  is_primary: boolean;
  verified_at: string | null;
  can_view_grades: boolean;
  can_view_finance: boolean;
  can_approve_leave: boolean;
  guardian_name: string;
  phone: string | null;
}

export interface FullProfile {
  id: string;
  student_code: string;
  status: string;
  admitted_year_be: number;
  siblings_count: number | null;
  birth_order: number | null;
  siblings_studying: number | null;
  parents_marital: string | null;
  class_number: number | null;
  travel_mode: string | null;
  talent_th: string | null;
  person_id: string;
  prefix_th: string | null;
  first_name_th: string;
  last_name_th: string;
  prefix_en: string | null;
  first_name_en: string | null;
  last_name_en: string | null;
  nickname_th: string | null;
  nickname_en: string | null;
  nationality: string | null;
  birth_date: string | null;
  gender: string;
  phone: string | null;
  email: string | null;
  line_id: string | null;
  facebook: string | null;
  birth_place_th: string | null;
  sensitive: Sensitive | null;
  canSeeSensitive: boolean;
  addresses: Address[];
  parents: Parent[];
  priorEducation: PriorEducation[];
  advisors: Advisor[];
  guardians: Guardian[];
}

/* ─── ตารางแปลค่า ───────────────────────────────────────────────── */

export const ADDRESS_KIND: Record<string, string> = {
  registered: 'ตามทะเบียนบ้าน',
  current: 'ที่อยู่ปัจจุบัน',
  work: 'ที่ทำงาน',
};

export const PARENT_ROLE: Record<string, string> = { father: 'บิดา', mother: 'มารดา' };

export const PARENT_STATUS: Record<string, string> = {
  alive: 'มีชีวิต',
  deceased: 'ถึงแก่กรรม',
  unknown: 'ไม่ทราบ',
};

export const MARITAL: Record<string, string> = {
  together: 'อยู่ด้วยกัน',
  separated: 'แยกกันอยู่',
  divorced: 'หย่าร้าง',
  father_deceased: 'บิดาถึงแก่กรรม',
  mother_deceased: 'มารดาถึงแก่กรรม',
  both_deceased: 'ถึงแก่กรรมทั้งคู่',
  unknown: 'ไม่ทราบ',
};

export const DISABILITY: Record<string, string> = {
  none: 'ไม่มี',
  vision: 'ทางการเห็น',
  hearing: 'ทางการได้ยิน',
  intellectual: 'ทางสติปัญญา',
  physical: 'ทางกายหรือการเคลื่อนไหว',
  learning: 'ทางการเรียนรู้',
  speech: 'ทางการพูดและภาษา',
  behavioral: 'ทางพฤติกรรมหรืออารมณ์',
  autistic: 'ออทิสติก',
  multiple: 'พิการซ้อน',
};

export const TRAVEL: Record<string, string> = {
  walk: 'เดิน',
  motorcycle: 'รถจักรยานยนต์',
  car: 'รถยนต์ส่วนตัว',
  paid_transit: 'รถโดยสารเสียค่าใช้จ่าย',
  free_transit: 'รถโดยสารไม่เสียค่าใช้จ่าย',
  loaned_bicycle: 'จักรยานยืมเรียน',
  school_van: 'รถรับส่งของสถานศึกษา',
  guardian: 'ผู้ปกครองรับส่ง',
  other: 'อื่น ๆ',
};

const GUARDIAN_RELATION: Record<string, string> = {
  father: 'บิดา',
  mother: 'มารดา',
  guardian: 'ผู้ปกครอง',
  grandparent: 'ปู่ย่าตายาย',
  sibling: 'พี่น้อง',
  relative: 'ญาติ',
  other: 'อื่น ๆ',
};

/* ─── ตัวช่วยของฟอร์ม ───────────────────────────────────────────── */

/**
 * ซ่อนฟอร์มที่ผู้ใช้กดแล้วได้ 403 แน่ ๆ
 *
 * ─── นี่ไม่ใช่มาตรการความปลอดภัย ───
 * สิทธิ์จริงบังคับที่ `@Roles` ของ API และนโยบาย RLS ของฐานข้อมูล ซึ่ง
 * ทำงานต่อให้ยิงตรงข้ามหน้าจอไปเลย ที่ทำตรงนี้คือไม่วางปุ่มที่กดแล้วล้มเสมอ
 * ไว้ให้ผู้ใช้ — ถ้าวันหนึ่งมีใครลบการตรวจฝั่ง API ออกโดยคิดว่า "หน้าจอซ่อนอยู่แล้ว"
 * นั่นคือการเปิดช่องเต็ม ๆ (แบบเดียวกับข้อ 10, 11 และ 13 ในบันทึกของโปรเจกต์)
 */
function useCan(...roles: Role[]): boolean {
  const { role } = useSession();
  return role != null && roles.includes(role);
}

const READ_ONLY_NOTE = (
  <Notice kind="info">
    บทบาทของคุณดูข้อมูลส่วนนี้ได้อย่างเดียว — การแก้ไขเป็นงานของทะเบียนและกิจการนักศึกษา
  </Notice>
);

/** ช่องข้อความที่ผูกกับ state ก้อนเดียว — ลดโค้ดซ้ำในฟอร์มยาว ๆ */
function T({
  label,
  form,
  set,
  name,
  type = 'text',
  readOnly,
  placeholder,
}: {
  label: string;
  form: Record<string, string>;
  set: (f: Record<string, string>) => void;
  name: string;
  type?: string;
  readOnly?: boolean;
  placeholder?: string;
}) {
  return (
    <Field label={label}>
      <input
        type={type}
        value={form[name] ?? ''}
        readOnly={readOnly}
        placeholder={placeholder}
        onChange={(e) => set({ ...form, [name]: e.target.value })}
      />
    </Field>
  );
}

function S({
  label,
  form,
  set,
  name,
  options,
  blank = '— ไม่ระบุ —',
}: {
  label: string;
  form: Record<string, string>;
  set: (f: Record<string, string>) => void;
  name: string;
  options: Record<string, string>;
  blank?: string;
}) {
  return (
    <Field label={label}>
      <select
        value={form[name] ?? ''}
        onChange={(e) => set({ ...form, [name]: e.target.value })}
      >
        <option value="">{blank}</option>
        {Object.entries(options).map(([k, v]) => (
          <option key={k} value={k}>{v}</option>
        ))}
      </select>
    </Field>
  );
}

/** เก็บเฉพาะช่องที่กรอกจริง — ช่องว่างไม่ควรถูกส่งไปล้างค่าเดิม */
function filled(form: Record<string, string>, numbers: string[] = []) {
  const out: Record<string, string | number> = {};
  for (const [k, v] of Object.entries(form)) {
    if (v === '' || v == null) continue;
    out[k] = numbers.includes(k) ? Number(v) : v;
  }
  return out;
}

/* ─── แท็บ 1 · ข้อมูลทั่วไป ─────────────────────────────────────── */

export function GeneralTab({ p, reload }: { p: FullProfile; reload: () => void }) {
  const canWrite = useCan('registrar', 'student_affairs', 'admin');
  const [form, setForm] = useState<Record<string, string>>({});

  useEffect(() => {
    setForm({
      prefixEn: p.prefix_en ?? '',
      nicknameTh: p.nickname_th ?? '',
      nicknameEn: p.nickname_en ?? '',
      nationality: p.nationality ?? '',
      birthPlaceTh: p.birth_place_th ?? '',
      phone: p.phone ?? '',
      email: p.email ?? '',
      lineId: p.line_id ?? '',
      facebook: p.facebook ?? '',
      siblingsCount: p.siblings_count?.toString() ?? '',
      birthOrder: p.birth_order?.toString() ?? '',
      siblingsStudying: p.siblings_studying?.toString() ?? '',
      parentsMarital: p.parents_marital ?? '',
      classNumber: p.class_number?.toString() ?? '',
      travelMode: p.travel_mode ?? '',
      talentTh: p.talent_th ?? '',
    });
  }, [p.id, p.person_id]);

  const NUMS = ['siblingsCount', 'birthOrder', 'siblingsStudying', 'classNumber'];

  return (
    <>
      <Card title="ชื่อ — นามสกุล">
        <div className="row">
          <Field label="คำนำหน้า (ไทย)">
            <input value={p.prefix_th ?? '—'} readOnly />
          </Field>
          <Field label="ชื่อ (ไทย)">
            <input value={p.first_name_th} readOnly />
          </Field>
          <Field label="นามสกุล (ไทย)">
            <input value={p.last_name_th} readOnly />
          </Field>
          <T label="ชื่อเล่น (ไทย)" form={form} set={setForm} name="nicknameTh" />
        </div>
        <div className="row">
          <T label="คำนำหน้า (อังกฤษ)" form={form} set={setForm} name="prefixEn" placeholder="Mr. / Ms." />
          <Field label="ชื่อ (อังกฤษ)">
            <input value={p.first_name_en ?? '—'} readOnly />
          </Field>
          <Field label="นามสกุล (อังกฤษ)">
            <input value={p.last_name_en ?? '—'} readOnly />
          </Field>
          <T label="ชื่อเล่น (อังกฤษ)" form={form} set={setForm} name="nicknameEn" />
        </div>
        <Notice kind="info">
          ชื่อ–นามสกุลแก้ที่นี่ไม่ได้ — เป็นข้อมูลที่ปรากฏบนเอกสารที่ออกไปแล้ว
          การเปลี่ยนต้องผ่านงานทะเบียนพร้อมหลักฐานการเปลี่ยนชื่อ
        </Notice>
      </Card>

      <Card title="ข้อมูลส่วนตัว">
        <div className="row">
          <Field label="วันเกิด">
            <input value={thaiDate(p.birth_date)} readOnly />
          </Field>
          <T label="สถานที่เกิด (จังหวัด)" form={form} set={setForm} name="birthPlaceTh" />
          <T label="สัญชาติ" form={form} set={setForm} name="nationality" placeholder="ไทย" />
          <T label="เลขที่ในห้อง" form={form} set={setForm} name="classNumber" />
        </div>
        <div className="row">
          <T label="โทรศัพท์" form={form} set={setForm} name="phone" />
          <T label="อีเมล" form={form} set={setForm} name="email" />
          <T label="ไลน์ไอดี" form={form} set={setForm} name="lineId" />
          <T label="เฟซบุ๊ก" form={form} set={setForm} name="facebook" />
        </div>
        <div className="row">
          <S label="การเดินทางมาสถานศึกษา" form={form} set={setForm} name="travelMode" options={TRAVEL} />
          <T label="ความสามารถพิเศษ" form={form} set={setForm} name="talentTh" />
        </div>
      </Card>

      <Card title="ครอบครัว">
        <div className="row">
          <T label="จำนวนพี่น้อง (รวมตนเอง)" form={form} set={setForm} name="siblingsCount" />
          <T label="เป็นบุตรคนที่" form={form} set={setForm} name="birthOrder" />
          <T label="พี่น้องที่กำลังศึกษา" form={form} set={setForm} name="siblingsStudying" />
          <S label="สถานภาพบิดามารดา" form={form} set={setForm} name="parentsMarital" options={MARITAL} />
        </div>
        {canWrite ? (
          <div className="row">
            <div className="shrink">
              <ActionButton
                className="primary"
                onRun={() => api.patch(`/students/${p.id}/profile`, filled(form, NUMS))}
                onDone={reload}
              >
                บันทึกข้อมูลทั่วไป
              </ActionButton>
            </div>
            <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
              ช่องที่เว้นว่างจะไม่ถูกบันทึกทับค่าเดิม — ล้างค่าต้องทำที่ฐานข้อมูล
            </div>
          </div>
        ) : READ_ONLY_NOTE}
      </Card>
    </>
  );
}

/* ─── แท็บ 2 · ที่อยู่ ──────────────────────────────────────────── */

export function AddressTab({ p, reload }: { p: FullProfile; reload: () => void }) {
  const canWrite = useCan('registrar', 'student_affairs', 'admin');
  const [form, setForm] = useState<Record<string, string>>({ kind: 'registered' });

  function edit(a: Address) {
    setForm({
      kind: a.kind,
      addressLine: a.address_line,
      subdistrictTh: a.subdistrict_th ?? '',
      districtTh: a.district_th ?? '',
      provinceTh: a.province_th ?? '',
      postalCode: a.postal_code ?? '',
    });
  }

  return (
    <>
      <TableCard title="ที่อยู่ที่บันทึกไว้">
        {p.addresses.length === 0 ? (
          <div className="empty">ยังไม่ได้บันทึกที่อยู่</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th style={{ width: 140 }}>ประเภท</th>
                <th>ที่อยู่</th>
                <th style={{ width: 130 }}>ตำบล/แขวง</th>
                <th style={{ width: 130 }}>อำเภอ/เขต</th>
                <th style={{ width: 120 }}>จังหวัด</th>
                <th style={{ width: 90 }}>รหัสไปรษณีย์</th>
                {canWrite && <th style={{ width: 130 }} />}
              </tr>
            </thead>
            <tbody>
              {p.addresses.map((a) => (
                <tr key={a.id}>
                  <td>{ADDRESS_KIND[a.kind] ?? a.kind}</td>
                  <td style={{ whiteSpace: 'normal' }}>{a.address_line}</td>
                  <td>{a.subdistrict_th ?? '—'}</td>
                  <td>{a.district_th ?? '—'}</td>
                  <td>{a.province_th ?? '—'}</td>
                  <td className="mono">{a.postal_code ?? '—'}</td>
                  {canWrite && (
                  <td>
                    <span style={{ display: 'inline-flex', gap: 8 }}>
                      <button onClick={() => edit(a)}>แก้ไข</button>
                      <ActionButton
                        className="danger"
                        confirm="ลบที่อยู่นี้ ยืนยันหรือไม่"
                        onRun={() => api.del(`/students/${p.id}/addresses/${a.id}`)}
                        onDone={reload}
                      >
                        ลบ
                      </ActionButton>
                    </span>
                  </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </TableCard>

      {canWrite && (
      <Card title="เพิ่มหรือแก้ไขที่อยู่">
        <div className="row">
          <S label="ประเภท" form={form} set={setForm} name="kind" options={ADDRESS_KIND} blank="— เลือกประเภท —" />
          <T label="บ้านเลขที่ หมู่ ถนน" form={form} set={setForm} name="addressLine" />
        </div>
        <div className="row">
          <T label="ตำบล/แขวง" form={form} set={setForm} name="subdistrictTh" />
          <T label="อำเภอ/เขต" form={form} set={setForm} name="districtTh" />
          <T label="จังหวัด" form={form} set={setForm} name="provinceTh" />
          <T label="รหัสไปรษณีย์" form={form} set={setForm} name="postalCode" placeholder="5 หลัก" />
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() => api.post(`/students/${p.id}/addresses`, filled(form))}
              onDone={() => {
                setForm({ kind: 'registered' });
                reload();
              }}
            >
              บันทึกที่อยู่
            </ActionButton>
          </div>
        </div>
        <Notice kind="info">
          หนึ่งประเภทมีได้หนึ่งที่อยู่ — บันทึกซ้ำประเภทเดิมคือการแก้ไขที่อยู่นั้น
        </Notice>
      </Card>
      )}
    </>
  );
}

/* ─── แท็บ 3 · บิดามารดา ────────────────────────────────────────── */

export function ParentTab({ p, reload }: { p: FullProfile; reload: () => void }) {
  const canWrite = useCan('registrar', 'student_affairs', 'admin');
  const [form, setForm] = useState<Record<string, string>>({ role: 'father', status: 'alive' });

  function edit(x: Parent) {
    setForm({
      role: x.role,
      prefixTh: x.prefix_th ?? '',
      firstNameTh: x.first_name_th,
      lastNameTh: x.last_name_th ?? '',
      birthDate: x.birth_date?.slice(0, 10) ?? '',
      occupationTh: x.occupation_th ?? '',
      incomeMonthly: x.income_monthly?.toString() ?? '',
      status: x.status,
      phone: x.phone ?? '',
      workPhone: x.work_phone ?? '',
      email: x.email ?? '',
      addressLine: x.address_line ?? '',
      subdistrictTh: x.subdistrict_th ?? '',
      districtTh: x.district_th ?? '',
      provinceTh: x.province_th ?? '',
      postalCode: x.postal_code ?? '',
    });
  }

  return (
    <>
      <TableCard title="บิดามารดา">
        {p.parents.length === 0 ? (
          <div className="empty">ยังไม่ได้บันทึกข้อมูลบิดามารดา</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th style={{ width: 70 }}>ความเกี่ยวข้อง</th>
                <th>ชื่อ — นามสกุล</th>
                <th style={{ width: 140 }}>อาชีพ</th>
                <th className="num" style={{ width: 120 }}>รายได้/เดือน</th>
                <th style={{ width: 120 }}>โทรศัพท์</th>
                <th style={{ width: 110 }}>สถานภาพ</th>
                <th style={{ width: 90 }}>เลขบัตร</th>
                {canWrite && <th style={{ width: 130 }} />}
              </tr>
            </thead>
            <tbody>
              {p.parents.map((x) => (
                <tr key={x.id}>
                  <td>{PARENT_ROLE[x.role] ?? x.role}</td>
                  <td>
                    {[x.prefix_th, x.first_name_th, x.last_name_th].filter(Boolean).join(' ')}
                  </td>
                  <td>{x.occupation_th ?? '—'}</td>
                  <td className="num">{x.income_monthly != null ? money(x.income_monthly) : '—'}</td>
                  <td>{x.phone ?? '—'}</td>
                  <td>
                    <Badge kind={x.status === 'alive' ? 'default' : 'warn'}>
                      {PARENT_STATUS[x.status] ?? x.status}
                    </Badge>
                  </td>
                  <td>
                    {x.has_national_id ? <Badge kind="ok">มี</Badge> : <Badge>ยังไม่มี</Badge>}
                  </td>
                  {canWrite && (
                  <td>
                    <span style={{ display: 'inline-flex', gap: 8 }}>
                      <button onClick={() => edit(x)}>แก้ไข</button>
                      <ActionButton
                        className="danger"
                        confirm="ลบข้อมูลนี้ ยืนยันหรือไม่"
                        onRun={() => api.del(`/students/${p.id}/parents/${x.id}`)}
                        onDone={reload}
                      >
                        ลบ
                      </ActionButton>
                    </span>
                  </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </TableCard>

      {canWrite && (
      <Card title="เพิ่มหรือแก้ไขข้อมูลบิดามารดา">
        <div className="row">
          <S label="ความเกี่ยวข้อง" form={form} set={setForm} name="role" options={PARENT_ROLE} blank="— เลือก —" />
          <T label="คำนำหน้า" form={form} set={setForm} name="prefixTh" />
          <T label="ชื่อ" form={form} set={setForm} name="firstNameTh" />
          <T label="นามสกุล" form={form} set={setForm} name="lastNameTh" />
          <S label="สถานภาพ" form={form} set={setForm} name="status" options={PARENT_STATUS} blank="— เลือก —" />
        </div>
        <div className="row">
          <T label="เลขบัตรประชาชน" form={form} set={setForm} name="nationalId" placeholder="กรอกได้ อ่านกลับไม่ได้" />
          <T label="วันเกิด" form={form} set={setForm} name="birthDate" type="date" />
          <T label="อาชีพ" form={form} set={setForm} name="occupationTh" />
          <T label="รายได้ต่อเดือน (บาท)" form={form} set={setForm} name="incomeMonthly" />
        </div>
        <div className="row">
          <T label="โทรศัพท์" form={form} set={setForm} name="phone" />
          <T label="โทรศัพท์ที่ทำงาน" form={form} set={setForm} name="workPhone" />
          <T label="อีเมล" form={form} set={setForm} name="email" />
        </div>
        <div className="row">
          <T label="ที่อยู่" form={form} set={setForm} name="addressLine" />
          <T label="ตำบล/แขวง" form={form} set={setForm} name="subdistrictTh" />
          <T label="อำเภอ/เขต" form={form} set={setForm} name="districtTh" />
          <T label="จังหวัด" form={form} set={setForm} name="provinceTh" />
          <T label="รหัสไปรษณีย์" form={form} set={setForm} name="postalCode" />
        </div>
        <div className="row">
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() => api.post(`/students/${p.id}/parents`, filled(form, ['incomeMonthly']))}
              onDone={() => {
                setForm({ role: 'father', status: 'alive' });
                reload();
              }}
            >
              บันทึก
            </ActionButton>
          </div>
        </div>
        <Notice kind="warn">
          <strong>เลขบัตรประชาชนกรอกได้แต่อ่านกลับไม่ได้</strong> — ฐานข้อมูลเก็บเฉพาะ
          ค่าแฮชเพื่อตรวจซ้ำ ไม่เก็บเลขจริง ตารางด้านบนจึงบอกได้แค่ว่ามีหรือยังไม่มี
          และการแก้ช่องอื่นโดยไม่กรอกเลขจะไม่ล้างค่าเดิมทิ้ง
        </Notice>
      </Card>
      )}
    </>
  );
}

/* ─── แท็บ 4 · ข้อมูลอ่อนไหว ────────────────────────────────────── */

export function SensitiveTab({ p, reload }: { p: FullProfile; reload: () => void }) {
  const canWrite = useCan('registrar', 'student_affairs', 'admin');
  const [form, setForm] = useState<Record<string, string>>({});
  const s = p.sensitive;

  useEffect(() => {
    setForm({
      ethnicity: s?.ethnicity ?? '',
      religion: s?.religion ?? '',
      bloodType: s?.blood_type ?? '',
      drugAllergy: s?.drug_allergy ?? '',
      chronicDisease: s?.chronic_disease ?? '',
      weightKg: s?.weight_kg?.toString() ?? '',
      heightCm: s?.height_cm?.toString() ?? '',
      distinguishing: s?.distinguishing ?? '',
      disability: s?.disability ?? '',
      disabilityNote: s?.disability_note ?? '',
      note: s?.note ?? '',
    });
  }, [p.person_id, s?.updated_at]);

  if (!p.canSeeSensitive) {
    return (
      <Notice kind="warn">
        <strong>ส่วนนี้ต้องมีสิทธิ์เฉพาะ</strong> — ข้อมูลสุขภาพ ศาสนา และเชื้อชาติ
        เป็นข้อมูลอ่อนไหวตาม พ.ร.บ.คุ้มครองข้อมูลส่วนบุคคล มาตรา 26
        ผู้ที่ดูได้คืองานทะเบียน · งานปกครองและแนะแนว · ผู้อำนวยการ ·
        <strong>ครูที่ปรึกษาของนักศึกษาคนนี้</strong> · เจ้าตัวและผู้ปกครองที่ยืนยันตัวตนแล้ว
        <br />
        ถ้าต้องใช้ข้อมูลนี้ในการดูแลนักศึกษา ให้ขอผ่านงานปกครอง —
        <strong>อย่าไปถามเจ้าตัวหรือผู้ปกครองแล้วจดไว้เอง</strong> เพราะข้อมูลจะไปอยู่
        นอกระบบที่ไม่มีใครตรวจสอบได้ว่าใครเห็นบ้าง
      </Notice>
    );
  }

  return (
    <>
      <Notice kind="warn">
        ข้อมูลในหน้านี้เป็นข้อมูลอ่อนไหวตาม PDPA มาตรา 26 —
        การเปิดหน้านี้ถูกบันทึกลง <code>access_log</code> ซึ่งลบไม่ได้
      </Notice>

      <Card title="สุขภาพ">
        <div className="row">
          <S label="หมู่โลหิต" form={form} set={setForm} name="bloodType"
             options={{ A: 'A', B: 'B', AB: 'AB', O: 'O' }} />
          <T label="น้ำหนัก (กก.)" form={form} set={setForm} name="weightKg" />
          <T label="ส่วนสูง (ซม.)" form={form} set={setForm} name="heightCm" />
          <T label="ตำหนิ/แผลเป็น" form={form} set={setForm} name="distinguishing" />
        </div>
        <div className="row">
          <T label="ประวัติแพ้ยา" form={form} set={setForm} name="drugAllergy" placeholder="ไม่มี" />
          <T label="โรคประจำตัว" form={form} set={setForm} name="chronicDisease" placeholder="ไม่มี" />
        </div>
        <Notice kind="info">
          ประวัติแพ้ยาและโรคประจำตัวคือสองช่องที่ต้องหาให้เจอภายในไม่กี่วินาที
          เมื่อเกิดเหตุในสถานศึกษา — กรอกว่า “ไม่มี” ดีกว่าเว้นว่าง
          เพราะช่องว่างแปลว่ายังไม่ได้ถาม ไม่ใช่ว่าไม่มี
        </Notice>
      </Card>

      <Card title="ความพิการ">
        <div className="row">
          <S label="ประเภทความพิการ" form={form} set={setForm} name="disability" options={DISABILITY} />
          <T label="รายละเอียด" form={form} set={setForm} name="disabilityNote" />
        </div>
      </Card>

      <Card title="เชื้อชาติ ศาสนา และหมายเหตุ">
        <div className="row">
          <T label="เชื้อชาติ" form={form} set={setForm} name="ethnicity" />
          <T label="ศาสนา" form={form} set={setForm} name="religion" />
          <T label="หมายเหตุ" form={form} set={setForm} name="note" />
        </div>
        <div className="row">
          {canWrite && (
            <div className="shrink">
              <ActionButton
                className="primary"
                onRun={() => api.post(`/students/${p.id}/sensitive`, filled(form, ['weightKg', 'heightCm']))}
                onDone={reload}
              >
                บันทึกข้อมูลอ่อนไหว
              </ActionButton>
            </div>
          )}
          {s && (
            <div style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
              แก้ไขล่าสุด {thaiDateTime(s.updated_at)}
            </div>
          )}
        </div>
        {!canWrite && (
          <Notice kind="info">
            ครูที่ปรึกษา<strong>ดูได้แต่แก้ไม่ได้</strong> — ข้อมูลสุขภาพต้องมาจาก
            เอกสารที่ผู้ปกครองกรอก ไม่ใช่จากความจำของครู แจ้งแก้ไขที่งานกิจการนักศึกษา
          </Notice>
        )}
      </Card>
    </>
  );
}

/* ─── แท็บ 5 · การศึกษาเดิม ─────────────────────────────────────── */

export function PriorEducationTab({ p, reload }: { p: FullProfile; reload: () => void }) {
  const canWrite = useCan('registrar', 'academic', 'admin');
  const [form, setForm] = useState<Record<string, string>>({});

  return (
    <>
      <TableCard title="ประวัติการศึกษาเดิม">
        {p.priorEducation.length === 0 ? (
          <div className="empty">ยังไม่ได้บันทึกประวัติการศึกษาเดิม</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th style={{ width: 120 }}>ระดับ</th>
                <th>สถานศึกษาเดิม</th>
                <th style={{ width: 110 }}>จังหวัด</th>
                <th style={{ width: 150 }}>สาขา/แผนการเรียน</th>
                <th className="num" style={{ width: 80 }}>ปีที่จบ</th>
                <th className="num" style={{ width: 70 }}>GPAX</th>
                <th style={{ width: 150 }}>ตรวจวุฒิ</th>
                {canWrite && <th style={{ width: 170 }} />}
              </tr>
            </thead>
            <tbody>
              {p.priorEducation.map((e) => (
                <tr key={e.id}>
                  <td>{e.level_th}</td>
                  <td>{e.school_th ?? '—'}</td>
                  <td>{e.province_th ?? '—'}</td>
                  <td>{e.program_th ?? e.program_type_th ?? '—'}</td>
                  <td className="num">{e.completed_year_be ?? '—'}</td>
                  <td className="num">{e.gpax != null ? num(e.gpax, 2) : '—'}</td>
                  <td>
                    {e.verified_at
                      ? <Badge kind="ok">ตรวจแล้ว {thaiDate(e.verified_at)}</Badge>
                      : <Badge kind="warn">ยังไม่ได้ตรวจ</Badge>}
                  </td>
                  {canWrite && (
                  <td>
                    <span style={{ display: 'inline-flex', gap: 8 }}>
                      {!e.verified_at && (
                        <ActionButton
                          confirm="ยืนยันว่าตรวจวุฒิกับสถานศึกษาเดิมแล้ว"
                          onRun={() => api.post(`/students/${p.id}/prior-education/${e.id}/verify`, {})}
                          onDone={reload}
                        >
                          ตรวจวุฒิแล้ว
                        </ActionButton>
                      )}
                      <ActionButton
                        className="danger"
                        confirm="ลบประวัตินี้ ยืนยันหรือไม่"
                        onRun={() => api.del(`/students/${p.id}/prior-education/${e.id}`)}
                        onDone={reload}
                      >
                        ลบ
                      </ActionButton>
                    </span>
                  </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </TableCard>

      {canWrite && (
      <Card title="เพิ่มประวัติการศึกษาเดิม">
        <div className="row">
          <T label="ระดับ" form={form} set={setForm} name="levelTh" placeholder="ม.3 / ปวช. / ม.6" />
          <T label="สถานศึกษาเดิม" form={form} set={setForm} name="schoolTh" />
          <T label="จังหวัด" form={form} set={setForm} name="provinceTh" />
        </div>
        <div className="row">
          <T label="สาขาวิชา" form={form} set={setForm} name="programTh" />
          <T label="ประเภทวิชา/แผนการเรียน" form={form} set={setForm} name="programTypeTh" />
          <T label="ปีที่สำเร็จ (พ.ศ.)" form={form} set={setForm} name="completedYearBe" />
          <T label="GPAX" form={form} set={setForm} name="gpax" />
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() =>
                api.post(`/students/${p.id}/prior-education`, filled(form, ['completedYearBe', 'gpax']))
              }
              onDone={() => {
                setForm({});
                reload();
              }}
            >
              บันทึก
            </ActionButton>
          </div>
        </div>
        <Notice kind="info">
          ช่อง “ตรวจวุฒิ” ที่ว่างแปลว่า <strong>ยังไม่ได้ตรวจ</strong> ไม่ใช่ตรวจแล้วไม่ผ่าน —
          ถ้าตรวจแล้วพบว่าวุฒิไม่ตรง ให้บันทึกไว้ในหมายเหตุแล้วส่งเรื่องต่อ
        </Notice>
      </Card>
      )}
    </>
  );
}

/* ─── แท็บ 6 · ที่ปรึกษาและผู้ปกครอง ────────────────────────────── */

interface StaffOption {
  id: string;
  full_name: string;
}

export function AdvisorTab({ p, reload }: { p: FullProfile; reload: () => void }) {
  const canWrite = useCan('registrar', 'academic', 'director', 'admin');
  const [staffId, setStaffId] = useState('');
  const [staff, setStaff] = useState<StaffOption[]>([]);

  useEffect(() => {
    api
      .getPage<StaffOption>('/staff?limit=300')
      .then((page) => setStaff(page.items))
      .catch(() => setStaff([]));
  }, []);

  const current = p.advisors.filter((a) => !a.ended_on);
  const past = p.advisors.filter((a) => a.ended_on);

  return (
    <>
      <TableCard title="อาจารย์ที่ปรึกษาปัจจุบัน">
        {current.length === 0 ? (
          <div className="empty">ยังไม่ได้มอบหมายอาจารย์ที่ปรึกษา</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>อาจารย์ที่ปรึกษา</th>
                <th style={{ width: 110 }}>ปีการศึกษา</th>
                <th style={{ width: 90 }}>ที่ปรึกษาหลัก</th>
                <th style={{ width: 130 }}>มอบหมายเมื่อ</th>
                {canWrite && <th style={{ width: 110 }} />}
              </tr>
            </thead>
            <tbody>
              {current.map((a) => (
                <tr key={a.id}>
                  <td>{a.advisor_name}</td>
                  <td>{a.year_be ?? 'ทุกปี'}</td>
                  <td>{a.is_primary ? <Badge kind="ok">หลัก</Badge> : <Badge>ร่วม</Badge>}</td>
                  <td>{thaiDate(a.assigned_on)}</td>
                  {canWrite && (
                  <td>
                    <ActionButton
                      className="danger"
                      confirm="สิ้นสุดการเป็นที่ปรึกษา ยืนยันหรือไม่"
                      onRun={() => api.del(`/students/${p.id}/advisors/${a.id}`)}
                      onDone={reload}
                    >
                      สิ้นสุด
                    </ActionButton>
                  </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </TableCard>

      {canWrite && (
      <Card title="มอบหมายอาจารย์ที่ปรึกษา">
        <div className="row">
          <Field label="อาจารย์">
            <select value={staffId} onChange={(e) => setStaffId(e.target.value)}>
              <option value="">— เลือกอาจารย์ —</option>
              {staff.map((s) => (
                <option key={s.id} value={s.id}>{s.full_name}</option>
              ))}
            </select>
          </Field>
          <div className="shrink">
            <ActionButton
              className="primary"
              onRun={() => api.post(`/students/${p.id}/advisors`, { staffId, isPrimary: true })}
              onDone={() => {
                setStaffId('');
                reload();
              }}
            >
              มอบหมายเป็นที่ปรึกษาหลัก
            </ActionButton>
          </div>
        </div>
        <Notice kind="info">
          มอบหมายคนใหม่จะ<strong>ปิด</strong>ที่ปรึกษาหลักคนเดิมด้วย <code>ended_on</code>
          ไม่ใช่ลบทิ้ง — ต้องรู้ย้อนหลังได้ว่าใครดูแลอยู่ตอนเกิดเรื่อง
        </Notice>
      </Card>
      )}

      {past.length > 0 && (
        <TableCard title="ที่ปรึกษาในอดีต">
          <table>
            <thead>
              <tr>
                <th>อาจารย์ที่ปรึกษา</th>
                <th style={{ width: 110 }}>ปีการศึกษา</th>
                <th style={{ width: 130 }}>ตั้งแต่</th>
                <th style={{ width: 130 }}>ถึง</th>
              </tr>
            </thead>
            <tbody>
              {past.map((a) => (
                <tr key={a.id}>
                  <td>{a.advisor_name}</td>
                  <td>{a.year_be ?? 'ทุกปี'}</td>
                  <td>{thaiDate(a.assigned_on)}</td>
                  <td>{thaiDate(a.ended_on)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </TableCard>
      )}

      <TableCard title="ผู้ปกครองที่เข้าระบบได้">
        {p.guardians.length === 0 ? (
          <div className="empty">ยังไม่มีผู้ปกครองที่ผูกบัญชีไว้</div>
        ) : (
          <table>
            <thead>
              <tr>
                <th>ชื่อผู้ปกครอง</th>
                <th style={{ width: 110 }}>ความเกี่ยวข้อง</th>
                <th style={{ width: 120 }}>โทรศัพท์</th>
                <th style={{ width: 90 }}>หลัก</th>
                <th style={{ width: 200 }}>สิทธิ์ที่ได้</th>
                <th style={{ width: 150 }}>ยืนยันตัวตน</th>
              </tr>
            </thead>
            <tbody>
              {p.guardians.map((g) => (
                <tr key={g.id}>
                  <td>{g.guardian_name}</td>
                  <td>{GUARDIAN_RELATION[g.relation] ?? g.relation}</td>
                  <td>{g.phone ?? '—'}</td>
                  <td>{g.is_primary ? <Badge kind="ok">หลัก</Badge> : '—'}</td>
                  <td style={{ fontSize: 11.5 }}>
                    {[
                      g.can_view_grades && 'ผลการเรียน',
                      g.can_view_finance && 'การเงิน',
                      g.can_approve_leave && 'อนุมัติการลา',
                    ].filter(Boolean).join(' · ') || 'ไม่ได้ให้สิทธิ์ใด'}
                  </td>
                  <td>
                    {g.verified_at
                      ? <Badge kind="ok">ยืนยันแล้ว</Badge>
                      : <Badge kind="danger">ยังไม่ยืนยัน</Badge>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </TableCard>

      <Notice kind="warn">
        ผู้ปกครองที่<strong>ยังไม่ยืนยันตัวตน</strong>จะไม่ได้รับข้อมูลผลการเรียน
        หรือข้อมูลอ่อนไหวใด ๆ แม้จะติ๊กสิทธิ์ไว้แล้ว — เป็นมาตรการคุ้มครองผู้เยาว์
        ที่บังคับอยู่ที่ฐานข้อมูล ไม่ใช่ที่หน้าจอ
      </Notice>
    </>
  );
}

/* ─── สถานะนักศึกษา ─────────────────────────────────────────────── */

/** สถานะที่แปลว่าออกจากสถานศึกษาจริง — ใบ รบ. พิมพ์วันที่และเหตุผลของกลุ่มนี้ */
const LEAVING = ['withdrawn', 'transferred_out', 'dismissed', 'graduated'];

/**
 * เปลี่ยนสถานะนักศึกษาพร้อมวันที่และเหตุผล
 *
 * ─── ทำไมช่อง "เหตุที่ออก" อยู่ที่นี่ ไม่ใช่ที่หน้าออกเอกสาร ───
 * เพราะมันเป็นข้อเท็จจริงของนักศึกษา ไม่ใช่ของกระดาษใบนั้น — ใบ รบ. ทุกใบ
 * ที่ออกให้คนคนเดียวกันต้องเขียนเหตุผลเดียวกันเสมอ และคนที่รู้เหตุผลจริง
 * คือคนที่กดเปลี่ยนสถานะ ไม่ใช่คนที่กดพิมพ์ใบในอีกสองปีถัดมา
 *
 * ─── ทำไมบังคับเหตุผลเฉพาะบางสถานะ ───
 * สี่สถานะที่แปลว่าออกจากสถานศึกษาจะถูกพิมพ์ลงใบ ระเบียนแสดงผลการเรียน
 * ใบที่เว้นช่อง "เหตุที่ออก" ว่างไว้คือเอกสารที่ตอบคำถามของคนอ่านไม่ได้
 * ส่วนการลาพักหรือกลับมาเรียนต่อไม่ได้ขึ้นใบ จึงไม่ต้องบังคับ —
 * ถ้าบังคับทุกสถานะ คนกรอกจะใส่จุดเดียวไปให้พ้น ๆ ซึ่งแย่กว่าไม่ถาม
 */
export function StatusTab({ p, reload }: { p: FullProfile; reload: () => void }) {
  const canWrite = useCan('registrar', 'academic', 'director', 'admin');
  const [status, setStatus] = useState(p.status);
  const [effectiveOn, setEffectiveOn] = useState(new Date().toISOString().slice(0, 10));
  const [reason, setReason] = useState('');
  const [documentNo, setDocumentNo] = useState('');

  const needsReason = LEAVING.includes(status);
  const ready = status !== '' && effectiveOn !== '' && (!needsReason || reason.trim() !== '');

  return (
    <Card title="สถานะนักศึกษา">
      <div className="row">
        <Field label="สถานะปัจจุบัน">
          <input value={STUDENT_STATUS[p.status] ?? p.status} readOnly />
        </Field>
      </div>

      {!canWrite ? (
        <Notice kind="warn">
          ไม่มีสิทธิ์เปลี่ยนสถานะ — งานทะเบียน งานวิชาการ และผู้อำนวยการเท่านั้น
        </Notice>
      ) : (
        <>
          <div className="row">
            <label className="field">
              <span>เปลี่ยนเป็น</span>
              <select value={status} onChange={(e) => setStatus(e.target.value)}>
                {Object.entries(STUDENT_STATUS).map(([k, v]) => (
                  <option key={k} value={k}>{v}</option>
                ))}
              </select>
            </label>
            <Field label="มีผลวันที่">
              <input
                type="date"
                value={effectiveOn}
                onChange={(e) => setEffectiveOn(e.target.value)}
              />
            </Field>
            <Field label="เลขที่คำสั่ง/หนังสือ">
              <input value={documentNo} onChange={(e) => setDocumentNo(e.target.value)} />
            </Field>
          </div>
          <div className="row">
            <Field
              label={needsReason ? 'เหตุที่ออก (พิมพ์บนใบ รบ.)' : 'เหตุผล'}
            >
              <input
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                placeholder={needsReason ? 'เช่น สำเร็จการศึกษาตามหลักสูตร' : '(ไม่บังคับ)'}
              />
            </Field>
          </div>

          {needsReason && (
            <Notice kind="warn">
              สถานะนี้จะถูกพิมพ์ในช่อง “ออกจากสถานศึกษาเมื่อ” และ “เหตุที่ออก”
              บนใบระเบียนแสดงผลการเรียน — ใบที่ออกไปแล้วจะยังเขียนค่าเดิม
              เพราะเนื้อหาของเอกสารที่ออกแล้วแก้ไม่ได้
            </Notice>
          )}

          <ActionButton
            confirm={
              needsReason
                ? 'สถานะนี้จะขึ้นบนใบ รบ. และประวัติการเปลี่ยนสถานะลบไม่ได้ ยืนยันหรือไม่'
                : undefined
            }
            onRun={() =>
              ready
                ? api.post(`/students/${p.id}/status`, {
                    status,
                    effectiveOn,
                    reason: reason.trim() || undefined,
                    documentNo: documentNo.trim() || undefined,
                  })
                : Promise.reject(new Error('กรอกไม่ครบ'))
            }
            onDone={reload}
          >
            บันทึกสถานะ
          </ActionButton>
          {!ready && (
            <Notice kind="warn">
              {needsReason && reason.trim() === ''
                ? 'ต้องระบุเหตุที่ออก เพราะจะถูกพิมพ์บนใบ รบ.'
                : 'กรอกสถานะและวันที่ให้ครบก่อน'}
            </Notice>
          )}
        </>
      )}

      <div style={{ marginTop: 12 }}>
        <StatusHistory studentId={p.id} />
      </div>
    </Card>
  );
}

/** ประวัติการเปลี่ยนสถานะ — ลบไม่ได้ จึงใช้ยันย้อนหลังได้ว่าใครเปลี่ยนอะไรเมื่อไร */
function StatusHistory({ studentId }: { studentId: string }) {
  const [rows, setRows] = useState<
    { to_status: string; effective_on: string; reason: string | null; document_no: string | null }[]
  >([]);
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    api
      .get<typeof rows>(`/students/${studentId}/status-history`)
      .then(setRows)
      .catch(() => setRows([]))
      .finally(() => setLoaded(true));
  }, [studentId]);

  if (!loaded || rows.length === 0) return null;
  return (
    <TableCard title="ประวัติการเปลี่ยนสถานะ">
      <table>
        <thead>
          <tr>
            <th style={{ width: 140 }}>มีผลวันที่</th>
            <th style={{ width: 170 }}>สถานะ</th>
            <th>เหตุผล</th>
            <th style={{ width: 170 }}>เลขที่คำสั่ง</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={`${r.effective_on}-${i}`}>
              <td>{thaiDate(r.effective_on)}</td>
              <td>{STUDENT_STATUS[r.to_status] ?? r.to_status}</td>
              <td style={{ whiteSpace: 'normal' }}>{r.reason ?? '—'}</td>
              <td>{r.document_no ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </TableCard>
  );
}
