import 'package:flutter/material.dart';
import 'core/fmt.dart';
import 'core/theme.dart';
import 'models.dart';

/// ระดับความสำคัญของสถานะ — ใช้เลือกสีและรูปทรงให้ตรงกันทั้งแอป
enum Tone { neutral, ok, warn, crit, info }

class RingProgress extends StatelessWidget {
  const RingProgress({
    super.key,
    required this.value,
    required this.center,
    this.caption,
    this.color,
    this.size = 126,
    this.centerIcon,
  });
  final double value;
  final String center;
  final String? caption;
  final Color? color;
  final double size;
  final IconData? centerIcon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            value.clamp(0, 1),
            color ?? context.c.sel,
            context.c.rule,
          ),
          child: Center(
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (centerIcon != null)
                  Icon(centerIcon, size: 38, color: color ?? context.c.sel)
                else
                  Text(center,
                      style: Theme.of(context)
                          .textTheme
                          .displayMedium
                          ?.copyWith(fontSize: 29)),
                if (caption != null)
                  Text(caption!, style: Theme.of(context).textTheme.labelSmall),
              ]),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.value, this.color, this.track);
  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = size.width * .085;
    canvas.drawArc(
        rect.deflate(stroke / 2),
        0,
        6.283,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    canvas.drawArc(
      rect.deflate(stroke / 2),
      -1.5708,
      6.283 * value,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color || old.track != track;
}

class MockBadge extends StatelessWidget {
  const MockBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFECEAFE),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text('ข้อมูลตัวอย่าง',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: context.c.sel)),
      );
}

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CustomPaint(size: const Size(9, 9), painter: _DotPainter(tone, color)),
        const SizedBox(width: Gap.sm),
        Text(label, style: TextStyle(fontSize: 13, color: color, height: 1.4)),
      ]),
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

/// หัวข้อกลุ่มในภาษาภาพเดียวกับ dashboard อ้างอิง
class GroupHeader extends StatelessWidget {
  const GroupHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// ตัวเลขหลักของหน้าจอ — น้ำหนักบางขนาดใหญ่
class Figure extends StatelessWidget {
  const Figure(this.value,
      {super.key, this.caption, this.tone = Tone.neutral, this.small = false});
  final String value;
  final String? caption;
  final Tone tone;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color =
        tone == Tone.neutral ? context.c.sel : toneColor(context, tone);
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .11),
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          value,
          style: (small ? t.displayMedium : t.displayLarge)?.copyWith(
            color: color,
            letterSpacing: -1.2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: Gap.xs),
          Text(caption!, style: t.bodySmall),
        ],
      ]),
    );
  }
}

/// แถบแจ้งเตือนแบบการ์ดสีพาสเทล
class Notice extends StatelessWidget {
  const Notice(
      {super.key, required this.title, this.body, this.tone = Tone.neutral});
  final String title;
  final String? body;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, tone);
    final t = Theme.of(context).textTheme;
    final bg = switch (tone) {
      Tone.ok => const Color(0xFFE5F8EF),
      Tone.warn => const Color(0xFFFFF2D6),
      Tone.crit => const Color(0xFFFFE8EB),
      Tone.info => const Color(0xFFEAE8FF),
      Tone.neutral => context.c.sunk,
    };
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .14), shape: BoxShape.circle),
              child: Icon(
                  tone == Tone.crit
                      ? Icons.priority_high_rounded
                      : tone == Tone.ok
                          ? Icons.check_rounded
                          : Icons.info_outline_rounded,
                  color: color,
                  size: 19)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: t.bodyLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                if (body != null) ...[
                  const SizedBox(height: 3),
                  Text(body!, style: t.bodyMedium)
                ],
              ])),
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
    final color =
        tone == Tone.neutral ? context.c.ink : toneColor(context, tone);
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
          color: context.c.sunk, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              Container(
                  height: 8,
                  width: box.maxWidth,
                  decoration: BoxDecoration(
                      color: context.c.rule,
                      borderRadius: BorderRadius.circular(8))),
              Positioned(
                top: 0,
                child: Container(
                  height: 8,
                  width: box.maxWidth * value.clamp(0, 1),
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(8)),
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
      ]),
    );
  }
}

/// แถวข้อมูล ป้ายซ้าย ค่าขวา
class InfoRow extends StatelessWidget {
  const InfoRow(this.label,
      {super.key, this.value, this.trailing, this.tone = Tone.neutral});
  final String label;
  final String? value;
  final Widget? trailing;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.md),
      decoration: BoxDecoration(
          color: context.c.sunk, borderRadius: BorderRadius.circular(16)),
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
                color: tone == Tone.neutral
                    ? context.c.ink
                    : toneColor(context, tone),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// ปุ่มหลักสีม่วงตามธีม dashboard
class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label,
      {super.key, this.onPressed, this.ghost = false});
  final String label;
  final VoidCallback? onPressed;
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color:
            ghost ? context.c.sunk : (enabled ? context.c.sel : context.c.ink4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
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
                  fontWeight: FontWeight.w700,
                  color: ghost ? context.c.sel : Colors.white,
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
      color: const Color(0xFFFFF2D6),
      child: Text(
        'ต่อเซิร์ฟเวอร์ไม่ได้ กำลังแสดงข้อมูลที่บันทึกไว้$when',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

/// หัวหน้าจอแบบ dashboard มี accent สีม่วงและพื้นขาว
class ScreenHeader extends StatelessWidget {
  const ScreenHeader(
      {super.key, this.kicker, required this.title, this.subtitle});
  final String? kicker, subtitle;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
          color: context.c.sunk, borderRadius: BorderRadius.circular(20)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 5,
            height: 48,
            decoration: BoxDecoration(
                color: context.c.sel, borderRadius: BorderRadius.circular(5))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (kicker != null) ...[
            Text(kicker!,
                style: t.bodySmall?.copyWith(
                    color: context.c.sel, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
          ],
          Text(title, style: t.titleLarge?.copyWith(letterSpacing: -0.4)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: t.bodySmall),
          ],
        ])),
      ]),
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
