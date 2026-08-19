# VEC SMS — Database Schema, Flowchart, DFD และ Sitemap

เอกสารนี้อ้างอิงจาก migrations, NestJS controllers และ React routes ณ วันที่ 14 สิงหาคม 2569

## 1. ภาพรวมสถาปัตยกรรม

```mermaid
flowchart LR
    U1[นักศึกษา / ผู้ปกครอง] --> APP[Flutter App]
    U2[ครู / เจ้าหน้าที่] --> WEB[React Staff Web]
    U3[ผู้ดูแลแพลตฟอร์ม] --> PADM[Flutter Platform Console]
    APP --> API[NestJS REST API]
    WEB --> API
    PADM --> API
    API --> AUTH[Authentication / RBAC / MFA]
    API --> DB[(PostgreSQL)]
    API --> DOC[Document & Report Renderer]
    API --> JOB[Scheduled Jobs]
    DOC --> PDF[เอกสารพิมพ์ / PDF]
    API --> EXT[ธนาคาร / หน่วยงานรัฐ / เครื่องสแกน]
```

## 2. Database Schema

ฐานข้อมูลเป็น PostgreSQL แบบ Multi-tenant ตารางธุรกิจส่วนใหญ่ผูก `institution_id` และบังคับสิทธิ์ด้วย Row-Level Security (RLS)

### 2.1 Core ER Diagram

```mermaid
erDiagram
    INSTITUTION ||--o{ ACADEMIC_YEAR : has
    ACADEMIC_YEAR ||--o{ TERM : contains
    INSTITUTION ||--o{ PERSON : owns
    PERSON ||--o| STUDENT : becomes
    PERSON ||--o| STAFF : becomes
    STUDENT ||--o{ STUDENT_STATUS_HISTORY : changes
    STUDENT ||--o{ STUDENT_GUARDIAN : has
    PERSON ||--o{ STUDENT_GUARDIAN : guardian
    STAFF ||--o{ STAFF_ROLE : assigned
    STAFF ||--o{ STAFF_ASSIGNMENT : works_in
    DEPARTMENT ||--o{ STAFF_ASSIGNMENT : contains
    DEPARTMENT ||--o{ DEPARTMENT : parent

    PROGRAM_TYPE ||--o{ PROGRAM : groups
    PROGRAM ||--o{ PROGRAM_TRACK : contains
    PROGRAM_TRACK ||--o{ CURRICULUM : defines
    CURRICULUM ||--o{ CURRICULUM_VERSION : versions
    CURRICULUM_VERSION ||--o{ CURRICULUM_CATEGORY : groups
    CURRICULUM_VERSION ||--o{ CURRICULUM_COURSE : contains
    COURSE ||--o{ CURRICULUM_COURSE : mapped
    STUDENT ||--o{ STUDENT_CURRICULUM : follows
    CURRICULUM_VERSION ||--o{ STUDENT_CURRICULUM : assigned

    TERM ||--o{ CLASS_SECTION : opens
    COURSE ||--o{ CLASS_SECTION : offered_as
    STAFF ||--o{ CLASS_SECTION : teaches
    ROOM ||--o{ SECTION_TIMESLOT : scheduled_in
    CLASS_SECTION ||--o{ SECTION_TIMESLOT : scheduled
    STUDENT ||--o{ ENROLLMENT : registers
    CLASS_SECTION ||--o{ ENROLLMENT : contains
    CLASS_SECTION ||--o{ CLASS_MEETING : meets
    CLASS_MEETING ||--o{ ATTENDANCE_RECORD : records
    ENROLLMENT ||--o{ ATTENDANCE_RECORD : receives

    CLASS_SECTION ||--o{ GRADEBOOK_ITEM : assesses
    GRADEBOOK_ITEM ||--o{ GRADEBOOK_SCORE : has
    ENROLLMENT ||--o{ GRADEBOOK_SCORE : earns
    CLASS_SECTION ||--o{ GRADE_SUBMISSION : submits
    ENROLLMENT ||--o| ENROLLMENT_RESULT : results
    ENROLLMENT_RESULT ||--o{ GRADE_CHANGE_REQUEST : changes
    STUDENT ||--o{ TERM_SUMMARY : summarizes

    STUDENT ||--o{ INVOICE : billed
    INVOICE ||--o{ INVOICE_LINE : contains
    STUDENT ||--o{ PAYMENT : pays
    PAYMENT ||--o{ PAYMENT_ALLOCATION : allocates
    INVOICE_LINE ||--o{ PAYMENT_ALLOCATION : settles

    STUDENT ||--o{ BEHAVIOR_RECORD : receives
    STUDENT ||--o{ SCREENING_RESULT : screened
    STUDENT ||--o{ STUDENT_RISK_SCORE : scored
    STUDENT ||--o{ INTERVENTION_CASE : followed
    INTERVENTION_CASE ||--o{ INTERVENTION_ACTION : contains

    STUDENT ||--o{ ISSUED_DOCUMENT : owns
    STUDENT ||--o| STUDENT_GRADUATION : graduates
    GRADUATION_APPROVAL ||--o{ STUDENT_GRADUATION : approves
```

