import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

/*
 * ─── ทำไมพอร์ต 5174 ───
 * 5173 เป็นค่าเริ่มต้นของ Vite ซึ่งเครื่องนักพัฒนามักมีโปรเจกต์อื่นจองอยู่แล้ว
 * และหน้าจอนี้ต้องอยู่ใน CORS_ORIGINS ของ API เสมอ การตรึงพอร์ตไว้ทำให้
 * ไม่ต้องแก้ค่าฝั่ง API ทุกครั้งที่เปิดใหม่
 */
export default defineConfig({
  plugins: [react()],
  server: { port: 5174, strictPort: true },
  // apply.html เป็นหน้าสาธารณะของผู้สมัคร — entry แยก จึงไม่มีโค้ดหน้าจอ
  // เจ้าหน้าที่ (และรายการเมนู/เส้นทางทั้งหมด) ติดไปกับหน้าที่ใครก็เปิดได้
  build: {
    outDir: 'dist',
    sourcemap: false,
    rollupOptions: { input: { main: 'index.html', apply: 'apply.html' } },
  },
});
