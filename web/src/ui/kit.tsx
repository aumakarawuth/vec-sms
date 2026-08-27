/**
 * ชิ้นส่วนหน้าจอที่ใช้ซ้ำทั้งระบบ
 *
 * ─── ทำไมไม่ใช้ชุด component สำเร็จรูป ───
 * หน้าจองานทะเบียนต้องการอยู่สามอย่าง คือตารางหนาแน่น ฟอร์มที่กรอกด้วย
 * คีย์บอร์ดได้ และการแสดงข้อผิดพลาดภาษาไทยจากฐานข้อมูลให้ตรงคำ ชุดสำเร็จรูป
 * ให้ของที่ไม่ได้ใช้อีกหลายร้อยกิโลไบต์ และบังคับรูปแบบที่ต้องเขียนทับอยู่ดี
 */
import { useEffect, useState, type ReactNode } from 'react';
import { ApiError, api } from '../core/api';

/* ─── การโหลดข้อมูล ─────────────────────────────────────────────── */

export interface Async<T> {
  data: T | null;
  error: string | null;
  loading: boolean;
  reload: () => void;
}

/**
 * โหลดข้อมูลจาก API หนึ่งชุด
 *
 * ไม่มีแคชโดยตั้งใจ — ดูเหตุผลใน core/api.ts ทุกครั้งที่เข้าหน้าใหม่
 * หรือกดโหลดซ้ำ คือการอ่านค่าล่าสุดจริง ๆ
 */
export function useAsync<T>(load: () => Promise<T>, deps: unknown[]): Async<T> {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError(null);
    load()
      .then((d) => { if (alive) setData(d); })
      .catch((e: unknown) => {
        if (!alive) return;
        setError(e instanceof ApiError ? e.message : 'โหลดข้อมูลไม่สำเร็จ');
      })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick]);

  return { data, error, loading, reload: () => setTick((t) => t + 1) };
}

/** แสดงสถานะโหลด/ผิดพลาด/ว่าง ให้เหมือนกันทุกหน้า */
export function AsyncView<T>({
  state,
  empty,
  children,
}: {
  state: Async<T>;
  empty?: string;
  children: (data: T) => ReactNode;
}) {
  if (state.loading && state.data === null) return <div className="loading">กำลังโหลด…</div>;
  if (state.error) return <Notice kind="error">{state.error}</Notice>;
  if (state.data === null) return <div className="empty">{empty ?? 'ไม่มีข้อมูล'}</div>;
  if (Array.isArray(state.data) && state.data.length === 0)
    return <div className="empty">{empty ?? 'ไม่มีข้อมูล'}</div>;
  return <>{children(state.data)}</>;
}

/* ─── ชิ้นส่วนพื้นฐาน ───────────────────────────────────────────── */

export function Notice({
  kind = 'info',
  children,
}: {
  kind?: 'info' | 'error' | 'warn' | 'ok';
  children: ReactNode;
}) {
  return <div className={`notice ${kind}`}>{children}</div>;
}

export function Card({
  title,
  actions,
  children,
}: {
  title?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="card">
      {(title || actions) && (
        <header>
          <span>{title}</span>
          <span style={{ flex: 1 }} />
          {actions}
        </header>
      )}
      <div className="body">{children}</div>
    </div>
  );
}

/** การ์ดที่เนื้อในเป็นตาราง — ไม่ต้องมี padding รอบตาราง */
export function TableCard({
  title,
  actions,
  children,
}: {
  title?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className="card">
      {(title || actions) && (
        <header>
          <span>{title}</span>
          <span style={{ flex: 1 }} />
          {actions}
        </header>
      )}
      {children}
    </div>
  );
}

export function Field({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
    </label>
  );
}

export function Badge({
  kind = 'default',
  children,
}: {
  kind?: 'default' | 'ok' | 'warn' | 'danger' | 'info';
  children: ReactNode;
}) {
  return <span className={`badge ${kind === 'default' ? '' : kind}`}>{children}</span>;
}

/**
 * แถบแท็บ — ใช้กับระเบียนที่มีข้อมูลหลายกลุ่มจนใส่หน้าเดียวไม่ไหว
 *
 * ─── ทำไมสถานะแท็บอยู่ใน URL ───
 * เจ้าหน้าที่ทะเบียนเปิดระเบียนหลายคนพร้อมกันเป็นเรื่องปกติ (คัดลอกลิงก์
 * ส่งให้กันทางแชท กดปุ่มย้อนกลับ เปิดแท็บใหม่) ถ้าเก็บไว้ใน state ล้วน
 * ลิงก์ที่ส่งไปจะเปิดมาที่แท็บแรกเสมอ แล้วคนรับต้องเดาว่าให้ดูตรงไหน
 */
