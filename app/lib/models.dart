import 'core/fmt.dart';

/// สถานะเวลาเรียนที่ฐานข้อมูลคำนวณมาให้
///
/// ตัดสินจาก pct_projected ไม่ใช่ pct_final เพราะกลางภาค pct_final จะต่ำเสมอ
/// โดยธรรมชาติ ถ้าใช้ตัดสินจะขึ้นว่าหมดสิทธิ์สอบให้ทุกคนตั้งแต่สัปดาห์แรก
enum AttendanceState { ok, warning, discretion, failed }

AttendanceState parseAttendanceState(String? v) => switch (v) {
      'failed' => AttendanceState.failed,
      'discretion' => AttendanceState.discretion,
      'warning' => AttendanceState.warning,
      _ => AttendanceState.ok,
    };

class CourseAttendance {
  CourseAttendance({
    required this.code,
    required this.name,
    required this.pctToDate,
    required this.pctProjected,
    required this.absencesLeft,
    required this.state,
    required this.minPct,
  });

  factory CourseAttendance.fromJson(Map<String, dynamic> j) => CourseAttendance(
        code: j['code']?.toString() ?? '',
        name: j['name_th']?.toString() ?? '',
        pctToDate: Fmt.toNum(j['pct_to_date'])?.toDouble(),
        pctProjected: Fmt.toNum(j['pct_projected'])?.toDouble() ?? 0,
        absencesLeft: Fmt.toNum(j['absences_left'])?.toInt() ?? 0,
        state: parseAttendanceState(j['attendance_state']?.toString()),
        minPct: Fmt.toNum(j['min_pct'])?.toDouble() ?? 80,
      );

  final String code, name;
  final double? pctToDate;
  final double pctProjected;
  final int absencesLeft;
  final AttendanceState state;
  final double minPct;
}

class Period {
  Period({
    required this.meetingId,
    required this.courseCode,
    required this.courseName,
    required this.periodFrom,
    required this.periodTo,
    required this.room,
    required this.teacherName,
  });

  factory Period.fromJson(Map<String, dynamic> j) => Period(
        meetingId: j['meeting_id']?.toString() ?? '',
        courseCode: j['course_code']?.toString() ?? '',
        courseName: j['course_name']?.toString() ?? '',
        periodFrom: Fmt.toNum(j['period_from'])?.toInt() ?? 0,
        periodTo: Fmt.toNum(j['period_to'])?.toInt() ?? 0,
        room: j['room']?.toString(),
        teacherName: j['teacher_name']?.toString(),
      );

  final String meetingId, courseCode, courseName;
  final int periodFrom, periodTo;
  final String? room, teacherName;

  String get periodLabel => periodFrom == periodTo
      ? 'คาบ $periodFrom'
      : 'คาบ $periodFrom–$periodTo';
}

class GraduationRule {
  GraduationRule({
    required this.kind,
    required this.name,
    required this.required,
    required this.achieved,
    required this.satisfied,
    required this.blocking,
  });

  factory GraduationRule.fromJson(Map<String, dynamic> j) => GraduationRule(
        kind: j['kind']?.toString() ?? '',
        name: j['name_th']?.toString() ?? '',
        required: Fmt.toNum(j['required'])?.toDouble() ?? 0,
        achieved: Fmt.toNum(j['achieved'])?.toDouble() ?? 0,
        satisfied: j['satisfied'] == true,
        blocking: j['is_blocking'] == true,
      );

  final String kind, name;
  final double required, achieved;
  final bool satisfied, blocking;

  /// กฎสามข้อนี้เป็น "จำนวนที่ยังค้าง" ยิ่งน้อยยิ่งดี ตรงข้ามกับข้ออื่น
  bool get isCountdown => const {
        'cocurricular_all_terms',
        'no_pending_grade',
        'required_courses',
      }.contains(kind);

  double get progress {
    if (satisfied) return 1;
    if (isCountdown) return 0;
    if (required <= 0) return 1;
    return (achieved / required).clamp(0, 1).toDouble();
  }
}

class Balance {
  Balance({
    required this.billed,
    required this.paid,
    required this.outstanding,
    required this.nextDueOn,
    required this.daysOverdue,
  });

  factory Balance.fromJson(Map<String, dynamic> j) => Balance(
        billed: Fmt.toNum(j['billed'])?.toDouble() ?? 0,
        paid: Fmt.toNum(j['paid'])?.toDouble() ?? 0,
        outstanding: Fmt.toNum(j['outstanding'])?.toDouble() ?? 0,
        nextDueOn: Fmt.parseDate(j['next_due_on']),
        daysOverdue: Fmt.toNum(j['days_overdue'])?.toInt(),
      );

  final double billed, paid, outstanding;
  final DateTime? nextDueOn;
  final int? daysOverdue;

  bool get isOverdue => (daysOverdue ?? 0) > 0;
}

class Installment {
  Installment({
    required this.seq,
    required this.dueOn,
    required this.amount,
    required this.paidAmount,
    required this.status,
  });

  factory Installment.fromJson(Map<String, dynamic> j) => Installment(
        seq: Fmt.toNum(j['seq'])?.toInt() ?? 0,
        dueOn: Fmt.parseDate(j['due_on']),
        amount: Fmt.toNum(j['amount'])?.toDouble() ?? 0,
        paidAmount: Fmt.toNum(j['paid_amount'])?.toDouble() ?? 0,
        status: j['status']?.toString() ?? '',
      );

  final int seq;
  final DateTime? dueOn;
  final double amount, paidAmount;
  final String status;

  double get remaining => amount - paidAmount;
  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue';

  String get statusLabel => switch (status) {
        'paid' => 'จ่ายแล้ว',
        'partially_paid' => 'จ่ายบางส่วน',
        'overdue' => 'เกินกำหนด',
        'waived' => 'ยกเว้น',
        _ => 'ยังไม่จ่าย',
      };
}

class Invoice {
  Invoice({
    required this.id,
    required this.invoiceNo,
    required this.dueOn,
    required this.total,
    required this.paidTotal,
    required this.outstanding,
    required this.status,
    required this.ref1,
    required this.ref2,
    required this.installments,
  });

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id']?.toString() ?? '',
        invoiceNo: j['invoice_no']?.toString() ?? '',
        dueOn: Fmt.parseDate(j['due_on']),
        total: Fmt.toNum(j['total'])?.toDouble() ?? 0,
        paidTotal: Fmt.toNum(j['paid_total'])?.toDouble() ?? 0,
        outstanding: Fmt.toNum(j['outstanding'])?.toDouble() ?? 0,
        status: j['status']?.toString() ?? '',
        ref1: j['ref1']?.toString(),
        ref2: j['ref2']?.toString(),
        installments: ((j['installments'] as List?) ?? const [])
            .map((e) => Installment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id, invoiceNo, status;
  final DateTime? dueOn;
  final double total, paidTotal, outstanding;
  final String? ref1, ref2;
  final List<Installment> installments;

  /// งวดถัดไปที่ยังต้องจ่าย — ตัวเลขที่แสดงใหญ่ที่สุดในหน้าการเงิน
  Installment? get nextDue {
    for (final i in installments) {
      if (!i.isPaid && i.remaining > 0) return i;
    }
    return null;
  }
}
