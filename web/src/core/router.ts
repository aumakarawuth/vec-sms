/**
 * ตัวจัดเส้นทางแบบ hash — เขียนเองราว 60 บรรทัด
 *
 * ─── ทำไมไม่ใช้ไลบรารี ───
 * หน้าจอชุดนี้เป็นเว็บภายในที่ deploy เป็นไฟล์คงที่ ความต้องการมีแค่
 * "เปลี่ยนหน้าจากลิงก์ และปุ่มย้อนกลับของเบราว์เซอร์ต้องทำงาน" ซึ่งเท่านี้พอ
 *
 * ─── ทำไมเป็น hash ไม่ใช่ history API ───
 * hash ไม่ต้องตั้งค่าอะไรที่ฝั่งเซิร์ฟเวอร์เลย วางบน nginx, Cloudflare Pages
 * หรือ static host อะไรก็ได้แล้วรีเฟรชหน้าลึก ๆ ไม่ 404 — ซึ่งเป็นอาการที่
 * เสียเวลาไล่หาบ่อยและไม่ได้อะไรกลับมา
 */
import { useEffect, useState } from 'react';

export interface Route {
  /** ส่วนของเส้นทางที่ตัดด้วย / เช่น ['students', '<uuid>'] */
  segments: string[];
  /** query string หลัง ? ในส่วน hash */
  query: URLSearchParams;
  path: string;
}

function parse(): Route {
  const raw = location.hash.replace(/^#/, '') || '/';
  const [pathPart = '/', queryPart = ''] = raw.split('?');
  return {
    segments: pathPart.split('/').filter(Boolean),
    query: new URLSearchParams(queryPart),
    path: pathPart,
  };
}

export function navigate(path: string): void {
  if (location.hash === `#${path}`) return;
  location.hash = path;
}

export function useRoute(): Route {
  const [route, setRoute] = useState<Route>(parse);

  useEffect(() => {
    const onChange = () => setRoute(parse());
    addEventListener('hashchange', onChange);
    return () => removeEventListener('hashchange', onChange);
  }, []);

  return route;
}

/** ลิงก์ภายใน — ใช้ <a href="#/..."> ตรง ๆ ได้ ตัวนี้มีไว้ให้เรียกจากโค้ด */
export function href(path: string): string {
  return `#${path}`;
}
