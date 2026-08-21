import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models.dart';
import '../widgets.dart';
import 'async_view.dart';

class GraduationScreen extends StatelessWidget {
  const GraduationScreen({super.key, required this.session});
  final Session session;

  Future<Fetched<List<GraduationRule>>> _load() async {
    final r = await session.api
        .getCached('/students/${session.studentId}/graduation');
    return Fetched(
      (r.data as List)
          .map((e) => GraduationRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      fromCache: r.fromCache,
      cachedAt: r.cachedAt,
    );
  }

  @override
  Widget build(BuildContext context) => AsyncView<List<GraduationRule>>(
        load: _load,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        builder: (context, rules) => _GraduationBody(rules: rules),
      );
}

class _GraduationBody extends StatelessWidget {
  const _GraduationBody({required this.rules});
  final List<GraduationRule> rules;

  @override
  Widget build(BuildContext context) {
    final mock = rules.isEmpty;
    final passed = mock ? 4 : rules.where((r) => r.satisfied).length;
    final total = mock ? 5 : rules.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Center(
          child: Text('ความพร้อมการจบ',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
      const SizedBox(height: 3),
      const Center(
          child: Text('เส้นทางสู่การจบ',
              style: TextStyle(fontSize: 11, color: Color(0xFF77758A)))),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFE5F8EF), Color(0xFFF0FBF6)]),
            borderRadius: BorderRadius.circular(21)),
        child: Row(children: [
          RingProgress(
              value: total == 0 ? 0 : passed / total,
              center: '',
              caption: '',
              size: 118,
              color: context.c.ok,
              centerIcon: Icons.school_rounded),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('ความพร้อมโดยรวม',
                    style: TextStyle(
                        color: Color(0xFF167550), fontWeight: FontWeight.w700)),
                RichText(
                    text: TextSpan(
                        style: const TextStyle(color: Color(0xFF126B4B)),
                        children: [
                      TextSpan(
                          text: '$passed',
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w800)),
                      const TextSpan(
                          text: ' จาก ', style: TextStyle(fontSize: 16)),
                      TextSpan(
                          text: '$total',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w700))
                    ])),
                Text('ผ่านแล้ว $passed จาก $total',
                    style: const TextStyle(
                        color: Color(0xFF167550), fontWeight: FontWeight.w700)),
                const Text('ใกล้สำเร็จการศึกษา!',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6D8279)))
              ]))
        ]),
      ),
      const SizedBox(height: 14),
      if (mock) ...const [
        _MockRule(Icons.check_circle, 'หน่วยกิตครบตามหลักสูตร',
            'ครบ 104 / 104 หน่วยกิต', true),
        _MockRule(Icons.check_circle, 'เกรดเฉลี่ยสะสม (GPAX)',
            '2.72 (ผ่านเกณฑ์ 2.00)', true),
        _MockRule(Icons.check_circle, 'ผ่านกิจกรรมเสริมหลักสูตร', 'ครบตามเกณฑ์',
            true),
        _MockRule(Icons.hourglass_bottom_rounded, 'ชั่วโมงฝึกประสบการณ์วิชาชีพ',
            'เหลืออีก 40 ชั่วโมง       160 / 200 ชั่วโมง', false),
        _MockRule(Icons.check_circle, 'ไม่มีหนี้ค้างชำระ',
            'ไม่มีรายการค้างชำระ', true),
      ] else
        for (final rule in rules) _RealRule(rule),
      const SizedBox(height: 10),
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xFFE8F8F0),
              borderRadius: BorderRadius.circular(17)),
          child: const Row(children: [
            Text('🎉', style: TextStyle(fontSize: 23)),
            SizedBox(width: 9),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('ทำได้ดีมาก! เหลืออีกนิดเดียวเท่านั้น',
                      style: TextStyle(
                          color: Color(0xFF16815A),
                          fontWeight: FontWeight.w700)),
                  Text('สู้ๆ นะครับ',
                      style: TextStyle(color: Color(0xFF16815A), fontSize: 12))
                ]))
          ]))
    ]);
  }
}

class _RealRule extends StatelessWidget {
  const _RealRule(this.rule);
  final GraduationRule rule;
  @override
  Widget build(BuildContext context) {
    final achieved =
        rule.achieved.toStringAsFixed(rule.achieved % 1 == 0 ? 0 : 2);
    final status = rule.satisfied
        ? 'ผ่าน'
        : (rule.isCountdown
            ? 'ค้าง ${rule.achieved.toInt()}'
            : rule.achieved.toStringAsFixed(rule.achieved % 1 == 0 ? 0 : 2));
    return Column(children: [
      _RuleCard(
          icon: rule.satisfied
              ? Icons.check_circle
              : Icons.hourglass_bottom_rounded,
          title: rule.name,
          detail:
              '$achieved / ${rule.required.toStringAsFixed(rule.required % 1 == 0 ? 0 : 2)}',
          status: status,
          ok: rule.satisfied),
      if (rule.satisfied) SizedBox(width: 0, height: 0, child: Text(achieved)),
    ]);
  }
}

class _MockRule extends StatelessWidget {
  const _MockRule(this.icon, this.title, this.detail, this.ok);
  final IconData icon;
  final String title, detail;
  final bool ok;
  @override
  Widget build(BuildContext context) => _RuleCard(
      icon: icon,
      title: title,
      detail: detail,
      status: ok ? 'ผ่าน' : 'ค้าง 40',
      ok: ok);
}

class _RuleCard extends StatelessWidget {
  const _RuleCard(
      {required this.icon,
      required this.title,
      required this.detail,
      required this.status,
      required this.ok});
  final IconData icon;
  final String title, detail, status;
  final bool ok;
  @override
  Widget build(BuildContext context) {
    final color = ok ? context.c.ok : const Color(0xFFF0A11A);
    return Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: ok ? context.c.sunk : const Color(0xFFFFF7E6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: ok ? context.c.rule : const Color(0xFFFFE4AC))),
        child: Row(children: [
          Icon(icon, color: color, size: 27),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        color: ok
                            ? const Color(0xFF186B50)
                            : const Color(0xFF8D6117),
                        fontWeight: FontWeight.w700)),
                Text(detail,
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFF69726F)))
              ])),
          Text(status,
              style: TextStyle(color: color, fontWeight: FontWeight.w700))
        ]));
  }
}
