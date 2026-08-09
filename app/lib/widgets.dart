import 'package:flutter/material.dart';
import 'core/fmt.dart';
import 'core/theme.dart';
import 'models.dart';

/// ระดับความสำคัญของสถานะ — ใช้เลือกสีและรูปทรงให้ตรงกันทั้งแอป
enum Tone { neutral, ok, warn, crit, info }

Color toneColor(BuildContext ctx, Tone t) => switch (t) {
      Tone.ok => ctx.c.ok,
      Tone.warn => ctx.c.warn,
      Tone.crit => ctx.c.crit,
      Tone.info => ctx.c.sel,
      Tone.neutral => ctx.c.ink4,
    };

/// จุดสัญลักษณ์ + ข้อความ ไม่มีกรอบไม่มีพื้นหลัง
///
/// รูปทรงต่างกันตามระดับ วงกลม สามเหลี่ยม ข้าวหลามตัด
/// เพื่อให้แยกออกได้แม้พิมพ์ขาวดำหรือผู้ใช้ตาบอดสี
class StatusDot extends StatelessWidget {
  const StatusDot(this.label, {super.key, this.tone = Tone.neutral});
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(size: const Size(9, 9), painter: _DotPainter(tone, color)),
        const SizedBox(width: Gap.sm),
        Text(label, style: TextStyle(fontSize: 13, color: color, height: 1.4)),
      ],
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.tone, this.color);
  final Tone tone;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width, h = size.height;
    switch (tone) {
      case Tone.warn:
        canvas.drawPath(
          Path()
            ..moveTo(w / 2, 0)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close(),
          p,
        );
      case Tone.crit:
        canvas.drawPath(
          Path()
            ..moveTo(w / 2, 0)
            ..lineTo(w, h / 2)
            ..lineTo(w / 2, h)
            ..lineTo(0, h / 2)
            ..close(),
          p,
        );
      default:
        canvas.drawCircle(Offset(w / 2, h / 2), w / 2, p);
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) => old.tone != tone || old.color != color;
}

/// หัวข้อกลุ่ม — เส้นทึบด้านล่างหนึ่งเส้น ไม่ใช่การ์ดมีกรอบ
class GroupHeader extends StatelessWidget {
  const GroupHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.c.ink, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.labelSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// ตัวเลขหลักของหน้าจอ — น้ำหนักบางขนาดใหญ่
class Figure extends StatelessWidget {
  const Figure(this.value, {super.key, this.caption, this.tone = Tone.neutral, this.small = false});
  final String value;
  final String? caption;
  final Tone tone;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: (small ? t.displayMedium : t.displayLarge)?.copyWith(
            color: tone == Tone.neutral ? context.c.ink : toneColor(context, tone),
            letterSpacing: -1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: Gap.xs),
          Text(caption!, style: t.bodySmall),
        ],
      ],
    );
  }
}

/// แถบแจ้งเตือน — เส้นซ้ายหนึ่งเส้น ไม่มีกล่องมีขอบ
class Notice extends StatelessWidget {
  const Notice({super.key, required this.title, this.body, this.tone = Tone.neutral});
  final String title;
  final String? body;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.only(left: Gap.md),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
          if (body != null) ...[
            const SizedBox(height: 2),
            Text(body!, style: t.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// มาตรวัดเวลาเรียน — เส้นบางสามพิกเซลบนราง 1 พิกเซล ไม่ใช่แถบหนา
class Meter extends StatelessWidget {
  const Meter({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
    this.note,
  });
  final String label;
  final double value; // 0..1
  final Tone tone;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = tone == Tone.neutral ? context.c.ink : toneColor(context, tone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(label,
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
            ),
            Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
        LayoutBuilder(
          builder: (_, box) => Stack(
            clipBehavior: Clip.none,
            children: [
              Container(height: 1, width: box.maxWidth, color: context.c.rule),
              Positioned(
                top: -1,
                child: Container(
                  height: 3,
                  width: box.maxWidth * value.clamp(0, 1),
                  color: color,
                ),
              ),
            ],
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: Gap.sm),
          Text(note!,
              style: t.bodySmall?.copyWith(
                  color: tone == Tone.crit ? context.c.crit : context.c.ink3)),
        ],
      ],
    );
  }
}

/// แถวข้อมูล ป้ายซ้าย ค่าขวา
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, {super.key, this.value, this.trailing, this.tone = Tone.neutral});
  final String label;
  final String? value;
  final Widget? trailing;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Text(label, style: t.bodyMedium)),
          const SizedBox(width: Gap.md),
          if (trailing != null)
            trailing!
          else
            Text(
              value ?? '—',
              style: t.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
                color: tone == Tone.neutral ? context.c.ink : toneColor(context, tone),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// ปุ่มหลัก — ดำทึบ ไม่มีมุมโค้งมาก ไม่มีเงา
class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, this.onPressed, this.ghost = false});
  final String label;
  final VoidCallback? onPressed;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: ghost ? Colors.transparent : (enabled ? context.c.ink : context.c.ink4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: ghost ? BorderSide(color: context.c.rule2) : BorderSide.none,
        ),
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ghost ? context.c.ink : context.c.bg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// แจ้งว่ากำลังแสดงข้อมูลที่เก็บไว้ เพราะต่อเซิร์ฟเวอร์ไม่ได้
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.cachedAt});
  final DateTime? cachedAt;

  @override
  Widget build(BuildContext context) {
    final when = cachedAt == null ? '' : ' · ข้อมูลเมื่อ ${Fmt.ago(cachedAt!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
      color: context.c.sunk,
      child: Text(
        'ต่อเซิร์ฟเวอร์ไม่ได้ กำลังแสดงข้อมูลที่บันทึกไว้$when',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// หัวหน้าจอ — ป้ายเทาเล็กกับหัวเรื่องดำ ไม่ใช้แถบสีทึบ
///
/// แถบสีกินพื้นที่บนสุดของจอโดยไม่ให้ข้อมูล และทำให้ทุกหน้าจอดูเหมือนกันหมด
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, this.kicker, required this.title, this.subtitle});
  final String? kicker, subtitle;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kicker != null) ...[
          Text(kicker!, style: t.bodySmall),
          const SizedBox(height: 2),
        ],
        Text(title, style: t.titleLarge?.copyWith(letterSpacing: -0.4)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: t.bodySmall),
        ],
      ],
    );
  }
}

/// แปลงสถานะเวลาเรียนเป็นระดับสี
Tone toneOfAttendance(AttendanceState s) => switch (s) {
      AttendanceState.failed => Tone.crit,
      AttendanceState.discretion => Tone.crit,
      AttendanceState.warning => Tone.warn,
      AttendanceState.ok => Tone.neutral,
    };
