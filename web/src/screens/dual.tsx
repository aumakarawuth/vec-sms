/**
 * ทวิภาคีและสถานประกอบการ
 *
 * ─── ทำไมหน้านี้เริ่มจาก "ชั่วโมงที่รอรับรอง" ───
 * ชั่วโมงฝึกที่นักศึกษาบันทึกแล้วไม่มีใครรับรอง **ไม่นับเป็นชั่วโมงฝึก**
 * ตราบใดที่ยังค้างอยู่ นักศึกษาจะเห็นตัวเลขที่ตัวเองกรอกแล้วเข้าใจว่าครบแล้ว
 * ทั้งที่ระบบยังไม่นับให้ กองที่ค้างจึงเป็นสิ่งแรกที่ครูนิเทศต้องเห็นตอนเปิดหน้า
 * ไม่ใช่รายชื่อสถานประกอบการซึ่งเปลี่ยนปีละครั้ง
 *
 * ─── ทำไมแยก "รับรองแล้ว" กับ "รอรับรอง" ทุกที่ที่แสดงชั่วโมง ───
 * สองตัวเลขนี้ตอบคนละคำถาม — ตัวแรกคือความคืบหน้าจริงตามหลักสูตร
 * ตัวที่สองคือภาระงานของครูนิเทศ ถ้ารวมเป็นตัวเดียวจะไม่มีใครรู้ว่า
 * นักศึกษาที่ "ครบ 400 ชั่วโมง" นั้นครบจริงหรือแค่กรอกครบ
 *
 * ─── ทำไมสถานประกอบการที่ยังไม่อนุมัติยังส่งนักศึกษาไปได้ในหน้าจอ ───
 * ไม่ได้ — ฐานข้อมูลปฏิเสธเอง หน้าจอจึงไม่ต้องตรวจซ้ำ แต่**แสดงสถานะให้เห็น
 * ชัด**เพื่อให้คนเลือกรู้ก่อนกด ว่าทำไมรายชื่อบางแห่งกดแล้วไม่ผ่าน
 */
import { useState } from 'react';
import { api, qs } from '../core/api';
import { num, thaiDate } from '../core/fmt';
import { href } from '../core/router';
import { useSession } from '../core/session';
import {
  ActionButton, AsyncView, Badge, Card, Field, Notice, PageHead, TableCard, useAsync,
} from '../ui/kit';

interface Workplace {
  id: string;
  code: string;
  name_th: string;
  branch_th: string | null;
  industry: string | null;
  province: string | null;
  status: string;
  capacity: number | null;
  contact_name: string | null;
  contact_phone: string | null;
  assessed_on: string | null;
  approved_at: string | null;
  active_students: string | number;
}

interface Agreement {
  id: string;
  agreement_no: string;
  signed_on: string | null;
  starts_on: string;
  ends_on: string;
  seats: number | null;
  active: boolean;
  scope_th: string | null;
  workplace_code: string;
  workplace_name: string;
  placements: string | number;
}

interface Placement {
  id: string;
  starts_on: string;
  ends_on: string;
  status: string;
  target_hours: number | null;
  student_code: string;
  full_name: string;
  workplace_code: string;
  workplace_name: string;
  supervisor_name: string | null;
  advisor_name: string | null;
  verified_hours: string | number;
  pending_hours: string | number;
}

interface PendingLog {
  id: string;
  worked_on: string;
  hours: string | number;
  description: string | null;
  source: string;
  checkin_at: string | null;
  checkin_lat: number | null;
  checkin_lng: number | null;
  student_code: string;
  full_name: string;
  workplace_name: string | null;
  workplace_lat: number | null;
  workplace_lng: number | null;
  checkin_radius_m: number | null;
}

const WP_STATUS: Record<string, { label: string; kind: 'default' | 'ok' | 'warn' | 'danger' }> = {
  draft: { label: 'ยังไม่ประเมิน', kind: 'default' },
  approved: { label: 'อนุมัติแล้ว', kind: 'ok' },
  suspended: { label: 'ระงับชั่วคราว', kind: 'warn' },
  terminated: { label: 'ยุติความร่วมมือ', kind: 'danger' },
};

