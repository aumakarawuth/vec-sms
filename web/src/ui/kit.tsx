/**
 * ชิ้นส่วนหน้าจอที่ใช้ซ้ำทั้งระบบ
 *
 * ─── ทำไมไม่ใช้ชุด component สำเร็จรูป ───
 * หน้าจองานทะเบียนต้องการอยู่สามอย่าง คือตารางหนาแน่น ฟอร์มที่กรอกด้วย
 * คีย์บอร์ดได้ และการแสดงข้อผิดพลาดภาษาไทยจากฐานข้อมูลให้ตรงคำ ชุดสำเร็จรูป
 * ให้ของที่ไม่ได้ใช้อีกหลายร้อยกิโลไบต์ และบังคับรูปแบบที่ต้องเขียนทับอยู่ดี
 */
import { useEffect, useState, type ReactNode } from 'react';
import { ApiError } from '../core/api';

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
}: {
  onRun: () => Promise<unknown>;
  children: ReactNode;
  className?: string;
  /** ข้อความยืนยันก่อนทำ — ใช้กับรายการที่ย้อนกลับไม่ได้ */
  confirm?: string;
  onDone?: (result: unknown) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

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
      {error && <Notice kind="error">{error}</Notice>}
    </>
  );
}
