import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../screens/async_view.dart';
import '../../widgets.dart';
import '../platform_session.dart';

/// บันทึกการกระทำของผู้ให้บริการ
///
/// ─── ทำไมบัญชีทุกระดับอ่านได้ รวมถึง support ───
/// บันทึกนี้มีไว้ตอบคำถาม "ใครเข้าไปยุ่งกับลูกค้ารายนี้บ้าง" ซึ่งเป็นคำถาม
/// ที่ฝ่ายสนับสนุนต้องตอบลูกค้าบ่อยที่สุด การปิดไว้ให้เฉพาะผู้ดูแลระดับสูง
/// แปลว่าคนที่รับสายต้องไปถามต่ออีกทอด แล้วคำตอบจะช้าจนไม่มีใครใช้
///
/// ─── สิ่งที่ทำไม่ได้จากหน้าจอนี้ ───
/// แก้และลบ — ไม่ใช่เพราะหน้าจอไม่มีปุ่ม แต่เพราะนโยบายในฐานข้อมูล
/// ไม่มีทางเขียนทับได้เลยแม้ยิงคำสั่งตรง (TEST 189 · PLAT-15)
class PlatformAuditScreen extends StatefulWidget {
  const PlatformAuditScreen({super.key, required this.session});

  final PlatformSession session;

  @override
  State<PlatformAuditScreen> createState() => _PlatformAuditScreenState();
}

class _PlatformAuditScreenState extends State<PlatformAuditScreen> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<Fetched<List<Map<String, dynamic>>>> _load() async {
    final data =
        await widget.session.api.get('/platform/audit?limit=200') as List<dynamic>;
    return Fetched(data.map((e) => Map<String, dynamic>.from(e as Map)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<List<Map<String, dynamic>>>(
      key: _key,
      load: _load,
      builder: (context, rows) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenHeader(
              kicker: 'ผู้ให้บริการ',
              title: 'บันทึกการกระทำ',
              subtitle: 'แก้ไม่ได้และลบไม่ได้ แม้แต่ผู้ดูแลระดับ owner',
            ),
            const SizedBox(height: Gap.xl),
            if (rows.isEmpty)
              Text('ยังไม่มีบันทึก', style: t.bodyMedium),
            for (final r in rows) ...[
              Divider(height: 1, color: context.c.rule),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(_labelOf(r['action']?.toString()),
                              style: t.titleMedium),
                        ),
                        Text(_when(r['occurred_at']), style: t.bodySmall),
                      ],
                    ),
                    Text(
                      [
                        r['username']?.toString() ?? 'ไม่ทราบ',
                        if (r['institution_code'] != null)
                          '${r['institution_code']} ${r['institution_name'] ?? ''}',
                      ].join(' · '),
                      style: t.bodySmall,
                    ),
                    if (_detailOf(r['detail']) != null)
                      Text(_detailOf(r['detail'])!, style: t.labelSmall),
                  ],
                ),
              ),
            ],
            Divider(height: 1, color: context.c.rule),
          ],
        );
      },
    );
  }

  static String _when(dynamic v) {
    final d = Fmt.parseDate(v);
    if (d == null) return '—';
    return '${Fmt.dateShort(d)} ${Fmt.time(d)}';
  }

  /// แปลชื่อการกระทำเป็นภาษาไทย
  ///
  /// ค่าที่เก็บในฐานข้อมูลเป็นอังกฤษเพราะเป็นคีย์ที่ค้นและเทียบได้ ส่วนหน้าจอ
  /// แสดงภาษาไทยตามหลักของทั้งโปรเจกต์ — ถ้าไม่รู้จักให้แสดงค่าดิบไปเลย
  /// ดีกว่าซ่อนรายการที่แปลไม่ได้ ซึ่งจะทำให้บันทึกไม่ครบโดยไม่มีใครรู้
  static String _labelOf(String? action) => switch (action) {
        'provision_institution' => 'เปิดวิทยาลัยใหม่',
        'suspend_institution' => 'ระงับการใช้งาน',
        'resume_institution' => 'คืนสิทธิ์การใช้งาน',
        'assign_plan' => 'ผูกแพ็กเกจ',
        'create_plan' => 'สร้างแพ็กเกจ',
        'update_plan' => 'แก้แพ็กเกจ',
        'create_platform_user' => 'สร้างบัญชีผู้ดูแล',
        'update_platform_user' => 'แก้บัญชีผู้ดูแล',
        'reset_platform_user' => 'ออกรหัสตั้งค่าใหม่',
        'refresh_usage' => 'เก็บภาพนิ่งปริมาณใช้งาน',
        'bootstrap_platform_owner' => 'ติดตั้งระบบและสร้างบัญชีผู้ดูแลคนแรก',
        _ => action ?? '—',
      };

  static String? _detailOf(dynamic detail) {
    if (detail == null) return null;
    final map = detail is String
        ? jsonDecode(detail) as Map<String, dynamic>
        : Map<String, dynamic>.from(detail as Map);
    if (map.isEmpty) return null;
    return map.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
  }
}