### 2.2 กลุ่มตารางทั้งหมด

| Domain | ตารางหลัก |
|---|---|
| Tenant/Academic calendar | `institution`, `academic_year`, `term`, `academic_holiday` |
| Person/Student | `person`, `student`, `student_status_history`, `student_guardian`, `student_parent`, `student_advisor`, `person_address`, `person_sensitive`, `student_prior_education` |
| Staff/HR | `staff`, `staff_role`, `department`, `staff_assignment`, `staff_record`, `staff_child`, `staff_leave`, `staff_attendance` |
| Curriculum | `program_type`, `program`, `program_track`, `curriculum`, `curriculum_version`, `curriculum_category`, `course`, `curriculum_course`, `course_prerequisite`, `competency` |
| Registration/Timetable | `class_section`, `enrollment`, `room`, `section_timeslot`, `teacher_availability`, `registration_policy`, `registration_hold`, `registration_override`, `student_class_placement` |
| Attendance | `attendance_policy`, `attendance_status_weight`, `class_meeting`, `attendance_record`, `attendance_checkin`, `student_leave`, `student_leave_applied` |
| Gradebook | `grade_scheme`, `grade_symbol`, `grade_cutoff`, `gradebook_item`, `gradebook_score`, `grade_submission`, `grade_submission_event`, `enrollment_result`, `grade_change_request`, `grade_ledger`, `term_summary` |
| Graduation/Practicum | `professional_standard_assessment`, `cocurricular_result`, `practicum_log`, `graduation_rule`, `student_graduation_status`, `student_graduation`, `graduation_approval` |
| Finance | `ledger_account`, `ledger_transaction`, `ledger_entry`, `fee_item`, `fee_schedule`, `invoice`, `invoice_line`, `installment`, `payment`, `payment_allocation`, `bank_transaction`, `late_fee_policy` |
| Behavior/Risk | `behavior_rule`, `behavior_record`, `behavior_policy`, `screening_result`, `home_visit`, `risk_factor`, `student_risk_signal`, `student_risk_score`, `intervention_case`, `intervention_action` |
| Admissions | `admission_round`, `admission_quota`, `application`, `application_choice`, `application_document` |
| Documents | `document_series`, `issued_document`, `institution_document_text` |
| Import/Export | `import_batch`, `import_row`, `prior_academic_record` และ Government Export views/services |
| Authentication/Audit | `user_credential`, `auth_identity`, `auth_session`, `login_attempt`, `mfa_credential`, `password_reset`, `access_log`, `request_rate` |
| Platform/SaaS | `plan`, `institution_subscription`, `usage_snapshot`, `platform_user`, `platform_session`, `platform_action_log`, `provisioning_log` |

### 2.3 Registration–Grade–Finance Data Chain

