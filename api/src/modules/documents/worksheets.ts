/**
 * เอกสารทำงานที่พิมพ์สด — ใบลงทะเบียน · ใบรายชื่อ · ประกาศผู้มีสิทธิ์สอบ
 *
 * ═══ ทำไมสามใบนี้ไม่ใช่ `issued_document` ═══
 * ระบบนี้แยกเอกสารเป็นสองชนิดที่ปนกันไม่ได้
 *
 *   **เอกสารที่เป็นหลักฐาน** (`issued_document` — แปดใบ) มีเลขที่ของตัวเอง
 *   payload ตรึงตั้งแต่วันที่ออก แก้ไม่ได้ ยกเลิกได้แต่ต้องมีเหตุผล
 *   พิมพ์ซ้ำต้องได้กระดาษใบเดิมเป๊ะ เพราะมีคนถือใบเก่าอยู่
 *
 *   **เอกสารทำงาน** (ไฟล์นี้) ต้องสะท้อน**สถานะปัจจุบัน**เสมอ
 *   ใบรายชื่อที่ตรึงไว้ตั้งแต่สัปดาห์แรกใช้ไม่ได้ในสัปดาห์ที่สิบ เพราะมีคน
 *   เพิ่ม-ถอนไปแล้ว และใบลงทะเบียนถูกพิมพ์ซ้ำหลายรอบระหว่างช่วงเพิ่ม-ถอน
 *   ถ้าทำเป็น `issued_document` จะกินเลขที่เอกสารเพิ่มทุกครั้งที่กดพิมพ์
 *   (หลักข้อ 5 — "เรียกใหม่ = เอกสารคนละใบ กินเลขที่เพิ่มทุกครั้ง")
 *
 * การเลือกผิดด้านทำให้พังคนละแบบ — เอกสารหลักฐานที่พิมพ์สดจะไม่ตรงกับใบที่
 * ส่งไปแล้ว ส่วนเอกสารทำงานที่ตรึงไว้จะทำให้คนทำงานจากข้อมูลเก่า
 *
 * ─── ทำไมทุกใบมีวันเวลาที่พิมพ์กำกับ ───
 * เพราะมันเป็นภาพ ณ วินาทีที่กด ถ้าไม่บอก คนที่หยิบกระดาษขึ้นมาอีกเดือน
 * จะไม่รู้ว่ามันเก่าแค่ไหน — ต่างจากเอกสารหลักฐานที่มีเลขที่กำกับอยู่แล้ว
 */
import {
  Controller,
  Get,
  Header,
  Injectable,
  NotFoundException,
  Param,
  Query,
} from '@nestjs/common';
import { IsIn, IsOptional } from 'class-validator';
import { Roles } from '../../common/auth/auth.guard';
import { DbService } from '../../common/db/db.service';
import { IsUuid, ParseUuidPipe } from '../../common/validation/uuid';
import { thaiDate } from './templates';

/**
 * ตัวกรองของใบรายชื่อ — รับเป็น DTO ไม่ใช่ `@Query('mode')` เดี่ยว ๆ
 *
 * ─── ทำไมต้องปฏิเสธพารามิเตอร์ที่ไม่รู้จัก ───
 * `@Query('name')` เดี่ยวจะ**เมินทุกอย่างที่ไม่ได้ขอ** ส่วน DTO ผ่าน
 * `ValidationPipe` ที่ตั้ง `forbidNonWhitelisted` ไว้ทั้งระบบ
 *
 * ที่สำคัญกับใบชุดนี้คือ **เอกสารทำงานไม่รับตัวเลือกกระดาษตรา** (หลักข้อ 4ก)
 * ถ้ารับแล้วเมินเงียบ ๆ เจ้าหน้าที่ที่ตั้งกระดาษตราไว้แล้วกดพิมพ์ใบรายชื่อ
 * จะได้ใบที่ "ตัวเลือกไม่ทำงาน" โดยไม่มีอะไรบอก — ตอบว่าใช้ไม่ได้ตรง ๆ ดีกว่า
 */