export function Tabs({
  tabs,
  active,
  onChange,
}: {
  tabs: { key: string; label: string; badge?: ReactNode }[];
  active: string;
  onChange: (key: string) => void;
}) {
  return (
    <div className="tabs">
      {tabs.map((t) => (
        <button
          key={t.key}
          className={t.key === active ? 'tab active' : 'tab'}
          onClick={() => onChange(t.key)}
        >
          {t.label}
          {t.badge != null && <span className="tab-badge">{t.badge}</span>}
        </button>
      ))}
    </div>
  );
}

export function PageHead({
  title,
  sub,
  actions,
}: {
  title: string;
  sub?: ReactNode;
  actions?: ReactNode;
}) {
  return (
    <div className="page-head">
      <h2>{title}</h2>
      {sub && <span className="sub">{sub}</span>}
      <span className="grow" />
      {actions}
    </div>
  );
}

/** ปุ่มที่กดแล้วยิง API — จัดการสถานะกำลังส่งและข้อความผิดพลาดให้ */
export function ActionButton({
  onRun,
  children,
  className = '',
  confirm,
  onDone,
  toast = false,
}: {
  onRun: () => Promise<unknown>;
  children: ReactNode;
  className?: string;
  /** ข้อความยืนยันก่อนทำ — ใช้กับรายการที่ย้อนกลับไม่ได้ */
  confirm?: string;
  onDone?: (result: unknown) => void;
  /**
   * แสดง error เป็นแผงลอยมุมจอแทนกล่องแทรกอยู่ในหน้า — ใช้กับปุ่มที่อยู่ใน
   * dialog ลอย (cascade-editor) ซึ่งพื้นที่แคบ กล่อง error แบบเดิมจะดัน
   * เลย์เอาต์จนฟอร์มขยับ ค่าเริ่มต้นยังเป็นกล่องแทรกเหมือนเดิมเพื่อไม่กระทบ
   * ฟอร์มอื่นที่ใช้ ActionButton อยู่แล้วทั้งระบบ
   */
  toast?: boolean;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!toast || !error) return;
    const t = setTimeout(() => setError(null), 6000);
    return () => clearTimeout(t);
  }, [toast, error]);

  return (
    <>
      <button
        className={className}
        disabled={busy}
        onClick={async () => {
          if (confirm && !window.confirm(confirm)) return;
          setBusy(true);
          setError(null);
          try {
            const r = await onRun();
            onDone?.(r);
          } catch (e) {
            setError(e instanceof ApiError ? e.message : 'ทำรายการไม่สำเร็จ');
          } finally {
            setBusy(false);
          }
        }}
      >
        {busy ? 'กำลังทำ…' : children}
      </button>
      {error && (toast
        ? <div className="toast-error" role="alert">{error}<button onClick={() => setError(null)} aria-label="ปิด">×</button></div>
        : <Notice kind="error">{error}</Notice>)}
    </>
  );
}

/* ─── การพิมพ์ ───────────────────────────────────────────────────── */

/**
 * ปุ่มพิมพ์
 *
 * ─── ทำไมทุกปุ่มพิมพ์ต้องผ่านตัวนี้ ───
 * `<a href>` และ `window.open()` ตั้งเฮดเดอร์ `Authorization` ไม่ได้ ส่วน
 * `AuthGuard` อ่าน token จากที่นั่นอย่างเดียว ทุกลิงก์พิมพ์จึงได้ 401 ทุกครั้ง
 * — ยืนยันด้วยการยิงจริงแล้ว (`{"message":"ต้องแนบ Bearer token"}`)
 * `api.openPrintable()` ดึงด้วย fetch ที่มีเฮดเดอร์แล้วเขียนลงแท็บใหม่
 */
export function PrintButton({
  path,
  children,
  className = '',
}: {
  path: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <ActionButton className={className} onRun={() => api.openPrintable(path)}>
      {children}
    </ActionButton>
  );
}

/**
 * ตัวเลือกกระดาษและระยะเลื่อนของเครื่องพิมพ์
 *
 * ─── ทำไมเก็บที่เครื่อง ไม่ใช่ที่วิทยาลัย ───
 * วิทยาลัยหนึ่งแห่งมีเครื่องพิมพ์หลายเครื่องที่ป้อนกระดาษเหลื่อมกันคนละระยะ
 * และเครื่องในห้องทะเบียนเครื่องหนึ่งมักใส่กระดาษตราค้างไว้ตลอด ค่านี้จึงเป็น
 * ของ**เครื่องที่นั่งอยู่** ไม่ใช่ของสถานศึกษา
 *
 * ใช้ `localStorage` ไม่ใช่ `sessionStorage` ต่างจาก token โดยตั้งใจ —
 * ค่านี้ไม่ใช่ความลับและตั้งใหม่ทุกเช้าไม่ไหว ส่วน token ต้องหายเมื่อปิดแท็บ
 */
