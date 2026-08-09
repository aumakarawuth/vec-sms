# ═══════════════════════════════════════════════════════════════════
# API — ระบบบริหารวิทยาลัยอาชีวศึกษาเอกชน
#
#   docker build -t vecsms-api -f api/Dockerfile .
#   docker run -p 3000:3000 --env-file api/.env vecsms-api
#
# ─── ทำไมต้อง build สองชั้น ───
# ชั้นแรกมี devDependencies และ TypeScript ครบเพื่อคอมไพล์
# ชั้นที่สองเอาเฉพาะ dist กับ dependencies ที่ใช้จริงตอนรัน
# ทำให้ image เล็กลงมากและไม่มี source กับเครื่องมือ build ติดไปในระบบจริง
# ═══════════════════════════════════════════════════════════════════

# ─── ชั้นที่ 1: คอมไพล์ ─────────────────────────────────────────────
FROM node:22-alpine AS build

WORKDIR /app

# คัดลอกไฟล์ manifest ก่อน source เพื่อให้ layer cache ของ npm ci
# ไม่ถูกทิ้งทุกครั้งที่แก้โค้ด
COPY api/package.json api/package-lock.json ./
RUN npm ci

COPY api/tsconfig.json ./
COPY api/src ./src

# ต้องใช้ tsc เท่านั้น ห้ามใช้ tsx หรือ esbuild
# เพราะไม่ปล่อย design:paramtypes metadata ที่ NestJS ใช้ทำ dependency
# injection อาการคือ constructor ได้ undefined ตอนบูต
RUN npm run build

# ตัด devDependencies ออกหลังคอมไพล์เสร็จ
RUN npm prune --omit=dev

# ─── ชั้นที่ 2: รันจริง ─────────────────────────────────────────────
FROM node:22-alpine AS runtime

# เอกสารและข้อความผิดพลาดเป็นภาษาไทยทั้งหมด และวันที่ต้องเป็นเวลาไทย
# มิฉะนั้นงานตามกำหนดเวลาจะรันผิดเวลาไป 7 ชั่วโมง
ENV NODE_ENV=production \
    TZ=Asia/Bangkok
RUN apk add --no-cache tzdata

WORKDIR /app

# รันด้วยผู้ใช้ที่ไม่ใช่ root — เหตุผลเดียวกับที่ห้ามต่อฐานข้อมูลด้วย superuser
# คือลดสิ่งที่ผู้โจมตีทำได้ถ้าเจาะเข้ามาได้จริง
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --chown=node:node api/package.json ./

USER node

EXPOSE 3000

# ใช้ /health ที่เปิดสาธารณะอยู่แล้ว — ตรวจถึงชั้นฐานข้อมูลด้วย ไม่ใช่แค่ว่าโปรเซสยังอยู่
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/api/v1/health').then(r=>r.ok?process.exit(0):process.exit(1)).catch(()=>process.exit(1))"

CMD ["node", "dist/main.js"]