```mermaid
flowchart LR
    ST[(student)] --> SC[(student_curriculum)]
    SC --> EN[(enrollment)]
    CS[(class_section)] --> EN
    EN --> AR[(attendance_record)]
    EN --> GS[(gradebook_score)]
    GS --> ER[(enrollment_result)]
    ER --> TS[(term_summary)]
    EN --> INV[(invoice)]
    INV --> PAY[(payment_allocation)]
    TS --> GR[(student_graduation)]
    GR --> DOC[(issued_document)]
```

## 3. System Flowchart

```mermaid
flowchart TD
    A([เริ่มต้น]) --> B[เข้าสู่ระบบ]
    B --> C{ยืนยันตัวตนสำเร็จ?}
    C -- ไม่สำเร็จ --> D[บันทึก Login Attempt / จำกัดอัตรา] --> B
    C -- สำเร็จ --> E{ต้องเปลี่ยนรหัสหรือ MFA?}
    E -- ใช่ --> F[เปลี่ยนรหัสผ่าน / ยืนยัน MFA] --> G
    E -- ไม่ใช่ --> G[โหลดบทบาทและ Institution Context]
    G --> H{เลือกโมดูล}
    H --> I[รับสมัครและขึ้นทะเบียน]
    H --> J[หลักสูตร / ตาราง / ลงทะเบียน]
    H --> K[เช็กชื่อ / คะแนน / อนุมัติเกรด]
    H --> L[การเงิน / รับชำระ]
    H --> M[พฤติกรรม / ความเสี่ยง / การลา]
    H --> N[ตรวจจบ / ออกเอกสาร / ส่งออกภาครัฐ]
    H --> O[บุคลากร / สิทธิ์ / Audit]
    I & J & K & L & M & N & O --> P[API ตรวจ Role + Validation]
    P --> Q{ผ่านสิทธิ์และกฎธุรกิจ?}
    Q -- ไม่ผ่าน --> R[คืน 400 / 403 / 422 พร้อมข้อความภาษาไทย]
    Q -- ผ่าน --> S[Transaction + PostgreSQL RLS]
    S --> T[บันทึก Ledger / Audit / Event ตามประเภทงาน]
    T --> U[ตอบผลและรีเฟรชหน้าจอ]
    U --> H
```

## 4. DFD Level 0 — Context Diagram

```mermaid
flowchart LR
    STUDENT[นักศึกษา] -->|ข้อมูลส่วนตัว ลงทะเบียน เช็กอิน คำร้อง| SYS((0 ระบบบริหารวิทยาลัย VEC SMS))
    SYS -->|ตารางเรียน ผลการเรียน ยอดค้าง เอกสาร| STUDENT
    GUARDIAN[ผู้ปกครอง] -->|รับทราบการลา / ข้อมูลติดต่อ| SYS
    SYS -->|แจ้งขาดเรียน หนังสือเชิญ สถานะนักศึกษา| GUARDIAN
    STAFF[ครูและเจ้าหน้าที่] -->|ระเบียน เช็กชื่อ คะแนน การเงิน งานดูแล| SYS
    SYS -->|รายงาน รายชื่อ งานรออนุมัติ| STAFF
    ADMIN[ผู้บริหาร / ผู้ดูแล] -->|นโยบาย สิทธิ์ การอนุมัติ| SYS
    SYS -->|Dashboard Audit และสถิติ| ADMIN
    GOV[หน่วยงานภาครัฐ] <-->|ไฟล์ REGIS / PVIS / PVRS / ข้อมูลรายงาน| SYS
    BANK[ธนาคาร / Payment Source] <-->|รายการเดินบัญชีและการกระทบยอด| SYS
    DEVICE[เครื่องสแกน / อุปกรณ์] -->|ข้อมูลเวลาและ Check-in| SYS
```

## 5. DFD Level 1 — กระบวนการหลัก