const PL_STATUS: Record<string, { label: string; kind: 'default' | 'ok' | 'warn' | 'info' | 'danger' }> = {
  planned: { label: 'วางแผนไว้', kind: 'info' },
  active: { label: 'กำลังฝึก', kind: 'ok' },
  completed: { label: 'ฝึกครบแล้ว', kind: 'default' },
  terminated: { label: 'ยุติก่อนกำหนด', kind: 'danger' },
};

const SOURCE_TH: Record<string, string> = {
  student_app: 'นักศึกษาบันทึกเอง',
  supervisor: 'ครูฝึกในสถานประกอบการ',
  teacher: 'ครูนิเทศ',
  import: 'นำเข้าไฟล์',
};

/** ระยะห่างระหว่างจุดเช็คอินกับสถานประกอบการ เป็นเมตร */
function distanceM(
  aLat: number, aLng: number, bLat: number, bLng: number,
): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(s)));
}

export function DualScreen() {
  const { role } = useSession();
  const canManage = role != null && ['academic', 'registrar', 'director', 'admin'].includes(role);
  const canApprove = role != null && ['academic', 'director', 'admin'].includes(role);

  const [result, setResult] = useState<string | null>(null);
  const [onlyMine, setOnlyMine] = useState(true);
  const [wpStatus, setWpStatus] = useState('');
  const [plStatus, setPlStatus] = useState('active');

  const pending = useAsync(
    () => api.get<PendingLog[]>(`/practicum/pending${qs({ all: onlyMine ? '' : 'true' })}`),
    [onlyMine],
  );
  const workplaces = useAsync(
    () => api.get<Workplace[]>(`/workplaces${qs({ status: wpStatus })}`),
    [wpStatus],
  );
  const placements = useAsync(
    () => api.get<Placement[]>(`/dual/placements${qs({ status: plStatus })}`),
    [plStatus],
  );
  const agreements = useAsync(() => api.get<Agreement[]>('/dual/agreements'), []);

  const [picked, setPicked] = useState<Set<string>>(new Set());
  const toggle = (id: string) =>
    setPicked((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });

  /* ─── ฟอร์มสร้างสถานประกอบการ ─── */
  const [code, setCode] = useState('');
  const [nameTh, setNameTh] = useState('');
  const [industry, setIndustry] = useState('');
  const [province, setProvince] = useState('');
  const [contactName, setContactName] = useState('');
  const [contactPhone, setContactPhone] = useState('');

  const pendingHours = (pending.data ?? []).reduce(
    (a, x) => a + Number(x.hours ?? 0), 0,
  );

  return (
    <>
      <PageHead
        title="ทวิภาคีและสถานประกอบการ"
        sub={pending.data ? `รอรับรอง ${num(pendingHours, 1)} ชั่วโมง` : undefined}
        actions={<a href={href('/registry')}>← ศูนย์งานทะเบียน</a>}
      />

      <Notice kind="info">
        ชั่วโมงฝึกที่ยังไม่มีใครรับรอง <strong>ไม่นับเป็นชั่วโมงฝึก</strong> —
        นักศึกษาเห็นตัวเลขที่ตัวเองกรอกแล้วเข้าใจว่าครบ ทั้งที่ระบบยังไม่นับให้
        กองที่ค้างจึงเป็นสิ่งแรกที่ต้องเคลียร์
      </Notice>

      {result && <Notice kind="ok">{result}</Notice>}

      <TableCard
        title="ชั่วโมงฝึกที่รอการรับรอง"
        actions={
          <label style={{ fontSize: 12, display: 'inline-flex', gap: 6, alignItems: 'center' }}>
            <input
              type="checkbox"
              style={{ width: 'auto' }}
              checked={!onlyMine}
              onChange={(e) => setOnlyMine(!e.target.checked)}
            />
            แสดงของทุกคน ไม่ใช่เฉพาะที่ตัวเองนิเทศ
          </label>
        }
      >
        <AsyncView state={pending} empty="ไม่มีชั่วโมงที่รอรับรอง">
          {(rows) => (
            <>
              <table>
                <thead>
                  <tr>
                    <th style={{ width: 34 }} />
                    <th style={{ width: 130 }}>วันที่ฝึก</th>
                    <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                    <th style={{ width: 170 }}>ชื่อ — นามสกุล</th>
                    <th className="num" style={{ width: 90 }}>ชั่วโมง</th>
                    <th>งานที่ทำ</th>
                    <th style={{ width: 170 }}>ที่มา</th>
                    <th style={{ width: 150 }}>ระยะจากสถานที่</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((l) => {
                    const far =
                      l.checkin_lat != null && l.workplace_lat != null
                        ? distanceM(
                            Number(l.checkin_lat), Number(l.checkin_lng),
                            Number(l.workplace_lat), Number(l.workplace_lng),
                          )
                        : null;
                    const radius = Number(l.checkin_radius_m ?? 0);
                    return (
                      <tr key={l.id}>
                        <td>
                          <input
                            type="checkbox"
                            style={{ width: 'auto' }}
                            checked={picked.has(l.id)}
                            onChange={() => toggle(l.id)}
                          />
                        </td>
                        <td>{thaiDate(l.worked_on)}</td>
                        <td className="mono">{l.student_code}</td>
                        <td>{l.full_name}</td>
                        <td className="num">{num(l.hours, 1)}</td>
                        <td style={{ whiteSpace: 'normal' }}>
                          {l.description ?? '—'}
                          {l.workplace_name && (
                            <div style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>
                              {l.workplace_name}
                            </div>
                          )}
                        </td>
                        <td style={{ fontSize: 11.5 }}>{SOURCE_TH[l.source] ?? l.source}</td>
                        <td>
                          {far == null ? (
                            <span style={{ color: 'var(--ink-faint)' }}>ไม่มีพิกัด</span>
                          ) : far <= radius || radius === 0 ? (
                            <Badge kind="ok">{far} ม.</Badge>
                          ) : (
                            <Badge kind="warn">{far} ม. (เกิน {radius})</Badge>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>

              <div className="card-actions" style={{ padding: 12, display: 'flex', gap: 10, alignItems: 'center' }}>
                <ActionButton
                  className="primary"
                  confirm={`รับรอง ${picked.size} รายการ — ชั่วโมงจะถูกนับเข้าหลักสูตรทันที ยืนยันหรือไม่`}
                  onRun={() => api.post('/practicum/verify', { logIds: [...picked], verify: true })}
                  onDone={() => {
                    setResult(`รับรองแล้ว ${picked.size} รายการ`);
                    setPicked(new Set());
                    pending.reload();
                    placements.reload();
                  }}
                >
                  รับรองที่เลือก
                </ActionButton>
                <ActionButton
                  className="danger"
                  confirm={`ถอนการรับรอง ${picked.size} รายการ ยืนยันหรือไม่`}
                  onRun={() => api.post('/practicum/verify', { logIds: [...picked], verify: false })}
                  onDone={() => {
                    setResult(`ถอนการรับรองแล้ว ${picked.size} รายการ`);
                    setPicked(new Set());
                    pending.reload();
                  }}
                >
                  ไม่รับรอง
                </ActionButton>
                <span style={{ color: 'var(--ink-soft)', fontSize: 12 }}>
                  เลือกไว้ {picked.size} รายการ · ระยะที่เกินรัศมีไม่ได้แปลว่าโกง
                  แต่แปลว่า<strong>ต้องถามก่อนรับรอง</strong>
                </span>
              </div>
            </>
          )}
        </AsyncView>
      </TableCard>

      <TableCard
        title="ใบส่งตัวนักศึกษา"
        actions={
          <select value={plStatus} onChange={(e) => setPlStatus(e.target.value)} style={{ width: 180 }}>
            <option value="">ทุกสถานะ</option>
            {Object.entries(PL_STATUS).map(([k, v]) => (
              <option key={k} value={k}>{v.label}</option>
            ))}
          </select>
        }
      >
        <AsyncView state={placements} empty="ไม่มีใบส่งตัวในสถานะนี้">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 130 }}>รหัสนักศึกษา</th>
                  <th style={{ width: 170 }}>ชื่อ — นามสกุล</th>
                  <th>สถานประกอบการ</th>
                  <th style={{ width: 190 }}>ช่วงฝึก</th>
                  <th className="num" style={{ width: 110 }}>รับรองแล้ว</th>
                  <th className="num" style={{ width: 100 }}>รอรับรอง</th>
                  <th className="num" style={{ width: 90 }}>เป้าหมาย</th>
                  <th style={{ width: 130 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((p) => (
                  <tr key={p.id}>
                    <td className="mono">{p.student_code}</td>
                    <td>{p.full_name}</td>
                    <td>
                      {p.workplace_name}
                      <div style={{ color: 'var(--ink-soft)', fontSize: 11.5 }}>
                        ครูฝึก {p.supervisor_name ?? '—'} · ครูนิเทศ {p.advisor_name ?? '—'}
                      </div>
                    </td>
                    <td>{thaiDate(p.starts_on)} – {thaiDate(p.ends_on)}</td>
                    <td className="num">{num(p.verified_hours, 1)}</td>
                    <td className="num">
                      {Number(p.pending_hours) > 0
                        ? <Badge kind="warn">{num(p.pending_hours, 1)}</Badge>
                        : '—'}
                    </td>
                    <td className="num">{p.target_hours ?? '—'}</td>
                    <td>
                      <Badge kind={PL_STATUS[p.status]?.kind ?? 'default'}>
                        {PL_STATUS[p.status]?.label ?? p.status}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
        <Notice kind="info">
          “รับรองแล้ว” กับ “รอรับรอง” แยกกันโดยตั้งใจ — ตัวแรกคือความคืบหน้าจริง
          ตามหลักสูตร ตัวที่สองคือภาระงานของครูนิเทศ ถ้ารวมเป็นตัวเดียว
          จะไม่มีใครรู้ว่าคนที่ “ครบแล้ว” ครบจริงหรือแค่กรอกครบ
        </Notice>
      </TableCard>

      <TableCard
        title="สถานประกอบการ"
        actions={
          <select value={wpStatus} onChange={(e) => setWpStatus(e.target.value)} style={{ width: 180 }}>
            <option value="">ทุกสถานะ</option>
            {Object.entries(WP_STATUS).map(([k, v]) => (
              <option key={k} value={k}>{v.label}</option>
            ))}
          </select>
        }
      >
        <AsyncView state={workplaces} empty="ยังไม่มีสถานประกอบการ">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 110 }}>รหัส</th>
                  <th>ชื่อสถานประกอบการ</th>
                  <th style={{ width: 150 }}>ประเภทกิจการ</th>
                  <th style={{ width: 110 }}>จังหวัด</th>
                  <th style={{ width: 170 }}>ผู้ติดต่อ</th>
                  <th className="num" style={{ width: 110 }}>กำลังฝึกอยู่</th>
                  <th style={{ width: 140 }}>สถานะ</th>
                  {canApprove && <th style={{ width: 110 }} />}
                </tr>
              </thead>
              <tbody>
                {rows.map((w) => (
                  <tr key={w.id}>
                    <td className="mono">{w.code}</td>
                    <td>
                      {w.name_th}
                      {w.branch_th && (
                        <span style={{ color: 'var(--ink-soft)' }}> — {w.branch_th}</span>
                      )}
                    </td>
                    <td>{w.industry ?? '—'}</td>
                    <td>{w.province ?? '—'}</td>
                    <td style={{ fontSize: 11.5 }}>
                      {w.contact_name ?? '—'}
                      {w.contact_phone && <div>{w.contact_phone}</div>}
                    </td>
                    <td className="num">
                      {w.active_students}
                      {w.capacity ? ` / ${w.capacity}` : ''}
                    </td>
                    <td>
                      <Badge kind={WP_STATUS[w.status]?.kind ?? 'default'}>
                        {WP_STATUS[w.status]?.label ?? w.status}
                      </Badge>
                      {w.assessed_on && (
                        <div style={{ color: 'var(--ink-faint)', fontSize: 11 }}>
                          ประเมิน {thaiDate(w.assessed_on)}
                        </div>
                      )}
                    </td>
                    {canApprove && (
                      <td>
                        {w.status === 'draft' ? (
                          <ActionButton
                            className="primary"
                            confirm={`อนุมัติ ${w.name_th} ให้รับนักศึกษาฝึกได้ ยืนยันหรือไม่`}
                            onRun={() => api.post(`/workplaces/${w.id}/approve`, {})}
                            onDone={() => {
                              setResult(`อนุมัติ ${w.name_th} แล้ว`);
                              workplaces.reload();
                            }}
                          >
                            อนุมัติ
                          </ActionButton>
                        ) : '—'}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
        <Notice kind="warn">
          ส่งนักศึกษาไปยังสถานประกอบการที่<strong>ยังไม่อนุมัติ</strong>ไม่ได้ —
          ฐานข้อมูลปฏิเสธเอง ไม่ใช่หน้าจอกันไว้ การประเมินสถานประกอบการก่อนส่งเด็กไป
          เป็นข้อกำหนดของหลักสูตรทวิภาคี
        </Notice>
      </TableCard>

      {canManage && (
        <Card title="เพิ่มสถานประกอบการ">
          <div className="row">
            <Field label="รหัส">
              <input value={code} onChange={(e) => setCode(e.target.value)} placeholder="เช่น WP-001" />
            </Field>
            <Field label="ชื่อสถานประกอบการ">
              <input value={nameTh} onChange={(e) => setNameTh(e.target.value)} />
            </Field>
            <Field label="ประเภทกิจการ">
              <input value={industry} onChange={(e) => setIndustry(e.target.value)} />
            </Field>
            <Field label="จังหวัด">
              <input value={province} onChange={(e) => setProvince(e.target.value)} />
            </Field>
          </div>
          <div className="row">
            <Field label="ชื่อผู้ติดต่อ">
              <input value={contactName} onChange={(e) => setContactName(e.target.value)} />
            </Field>
            <Field label="โทรศัพท์">
              <input value={contactPhone} onChange={(e) => setContactPhone(e.target.value)} />
            </Field>
            <div className="shrink">
              <ActionButton
                className="primary"
                onRun={() =>
                  api.post('/workplaces', {
                    code, nameTh,
                    industry: industry || undefined,
                    province: province || undefined,
                    contactName: contactName || undefined,
                    contactPhone: contactPhone || undefined,
                  })
                }
                onDone={() => {
                  setResult(`เพิ่ม ${nameTh} แล้ว — ต้องประเมินและอนุมัติก่อนส่งนักศึกษาไปฝึก`);
                  setCode(''); setNameTh(''); setIndustry('');
                  setProvince(''); setContactName(''); setContactPhone('');
                  workplaces.reload();
                }}
              >
                เพิ่มสถานประกอบการ
              </ActionButton>
            </div>
          </div>
        </Card>
      )}

      <TableCard title="ข้อตกลงความร่วมมือ (MOU)">
        <AsyncView state={agreements} empty="ยังไม่มีข้อตกลง">
          {(rows) => (
            <table>
              <thead>
                <tr>
                  <th style={{ width: 160 }}>เลขที่ข้อตกลง</th>
                  <th>สถานประกอบการ</th>
                  <th style={{ width: 200 }}>ช่วงเวลา</th>
                  <th className="num" style={{ width: 90 }}>ที่นั่ง</th>
                  <th className="num" style={{ width: 110 }}>ส่งไปแล้ว</th>
                  <th style={{ width: 110 }}>สถานะ</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((a) => (
                  <tr key={a.id}>
                    <td className="mono">{a.agreement_no}</td>
                    <td>{a.workplace_name}</td>
                    <td>{thaiDate(a.starts_on)} – {thaiDate(a.ends_on)}</td>
                    <td className="num">{a.seats ?? '—'}</td>
                    <td className="num">{a.placements}</td>
                    <td>
                      <Badge kind={a.active ? 'ok' : 'default'}>
                        {a.active ? 'ใช้อยู่' : 'สิ้นสุดแล้ว'}
                      </Badge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </AsyncView>
      </TableCard>
    </>
  );
}