export interface PrintPaper {
  paper: 'plain' | 'letterhead';
  dx: number;
  dy: number;
  /**
   * รูปแบบใบ รบ. ของหลักสูตรรุ่นก่อน 67
   *
   * เก็บรวมกับค่ากระดาษเพราะเป็นค่าที่ตั้งครั้งเดียวแล้วใช้ทั้งวันเหมือนกัน
   * — วิทยาลัยหนึ่งแห่งยื่นให้หน่วยงานเดิมเป็นประจำ ไม่ได้สลับรายใบ
   */
  form: '62' | 'sorsor';
}

const PRINT_KEY = 'vecsms.print';

export function readPrintPaper(): PrintPaper {
  try {
    const raw = localStorage.getItem(PRINT_KEY);
    if (raw) {
      const v = JSON.parse(raw) as Partial<PrintPaper>;
      return {
        paper: v.paper === 'letterhead' ? 'letterhead' : 'plain',
        dx: Number(v.dx) || 0,
        dy: Number(v.dy) || 0,
        form: v.form === 'sorsor' ? 'sorsor' : '62',
      };
    }
  } catch {
    /* ค่าที่อ่านไม่ได้ให้ใช้ค่าเริ่มต้น ดีกว่าทำให้ทั้งหน้าพัง */
  }
  return { paper: 'plain', dx: 0, dy: 0, form: '62' };
}

/** ต่อท้าย path ของการพิมพ์ — ไม่ส่งค่าที่เป็นค่าเริ่มต้นเพื่อให้ URL อ่านง่าย */
export function printQuery(p: PrintPaper): string {
  const q = new URLSearchParams();
  if (p.paper === 'letterhead') q.set('paper', 'letterhead');
  if (p.dx) q.set('offsetX', String(p.dx));
  if (p.dy) q.set('offsetY', String(p.dy));
  if (p.form === 'sorsor') q.set('form', 'sorsor');
  const s = q.toString();
  return s ? `?${s}` : '';
}

export function PrintPaperControl({
  value,
  onChange,
}: {
  value: PrintPaper;
  onChange: (v: PrintPaper) => void;
}) {
  const set = (patch: Partial<PrintPaper>) => {
    const next = { ...value, ...patch };
    onChange(next);
    localStorage.setItem(PRINT_KEY, JSON.stringify(next));
  };

  return (
    <div className="row" style={{ alignItems: 'flex-end', gap: 12, flexWrap: 'wrap' }}>
      <Field label="กระดาษ">
        <select
          value={value.paper}
          onChange={(e) => set({ paper: e.target.value as PrintPaper['paper'] })}
        >
          <option value="plain">กระดาษเปล่า</option>
          <option value="letterhead">กระดาษตรา (มีหัวพิมพ์มาแล้ว)</option>
        </select>
      </Field>
      <Field label="รูปแบบใบ รบ.">
        <select
          value={value.form}
          onChange={(e) => set({ form: e.target.value as PrintPaper['form'] })}
        >
          <option value="62">แบบ 62 (สรุปรายภาคในตาราง)</option>
          <option value="sorsor">แบบ สอศ. (ตารางสรุปหน้า 2)</option>
        </select>
      </Field>
      <Field label="เลื่อนขวา (pt)">
        <input
          type="number" step="0.5" min={-36} max={36} style={{ width: 90 }}
          value={value.dx}
          onChange={(e) => set({ dx: Number(e.target.value) || 0 })}
        />
      </Field>
      <Field label="เลื่อนลง (pt)">
        <input
          type="number" step="0.5" min={-36} max={36} style={{ width: 90 }}
          value={value.dy}
          onChange={(e) => set({ dy: Number(e.target.value) || 0 })}
        />
      </Field>
      <div style={{ color: 'var(--ink-soft)', fontSize: 11.5, maxWidth: 380 }}>
        กระดาษตราจะไม่พิมพ์หัวเรื่องซ้ำและย่อตารางลงเพื่อไม่ให้ทับตรา ·
        รูปแบบใบ รบ. มีผลกับหลักสูตรรุ่นก่อน 67 เท่านั้น ตัวเลขบนใบเท่ากันทั้งสองแบบ
        ต่างแค่ที่วางสรุปรายภาค · ค่าทั้งหมดเก็บไว้ที่เครื่องนี้เครื่องเดียว
        เพราะแต่ละเครื่องพิมพ์ป้อนกระดาษเหลื่อมกันคนละระยะ
      </div>
    </div>
  );
}