class EmptyQueryDto {}

class RegistrationQueryDto {
  @IsUuid() termId!: string;
}

class RosterQueryDto {
  @IsOptional() @IsIn(['blank'], { message: 'โหมดของใบรายชื่อมีได้แค่ blank' })
  mode?: string;
}

function esc(value: unknown): string {
  if (value === null || value === undefined) return '';
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function money(v: unknown): string {
  if (v === null || v === undefined) return '—';
  return Number(v).toLocaleString('th-TH', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

function thaiDateTime(iso: string): string {
  const d = new Date(iso);
  const time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  return `${thaiDate(iso)} ${time} น.`;
}

const SHEET_STYLE = (orientation: 'portrait' | 'landscape') => `
  @page { size: A4 ${orientation}; margin: 12mm 12mm; }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: 'TH Sarabun New', 'Sarabun', 'Leelawadee UI', 'Tahoma', sans-serif;
    font-size: 14pt; line-height: 1.4; color: #000;
  }
  .center { text-align: center; }
  .right { text-align: right; }
  .muted { color: #444; }
  .school { font-size: 19pt; font-weight: 700; text-align: center; }
  .title { font-size: 17pt; font-weight: 700; text-align: center; margin: 4pt 0 2pt; }
  .sub { text-align: center; font-size: 13pt; margin-bottom: 8pt; }
  .meta { display: flex; flex-wrap: wrap; gap: 4pt 24pt; font-size: 13pt; margin: 8pt 0; }
  table { width: 100%; border-collapse: collapse; margin-top: 6pt; }
  th, td { border: 0.7pt solid #000; padding: 2.5pt 4pt; }
  th { background: #eee; font-weight: 700; font-size: 12.5pt; }
  td.num { text-align: right; }
  td.mid { text-align: center; }
  tfoot td { font-weight: 700; background: #f6f6f6; }
  .sign-row { display: flex; justify-content: space-around; margin-top: 26pt; }
  .sign { text-align: center; min-width: 40%; }
  .sign .line { margin-top: 30pt; border-top: 1pt dotted #000; padding-top: 3pt; }
  .foot { margin-top: 12pt; font-size: 11.5pt; color: #444; }
  /* ช่องเปล่าให้เขียนด้วยมือ — ใบรายชื่อคือกระดาษที่ครูถือเดินเข้าห้อง */
  .blank { background: repeating-linear-gradient(90deg,#fff 0 100%); }
  @media screen {
    body { background: #f4f4f4; padding: 16px; }
    .sheet { background: #fff; margin: 0 auto; padding: 12mm;
             max-width: ${orientation === 'portrait' ? '210mm' : '297mm'};
             box-shadow: 0 1px 6px rgba(0,0,0,.2); }
  }`;

function sheet(title: string, orientation: 'portrait' | 'landscape', body: string): string {
  return `<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<style>${SHEET_STYLE(orientation)}</style>
</head>
<body>
<div class="sheet">
${body}
</div>
</body>
</html>`;
}

/** ท้ายกระดาษที่บอกว่าเป็นภาพ ณ วินาทีไหน — ทุกใบในไฟล์นี้ต้องมี */
function printedAt(extra = ''): string {
  return `<div class="foot">
    พิมพ์เมื่อ ${esc(thaiDateTime(new Date().toISOString()))}
    — เอกสารนี้แสดงสถานะ ณ เวลาที่พิมพ์ ไม่ใช่เอกสารที่มีเลขที่กำกับ
    ${extra}
  </div>`;
}

@Injectable()
export class WorksheetService {
  constructor(private readonly db: DbService) {}

  /**
   * ใบลงทะเบียน — รายวิชาที่ลงในภาคเรียนนั้นพร้อมยอดค่าใช้จ่าย
   *
   * ยอดเงินอ่านจาก `invoice` ที่ออกจริง ไม่ใช่คำนวณจาก `fee_schedule` ใหม่
   * เพราะใบแจ้งหนี้อาจมีส่วนลดหรือทุนที่ระบบคิดเองไม่ได้ ถ้าคำนวณใหม่
   * ตัวเลขบนใบลงทะเบียนจะไม่ตรงกับที่นักศึกษาต้องจ่ายจริง
   */
  async registrationSlip(studentId: string, termId: string) {
    return this.db.tx(async (c) => {
      const head = (
        await c.query(
          `select s.student_code, s.admitted_year_be,
                  trim(coalesce(p.prefix_th,'') || coalesce(p.first_name_th,'')
                       || ' ' || coalesce(p.last_name_th,'')) as full_name,
                  i.name_th as institution_th,
                  pr.name_th as program_th,
                  case pr.level when 'PVC' then 'ปวช.' when 'PVS' then 'ปวส.'
                                when 'TVB' then 'ทล.บ.' end as level_th,
                  scp.study_year, scp.group_code,
                  t.ordinal, ay.year_be,
                  t.add_drop_ends_on
             from student s
             join person p on p.id = s.person_id
             join institution i on i.id = s.institution_id
             join term t on t.id = $2
             join academic_year ay on ay.id = t.academic_year_id
             left join student_curriculum sc on sc.student_id = s.id
                   and (sc.effective_to is null or sc.effective_to >= current_date)
             left join curriculum_version cv on cv.id = sc.curriculum_version_id
             left join curriculum cur on cur.id = cv.curriculum_id
             left join program_track ptr on ptr.id = cur.program_track_id
             left join program pr on pr.id = ptr.program_id
             left join student_class_placement scp
                    on scp.student_id = s.id and scp.academic_year_id = ay.id
            where s.id = $1`,
          [studentId, termId],
        )
      ).rows[0];
      if (!head) throw new NotFoundException('ไม่พบนักศึกษาหรือภาคเรียนที่ระบุ');

      const courses = (
        await c.query(
          `select c.code, c.name_th, c.credits, cs.section_no, e.status,
                  trim(coalesce(tp.prefix_th,'') || coalesce(tp.first_name_th,'')
                       || ' ' || coalesce(tp.last_name_th,'')) as teacher_th
             from enrollment e
             join class_section cs on cs.id = e.class_section_id
             join course c on c.id = cs.course_id
             left join staff tst on tst.id = cs.teacher_id
             left join person tp on tp.id = tst.person_id
            where e.student_id = $1 and e.term_id = $2
              and e.status <> 'dropped'
            order by c.code`,
          [studentId, termId],
        )
      ).rows;

      const invoice = (
        await c.query(
          `select invoice_no, issued_on, due_on, subtotal, discount_total,
                  total, paid_total, total - paid_total as outstanding, status
             from invoice
            where student_id = $1 and term_id = $2 and status <> 'void'
            order by issued_on desc limit 1`,
          [studentId, termId],
        )
      ).rows[0] ?? null;

      return { head, courses, invoice };
    });
  }

  /**
   * ใบรายชื่อของกลุ่มเรียน
   *
   * `blankColumns` คือช่องว่างให้ครูขีดด้วยมือ — ใบรายชื่อคือกระดาษที่ถือ
   * เดินเข้าห้องตอนอินเทอร์เน็ตล่มหรือแท็บเล็ตแบตหมด ถ้าไม่มีช่องเปล่าเลย
   * มันก็เป็นแค่รายชื่อที่ดูสวย ไม่ใช่เครื่องมือทำงาน
   */
  async roster(sectionId: string) {
    return this.db.tx(async (c) => {
      const head = (
        await c.query(
          `select cs.section_no, cs.capacity,
                  c.code, c.name_th as course_th, c.credits,
                  i.name_th as institution_th,
                  t.ordinal, ay.year_be,
                  trim(coalesce(tp.prefix_th,'') || coalesce(tp.first_name_th,'')
                       || ' ' || coalesce(tp.last_name_th,'')) as teacher_th,
                  r.name_th as room_th
             from class_section cs
             join course c on c.id = cs.course_id
             join term t on t.id = cs.term_id
             join academic_year ay on ay.id = t.academic_year_id
             join institution i on i.id = cs.institution_id
             left join staff tst on tst.id = cs.teacher_id
             left join person tp on tp.id = tst.person_id
             left join room r on r.id = cs.room_id
            where cs.id = $1`,
          [sectionId],
        )
      ).rows[0];
      if (!head) throw new NotFoundException('ไม่พบกลุ่มเรียนที่ระบุ');

      const students = (
        await c.query(
          `select s.student_code,
                  trim(coalesce(p.prefix_th,'') || coalesce(p.first_name_th,'')
                       || ' ' || coalesce(p.last_name_th,'')) as full_name,
                  s.class_number,
                  v.pct_to_date, v.attendance_state
             from enrollment e
             join student s on s.id = e.student_id
             join person  p on p.id = s.person_id
             left join v_enrollment_attendance v on v.enrollment_id = e.id
            where e.class_section_id = $1 and e.status = 'enrolled'
            order by s.student_code`,
          [sectionId],
        )
      ).rows;

      return { head, students };
    });
  }
}

@Roles('teacher', 'registrar', 'academic', 'student_affairs', 'director', 'admin')
@Controller('reports')
export class WorksheetController {
  constructor(private readonly svc: WorksheetService) {}

  @Header('content-type', 'text/html; charset=utf-8')
  @Get('registration/:studentId')
  async registration(
    @Param('studentId', ParseUuidPipe) studentId: string,
    @Query() q: RegistrationQueryDto,
  ) {
    const { head, courses, invoice } = await this.svc.registrationSlip(studentId, q.termId);

    const totalCredits = courses.reduce(
      (a: number, x: { credits: number }) => a + Number(x.credits ?? 0), 0,
    );

    const rows = courses
      .map(
        (x: Record<string, unknown>, i: number) => `<tr>
        <td class="mid">${i + 1}</td>
        <td>${esc(x.code)}</td>
        <td>${esc(x.name_th)}</td>
        <td class="mid">${esc(x.section_no)}</td>
        <td class="num">${esc(x.credits)}</td>
        <td>${esc(x.teacher_th)}</td>
      </tr>`,
      )
      .join('\n');

    const feeBlock = invoice
      ? `<table style="margin-top:10pt">
        <tbody>
          <tr><th style="width:30%">เลขที่ใบแจ้งหนี้</th><td>${esc(invoice.invoice_no)}</td></tr>
          <tr><th>ยอดรวม</th><td class="num">${esc(money(invoice.subtotal))} บาท</td></tr>
          <tr><th>ส่วนลด/ทุน</th><td class="num">${esc(money(invoice.discount_total))} บาท</td></tr>
          <tr><th>ยอดที่ต้องชำระ</th><td class="num">${esc(money(invoice.total))} บาท</td></tr>
          <tr><th>ชำระแล้ว</th><td class="num">${esc(money(invoice.paid_total))} บาท</td></tr>
          <tr><th>คงค้าง</th><td class="num">${esc(money(invoice.outstanding))} บาท</td></tr>
          <tr><th>กำหนดชำระ</th><td>${esc(thaiDate(invoice.due_on))}</td></tr>
        </tbody>
      </table>`
      : `<div class="muted" style="margin-top:10pt">
           — ยังไม่ได้ออกใบแจ้งหนี้ของภาคเรียนนี้ —
         </div>`;

    const body = `
<div class="school">${esc(head.institution_th)}</div>
<div class="title">ใบลงทะเบียนเรียน</div>
<div class="sub">ภาคเรียนที่ ${esc(head.ordinal)} ปีการศึกษา ${esc(head.year_be)}</div>

<div class="meta">
  <span><strong>รหัสนักศึกษา</strong> ${esc(head.student_code)}</span>
  <span><strong>ชื่อ–นามสกุล</strong> ${esc(head.full_name)}</span>
  <span><strong>ระดับ/สาขา</strong> ${esc(head.level_th ?? '')} ${esc(head.program_th ?? '')}</span>
  ${head.study_year ? `<span><strong>ชั้นปี</strong> ${esc(head.study_year)}${head.group_code ? ` กลุ่ม ${esc(head.group_code)}` : ''}</span>` : ''}
</div>

<table>
  <thead>
    <tr>
      <th style="width:5%">ที่</th>
      <th style="width:14%">รหัสวิชา</th>
      <th>ชื่อวิชา</th>
      <th style="width:9%">กลุ่ม</th>
      <th style="width:9%">หน่วยกิต</th>
      <th style="width:24%">ผู้สอน</th>
    </tr>
  </thead>
  <tbody>${rows || '<tr><td colspan="6" class="mid">— ยังไม่ได้ลงทะเบียนรายวิชาใด —</td></tr>'}</tbody>
  <tfoot>
    <tr>
      <td colspan="4" class="right">รวมหน่วยกิต</td>
      <td class="num">${esc(totalCredits)}</td>
      <td></td>
    </tr>
  </tfoot>
</table>

${feeBlock}

<div class="sign-row">
  <div class="sign"><div class="line">ลายมือชื่อนักศึกษา</div></div>
  <div class="sign"><div class="line">อาจารย์ที่ปรึกษา</div></div>
  <div class="sign"><div class="line">นายทะเบียน</div></div>
</div>

${printedAt(
  head.add_drop_ends_on
    ? `<br>ช่วงเพิ่ม-ถอนสิ้นสุด ${esc(thaiDate(head.add_drop_ends_on))} — รายวิชาอาจเปลี่ยนได้จนถึงวันนั้น`
    : '',
)}`;

    return sheet(`ใบลงทะเบียน ${head.student_code}`, 'portrait', body);
  }

  /**
   * ใบรายชื่อ — โหมด `blank` สำหรับเช็คชื่อด้วยมือ
   *
   * แยกโหมดเพราะสองใบนี้ใช้คนละงาน ใบที่มีเปอร์เซ็นต์เวลาเรียนไว้ให้ครู
   * ดูสถานะ ส่วนใบเปล่าไว้ถือเดินเข้าห้อง การรวมเป็นใบเดียวจะได้กระดาษ
   * ที่แน่นเกินกว่าจะเขียนลงไปได้
   */
  @Header('content-type', 'text/html; charset=utf-8')
  @Get('roster/:sectionId')
  async roster(
    @Param('sectionId', ParseUuidPipe) sectionId: string,
    @Query() q: RosterQueryDto,
  ) {
    const { head, students } = await this.svc.roster(sectionId);
    const blank = q.mode === 'blank';
    const blankCols = 12;

    /*
     * ─── คอลัมน์แรกเป็น "เลขที่" ได้ต่อเมื่อทุกคนมีเลขที่จริง ───
     * ถ้าบางคนมี บางคนไม่มี แล้วเติมด้วยลำดับแถวแทน จะได้คอลัมน์ที่ปนกัน
     * ระหว่างเลขที่จริงกับตำแหน่งในตาราง — ครูที่ขานชื่อตามเลขจะเรียกผิดคน
     * และ**ไม่มีอะไรบนกระดาษบอกว่ามันปนกันอยู่** จึงเลือกอย่างใดอย่างหนึ่ง
     * ทั้งใบ พร้อมเปลี่ยนหัวคอลัมน์ให้ตรงกับสิ่งที่พิมพ์จริง
     */
    const hasClassNumbers =
      students.length > 0 &&
      students.every((x: { class_number: number | null }) => x.class_number != null);
    if (hasClassNumbers) {
      students.sort(
        (a: { class_number: number }, b: { class_number: number }) =>
          a.class_number - b.class_number,
      );
    }

    const rows = students
      .map((x: Record<string, unknown>, i: number) => {
        const cells = blank
          ? Array.from({ length: blankCols }, () => '<td class="blank"></td>').join('')
          : `<td class="num">${x.pct_to_date != null ? `${Number(x.pct_to_date).toFixed(1)}%` : '—'}</td>
             <td class="mid">${esc(ATT_TH[String(x.attendance_state)] ?? '—')}</td>`;
        return `<tr>
        <td class="mid">${hasClassNumbers ? esc(x.class_number) : i + 1}</td>
        <td>${esc(x.student_code)}</td>
        <td>${esc(x.full_name)}</td>
        ${cells}
      </tr>`;
      })
      .join('\n');

    const headCells = blank
      ? Array.from({ length: blankCols }, (_, i) => `<th style="width:4%">${i + 1}</th>`).join('')
      : `<th style="width:12%">เวลาเรียน</th><th style="width:14%">สถานะ</th>`;

    const body = `
<div class="school">${esc(head.institution_th)}</div>
<div class="title">${blank ? 'ใบรายชื่อสำหรับบันทึกเวลาเรียน' : 'ใบรายชื่อนักศึกษาที่ลงทะเบียนเรียน'}</div>
<div class="sub">ภาคเรียนที่ ${esc(head.ordinal)} ปีการศึกษา ${esc(head.year_be)}</div>

<div class="meta">
  <span><strong>รายวิชา</strong> ${esc(head.code)} ${esc(head.course_th)}</span>
  <span><strong>กลุ่ม</strong> ${esc(head.section_no)}</span>
  <span><strong>หน่วยกิต</strong> ${esc(head.credits)}</span>
  <span><strong>ผู้สอน</strong> ${esc(head.teacher_th ?? '—')}</span>
  ${head.room_th ? `<span><strong>ห้อง</strong> ${esc(head.room_th)}</span>` : ''}
  <span><strong>จำนวน</strong> ${students.length}${head.capacity ? ` / ${esc(head.capacity)}` : ''} คน</span>
</div>

<table>
  <thead>
    <tr>
      <th style="width:6%">${hasClassNumbers ? 'เลขที่' : 'ลำดับ'}</th>
      <th style="width:14%">รหัสนักศึกษา</th>
      <th>ชื่อ — นามสกุล</th>
      ${headCells}
    </tr>
  </thead>
  <tbody>${rows || `<tr><td colspan="${blank ? blankCols + 3 : 5}" class="mid">— ยังไม่มีผู้ลงทะเบียน —</td></tr>`}</tbody>
</table>

<div class="sign-row">
  <div class="sign"><div class="line">ผู้สอน</div></div>
  <div class="sign"><div class="line">หัวหน้าแผนกวิชา</div></div>
</div>

${printedAt(
  (blank ? '<br>ช่องว่างสำหรับบันทึกด้วยมือ — ต้องนำกลับมาบันทึกในระบบภายหลัง' : '') +
  (hasClassNumbers
    ? ''
    : '<br>คอลัมน์แรกเป็น<strong>ลำดับในตาราง</strong> ไม่ใช่เลขที่ในห้อง' +
      ' เพราะยังมีนักศึกษาบางคนที่ยังไม่ได้กำหนดเลขที่'),
)}`;

    return sheet(
      `ใบรายชื่อ ${head.code} ${head.section_no}`,
      blank ? 'landscape' : 'portrait',
      body,
    );
  }

  /**
   * ประกาศรายชื่อผู้มีสิทธิ์และผู้หมดสิทธิ์สอบ
   *
   * ─── ทำไมต้องแยกเป็นสองรายการบนกระดาษแผ่นเดียว ───
   * ประกาศที่มีแต่รายชื่อผู้มีสิทธิ์ ทำให้คนที่ไม่เห็นชื่อตัวเองไม่รู้ว่า
   * "ตกหล่น" หรือ "หมดสิทธิ์" ซึ่งเป็นคนละเรื่องและต้องไปทำคนละอย่าง
   * การพิมพ์ทั้งสองฝั่งบนแผ่นเดียวปิดความกำกวมนั้น
   */
  @Header('content-type', 'text/html; charset=utf-8')
  @Get('exam-eligibility/:sectionId')
  async examEligibility(
    @Param('sectionId', ParseUuidPipe) sectionId: string,
    @Query() _q: EmptyQueryDto,
  ) {
    const { head, students } = await this.svc.roster(sectionId);

    const eligible = students.filter(
      (x: { attendance_state: string }) => x.attendance_state !== 'failed',
    );
    const failed = students.filter(
      (x: { attendance_state: string }) => x.attendance_state === 'failed',
    );

    const table = (list: Record<string, unknown>[], showPct: boolean) =>
      list.length === 0
        ? '<div class="muted" style="margin:6pt 0">— ไม่มีรายชื่อ —</div>'
        : `<table>
      <thead>
        <tr>
          <th style="width:6%">ที่</th>
          <th style="width:18%">รหัสนักศึกษา</th>
          <th>ชื่อ — นามสกุล</th>
          ${showPct ? '<th style="width:16%">เวลาเรียน</th>' : ''}
        </tr>
      </thead>
      <tbody>
        ${list
          .map(
            (x, i) => `<tr>
          <td class="mid">${i + 1}</td>
          <td>${esc(x.student_code)}</td>
          <td>${esc(x.full_name)}</td>
          ${showPct ? `<td class="num">${x.pct_to_date != null ? `${Number(x.pct_to_date).toFixed(1)}%` : '—'}</td>` : ''}
        </tr>`,
          )
          .join('\n')}
      </tbody>
    </table>`;

    const body = `
<div class="school">${esc(head.institution_th)}</div>
<div class="title">ประกาศรายชื่อผู้มีสิทธิ์เข้าสอบปลายภาค</div>
<div class="sub">ภาคเรียนที่ ${esc(head.ordinal)} ปีการศึกษา ${esc(head.year_be)}</div>

<div class="meta">
  <span><strong>รายวิชา</strong> ${esc(head.code)} ${esc(head.course_th)}</span>
  <span><strong>กลุ่ม</strong> ${esc(head.section_no)}</span>
  <span><strong>ผู้สอน</strong> ${esc(head.teacher_th ?? '—')}</span>
</div>

<div style="margin-top:10pt"><strong>ผู้มีสิทธิ์เข้าสอบ (${eligible.length} คน)</strong></div>
${table(eligible, false)}

<div style="margin-top:14pt"><strong>ผู้หมดสิทธิ์เข้าสอบเนื่องจากเวลาเรียนไม่ถึงเกณฑ์ (${failed.length} คน)</strong></div>
${table(failed, true)}

<div class="sign-row">
  <div class="sign"><div class="line">ผู้สอน</div></div>
  <div class="sign"><div class="line">หัวหน้าแผนกวิชา</div></div>
  <div class="sign"><div class="line">ฝ่ายวิชาการ</div></div>
</div>

${printedAt(
  '<br>ผู้ที่ไม่พบชื่อในทั้งสองรายการ แปลว่ายังไม่ได้ลงทะเบียนรายวิชานี้ — คนละเรื่องกับการหมดสิทธิ์',
)}`;

    return sheet(`ผู้มีสิทธิ์สอบ ${head.code} ${head.section_no}`, 'portrait', body);
  }
}

const ATT_TH: Record<string, string> = {
  ok: 'ปกติ',
  warning: 'ใกล้ตกเกณฑ์',
  at_risk: 'เสี่ยงหมดสิทธิ์',
  failed: 'หมดสิทธิ์',
};
