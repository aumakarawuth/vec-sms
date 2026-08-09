import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../widgets.dart';

/// ช่องกรอกข้อความของหน้าจอผู้ให้บริการ
///
/// เขียนแยกจากช่องในหน้าเข้าสู่ระบบของแอปนักศึกษาโดยตั้งใจ — ทั้งสองหน้าจอ
/// ถูกส่งให้คนละกลุ่มผู้ใช้และ build แยกกัน การใช้วิดเจ็ตร่วมกันแปลว่า
/// การแก้หน้าจอฝั่งผู้ให้บริการมีโอกาสไปเปลี่ยนหน้าจอที่ลูกค้าเห็น
class ConsoleField extends StatelessWidget {
  const ConsoleField({
    super.key,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.focusNode,
    this.onSubmitted,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: obscure ? 1 : maxLines,
      onSubmitted: onSubmitted,
      style: Theme.of(context).textTheme.bodyLarge,
      cursorColor: c.ink,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.ink4),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.rule2)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.ink)),
        disabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.rule)),
      ),
    );
  }
}

/// ค่าที่ต้องคัดลอกไปให้คนอื่น เช่น รหัสตั้งค่าและความลับ TOTP
///
/// ─── ทำไมต้องมีวิดเจ็ตเฉพาะ ───
/// ค่าเหล่านี้ออกให้ครั้งเดียวและดูซ้ำไม่ได้ ถ้าผู้ใช้คัดลอกพลาดไปตัวหนึ่ง
/// ต้องออกใหม่ทั้งชุด การแสดงเป็นตัวอักษรกว้าง ๆ พร้อมปุ่มคัดลอกจึงไม่ใช่
/// ความสวยงาม แต่เป็นการกันความผิดพลาดที่แก้ทีหลังไม่ได้
class CopyableValue extends StatelessWidget {
  const CopyableValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GroupHeader(
          label,
          trailing: GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('คัดลอกแล้ว')),
                );
              }
            },
            child: Text('คัดลอก', style: t.bodySmall?.copyWith(color: context.c.sel)),
          ),
        ),
        const SizedBox(height: Gap.sm),
        SelectableText(
          value,
          style: t.titleMedium?.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 1.2,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// แถวของตารางที่กดได้ ใช้กับรายชื่อวิทยาลัยและรายชื่อบัญชี
class ConsoleRow extends StatelessWidget {
  const ConsoleRow({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.tone = Tone.neutral,
    this.badge,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final Tone tone;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.titleMedium),
                  if (subtitle != null)
                    Text(subtitle!, style: t.bodySmall, maxLines: 2),
                  if (badge != null) ...[
                    const SizedBox(height: Gap.xs),
                    StatusDot(badge!, tone: tone),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Gap.md),
              Text(trailing!, style: t.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