```mermaid
flowchart TB
    E1[นักศึกษา/ผู้ปกครอง] --> P1((1.0 ผู้ใช้และระเบียน))
    E2[ครู/เจ้าหน้าที่] --> P1
    P1 <--> D1[(D1 บุคคล นักศึกษา บุคลากร Auth)]

    E2 --> P2((2.0 หลักสูตร ตาราง และลงทะเบียน))
    P2 <--> D2[(D2 หลักสูตร รายวิชา กลุ่มเรียน ห้อง)]
    P2 <--> D3[(D3 Enrollment และ Registration Rules)]
    P2 --> E1

    E1 --> P3((3.0 เวลาเรียน คะแนน และผลการเรียน))
    E2 --> P3
    P3 <--> D4[(D4 Attendance / Check-in)]
    P3 <--> D5[(D5 Gradebook / Results / Ledger)]
    P3 --> E1

    E1 --> P4((4.0 การเงิน))
    E2 --> P4
    P4 <--> D6[(D6 Invoice Payment Ledger)]
    P4 <--> E4[ธนาคาร]

    E1 --> P5((5.0 พฤติกรรม ความเสี่ยง และการลา))
    E2 --> P5
    P5 <--> D7[(D7 Behavior Risk Leave)]
    P5 --> E3[ผู้ปกครอง]

    E2 --> P6((6.0 จบการศึกษา เอกสาร และรายงาน))
    P6 <--> D5
    P6 <--> D8[(D8 Graduation / Issued Documents)]
    P6 --> E1
    P6 <--> E5[หน่วยงานภาครัฐ]

    E6[Platform Admin] --> P7((7.0 Platform Subscription และ Audit))
    P7 <--> D9[(D9 Institution Plan Usage Audit)]
```

## 6. DFD Level 2 — งานลงทะเบียนถึงประกาศผล

```mermaid
flowchart TB
    ST[นักศึกษา/เจ้าหน้าที่ทะเบียน] --> P21((2.1 เลือกภาคเรียนและรายวิชา))
    P21 <-->|แผนการเรียน รายวิชาที่เปิด| D21[(Curriculum / Class Section)]
    P21 --> P22((2.2 ตรวจเงื่อนไขลงทะเบียน))
    P22 <-->|วิชาบังคับก่อน หน่วยกิต โฮลด์ ที่นั่ง ตารางชน| D22[(Registration Policy / Hold / Timeslot)]
    P22 -- ไม่ผ่าน --> X1[แจ้งเหตุผลหรือขอ Override]
    X1 --> P23((2.3 อนุมัติ Override))
    P23 --> D23[(Registration Override)]
    P22 -- ผ่าน --> P24((2.4 บันทึก Enrollment))
    P23 --> P24
    P24 --> D24[(Enrollment)]
    P24 --> P25((2.5 สร้างภาระค่าธรรมเนียม))
    P25 --> D25[(Invoice / Ledger)]
    P24 --> P26((2.6 เปิดเช็กชื่อและสมุดคะแนน))
    TEACHER[ครูผู้สอน] --> P26
    P26 --> D26[(Meeting / Attendance / Gradebook Score)]
    D26 --> P27((2.7 คำนวณและตรวจผล))
    P27 --> P28((2.8 ส่งและอนุมัติเกรด))
    APPROVER[วิชาการ/ผู้บริหาร] --> P28
    P28 --> D27[(Grade Submission Event)]
    P28 --> P29((2.9 ตรึงผลและสรุปภาคเรียน))
    P29 --> D28[(Enrollment Result / Grade Ledger / Term Summary)]
    D28 --> OUT[ผลการเรียน Transcript และตรวจจบ]
```

## 7. Sitemap — Staff Web

```mermaid
flowchart TD
    ROOT[Staff Web] --> LOGIN[เข้าสู่ระบบ / MFA / เปลี่ยนรหัสผ่าน]
    ROOT --> HUB[เมนูศูนย์งาน]
    HUB --> REG[ศูนย์งานทะเบียน]
    HUB --> HRH[ศูนย์งานบุคลากร]
    HUB --> TTH[ศูนย์งานตารางเรียน]
    HUB --> STH[ศูนย์การตั้งค่า]
    HUB --> BEH[ศูนย์งานพฤติกรรม]

    ROOT --> REGG[งานทะเบียน]
    REGG --> STUDENTS[ระเบียนนักศึกษา /students]
    STUDENTS --> PROFILE[ข้อมูลทั่วไป ที่อยู่ ผู้ปกครอง สุขภาพ การศึกษาเดิม ที่ปรึกษา สถานะ]
    REGG --> ENROLL[ลงทะเบียนเรียน /registration]
    REGG --> DOCS[ออกเอกสาร /documents]
    REGG --> GRAD[สำเร็จการศึกษา /graduation]
    REGG --> ADMIT[งานรับสมัคร /admissions]
    REGG --> IMPORT[นำเข้าข้อมูล /import]
    REGG --> GOV[ส่งออกข้อมูลรัฐ /government-exports]

    ROOT --> FIN[การเงิน /finance]
    ROOT --> ACADEMIC[งานวัดผล]
    ACADEMIC --> CURR[โครงสร้างหลักสูตร /curriculum]
    ACADEMIC --> TT[ตารางสอน /timetable]
    ACADEMIC --> AY[งานวิชาการรายปี /academic-year]
    ACADEMIC --> DUAL[ทวิภาคี /dual]
    ACADEMIC --> GB[สมุดคะแนน /gradebook]
    ACADEMIC --> ATT[เช็กชื่อรายคาบ /attendance]
    ACADEMIC --> CHANGE[คำร้องแก้เกรด /change-requests]

    ROOT --> CARE[ดูแลนักศึกษา]
    CARE --> RISK[เฝ้าระวัง /risk]
    CARE --> BREC[พฤติกรรม /behavior]
    CARE --> LETTER[หนังสือผู้ปกครอง /letters]
    CARE --> LEAVE[การลานักศึกษา /leaves]

    ROOT --> HR[บุคลากรและการลา /hr]
    ROOT --> SYSTEM[ระบบ]
    SYSTEM --> JOBS[งานตามกำหนดเวลา /jobs]
```

## 8. ขอบเขตระบบตาม Actor

| Actor | งานหลัก |
|---|---|
| นักศึกษา | ตารางเรียน เช็กอิน เวลาเรียน ผลการเรียน การเงิน ความพร้อมจบ และโปรไฟล์ |
| ผู้ปกครอง | รับทราบการลา หนังสือแจ้งเตือน และข้อมูลนักศึกษาในความดูแล |
| ครู | กลุ่มเรียน เช็กชื่อ สมุดคะแนน ส่งเกรด ที่ปรึกษา และติดตามนักศึกษา |
| งานทะเบียน/วิชาการ | ระเบียน ลงทะเบียน หลักสูตร ตาราง อนุมัติเกรด เอกสาร และตรวจจบ |
| การเงิน | ใบแจ้งหนี้ รับชำระ จัดสรรยอด กระทบยอด และรายงานลูกหนี้ |
| กิจการนักศึกษา | พฤติกรรม การลา คัดกรอง ความเสี่ยง เยี่ยมบ้าน และหนังสือผู้ปกครอง |
| ผู้บริหาร | อนุมัติ ดูภาพรวม Audit และรายงาน |
| Platform Admin | Institution, Plan, Subscription, Usage และ Provisioning |

## 9. หมายเหตุสำหรับพัฒนาต่อ

- ER Diagram แสดงความสัมพันธ์แกนหลักเพื่อให้อ่านได้ ไม่ได้วาดทุกตารางเชื่อมกันในภาพเดียว
- ตารางเอกสารใช้ payload ที่ตรึง ณ เวลาออกเอกสาร การพิมพ์ซ้ำต้องอ่านจาก `issued_document`
- ผลการเรียนที่ประกาศแล้วมี `grade_ledger` และ event สำหรับ Audit ห้ามแก้ทับโดยตรง
- สิทธิ์จริงควบคุมที่ API Roles และ PostgreSQL RLS ไม่ใช่การซ่อนเมนูหน้าเว็บ
- โมดูล Mockup ที่ยังไม่มี schema เฉพาะ ได้แก่ O-NET, ชุมนุม/ชมรม, RFID และเครื่องมือรูปภาพบางส่วน
