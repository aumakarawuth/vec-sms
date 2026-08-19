import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../screens/async_view.dart';
import '../../widgets.dart';
import '../console_widgets.dart';
import '../platform_session.dart';

/// ทะเบียนวิทยาลัย — หน้าจอแรกที่ผู้ให้บริการเปิดทุกเช้า
///
/// ─── ตัวเลขที่แสดงมาจากภาพนิ่ง ไม่ใช่ค่าสด ───
/// จำนวนนักศึกษาอ่านจาก usage_snapshot ที่งานประจำวันเก็บไว้ ไม่ใช่การนับสด
/// ในบริบทของวิทยาลัย เพราะการนับสดแปลว่าหน้าจอนี้ต้องยืมสิทธิ์ของลูกค้า
/// มาอ่านข้อมูล ซึ่งเปิดทางให้อ่านอะไรก็ได้ในวิทยาลัยนั้น
///
/// หน้าจอจึงบอกวันที่ของภาพนิ่งไว้ตรง ๆ แทนที่จะทำเหมือนเป็นค่าปัจจุบัน
class InstitutionsScreen extends StatefulWidget {
  const InstitutionsScreen({super.key, required this.session});

  final PlatformSession session;

  @override
  State<InstitutionsScreen> createState() => _InstitutionsScreenState();
}

class _InstitutionsScreenState extends State<InstitutionsScreen> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<Fetched<Map<String, dynamic>>> _load() async {
    final data = await widget.session.api.get('/platform/institutions');
    return Fetched(Map<String, dynamic>.from(data as Map));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return AsyncView<Map<String, dynamic>>(
      key: _key,
      load: _load,
      builder: (context, data) {
        final rows = (data['rows'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((r) => _matches(r))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenHeader(
              kicker: 'ผู้ให้บริการ',
              title: 'ทะเบียนวิทยาลัย',
            ),
            const SizedBox(height: Gap.lg),
            Row(
              children: [
                Expanded(
                  child: Figure(
                    Fmt.count(data['institutions']),
                    caption: 'วิทยาลัย',
                    small: true,
                  ),
                ),
                Expanded(
                  child: Figure(
                    Fmt.count(data['overQuota']),
                    caption: 'เกินโควตา',
                    small: true,
                    tone: Fmt.toNum(data['overQuota']) == 0
                        ? Tone.neutral
                        : Tone.warn,
                  ),
                ),
                Expanded(
                  child: Figure(
                    Fmt.count(data['suspended']),
                    caption: 'ถูกระงับ',
                    small: true,
                    tone: Fmt.toNum(data['suspended']) == 0
                        ? Tone.neutral
                        : Tone.crit,
                  ),
                ),
                Expanded(
                  child: Figure(
                    Fmt.count(data['unassigned']),
                    caption: 'ยังไม่ผูกแพ็กเกจ',
                    small: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gap.xl),
            ConsoleField(
              controller: _search,
              hint: 'ค้นหาด้วยรหัสหรือชื่อสถานศึกษา',
              onSubmitted: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: Gap.md),
            PrimaryButton(
              'ค้นหา',
              ghost: true,
              onPressed: () => setState(() => _query = _search.text.trim()),
            ),
            const SizedBox(height: Gap.xl),
            GroupHeader(
              'รายชื่อ',
              trailing: Text('${rows.length} แห่ง', style: t.bodySmall),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xl),
                child: Text('ไม่พบสถานศึกษาตามที่ค้นหา', style: t.bodyMedium),
              ),
            for (final r in rows) ...[
              Divider(height: 1, color: context.c.rule),
              ConsoleRow(
                title: '${r['code']} · ${r['name_th']}',
                subtitle: _planLine(r),
                trailing: Fmt.count(r['students_active']),
                badge: _badgeOf(r),
                tone: _toneOf(r),
                onTap: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute<void>(
                        builder: (_) => InstitutionDetailScreen(
                          session: widget.session,
                          institutionId: r['id'].toString(),
                          title: r['name_th'].toString(),
                        ),
                      ),
                    )
                    .then((_) => _key.currentState?.reload()),
              ),
            ],
            Divider(height: 1, color: context.c.rule),
            const SizedBox(height: Gap.lg),
            Text(data['note']?.toString() ?? '', style: t.labelSmall),
            if (widget.session.role.canWrite) ...[
              const SizedBox(height: Gap.lg),
              PrimaryButton(
                'เก็บภาพนิ่งปริมาณใช้งานใหม่',
                ghost: true,
                onPressed: () async {
                  await widget.session.api.post('/platform/usage/refresh');
                  await _key.currentState?.reload();
                },
              ),
            ],
          ],
        );
      },
    );
  }

  bool _matches(Map<String, dynamic> r) {
    if (_query.isEmpty) return true;
    final hay = '${r['code']} ${r['name_th']}'.toLowerCase();
    return hay.contains(_query.toLowerCase());
  }

  static String _planLine(Map<String, dynamic> r) {
    final plan = r['plan_name_th']?.toString() ?? 'ยังไม่ผูกแพ็กเกจ';
    final taken = Fmt.parseDate(r['usage_taken_on']);
    final when =
        taken == null ? 'ยังไม่มีภาพนิ่ง' : 'ณ ${Fmt.dateShort(taken)}';
    return '$plan · $when';
  }

  static String? _badgeOf(Map<String, dynamic> r) {
    if (r['suspended_at'] != null) return 'ถูกระงับ';
    final over = Fmt.toNum(r['over_students']) ?? 0;
    if (over > 0) return 'เกินโควตา $over คน';
    if (r['plan_code'] == null) return 'ยังไม่ผูกแพ็กเกจ';
    return null;
  }

  static Tone _toneOf(Map<String, dynamic> r) {
    if (r['suspended_at'] != null) return Tone.crit;
    if ((Fmt.toNum(r['over_students']) ?? 0) > 0) return Tone.warn;
    return Tone.neutral;
  }
}

/// รายละเอียดของวิทยาลัยหนึ่งแห่ง
///
/// สิ่งที่ **ไม่มี** ในหน้านี้คือสิ่งที่สำคัญที่สุด — ไม่มีรายชื่อนักศึกษา
/// ไม่มีข้อมูลบุคลากร ไม่มีทางเข้าไปดูข้อมูลในวิทยาลัย เพราะบัญชีที่เปิด
/// หน้าจอนี้ไม่มีบริบทวิทยาลัย ต่อให้เขียน query ไปก็ได้ศูนย์แถวกลับมา
class InstitutionDetailScreen extends StatefulWidget {
  const InstitutionDetailScreen({
    super.key,
    required this.session,
    required this.institutionId,
    required this.title,
  });

  final PlatformSession session;
  final String institutionId;
  final String title;

  @override
  State<InstitutionDetailScreen> createState() =>
      _InstitutionDetailScreenState();
}

class _InstitutionDetailScreenState extends State<InstitutionDetailScreen> {
  final _key = GlobalKey<AsyncViewState<Map<String, dynamic>>>();

  Future<Fetched<Map<String, dynamic>>> _load() async {
    final data = await widget.session.api
        .get('/platform/institutions/${widget.institutionId}');
    return Fetched(Map<String, dynamic>.from(data as Map));
  }

  Future<void> _suspend() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(),
    );
    if (reason == null || !mounted) return;

    await _guard(() => widget.session.api.post(
          '/platform/institutions/${widget.institutionId}/suspend',
          {'reason': reason},
        ));
  }

  Future<void> _resume() async {
    await _guard(() => widget.session.api
        .post('/platform/institutions/${widget.institutionId}/resume', {}));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
      await _key.currentState?.reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } on OfflineException {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ต่อเซิร์ฟเวอร์ไม่ได้')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: AsyncView<Map<String, dynamic>>(
        key: _key,
        load: _load,
        builder: (context, data) {
          final inst = Map<String, dynamic>.from(data['institution'] as Map);
          final subs = (data['subscriptions'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final usage = (data['usage'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final actions = (data['actions'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final suspended = inst['suspended_at'] != null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                kicker: inst['code']?.toString(),
                title: inst['name_th']?.toString() ?? '—',
                subtitle: inst['name_en']?.toString(),
              ),
              if (suspended) ...[
                const SizedBox(height: Gap.lg),
                Notice(
                  title: 'ถูกระงับการใช้งาน',
                  body: '${inst['suspended_reason'] ?? 'ไม่ได้ระบุเหตุผล'}\n'
                      'ข้อมูลทุกแถวยังอยู่ครบ คืนสิทธิ์แล้วผู้ใช้เข้าระบบได้ทันที',
                  tone: Tone.crit,
                ),
              ],
              const SizedBox(height: Gap.xl),
              const GroupHeader('ปริมาณใช้งานล่าสุด'),
              const SizedBox(height: Gap.md),
              if (usage.isEmpty)
                Text(
                  'ยังไม่มีภาพนิ่ง — งานประจำวัน usage-snapshot อาจยังไม่ได้รัน',
                  style: t.bodyMedium,
                )
              else ...[
                InfoRow('วันที่เก็บ',
                    value: Fmt.dateShortOf(usage.first['taken_on'])),
                InfoRow('นักศึกษากำลังศึกษา',
                    value: Fmt.count(usage.first['students_active'])),
                InfoRow('บุคลากร',
                    value: Fmt.count(usage.first['staff_active'])),
                InfoRow('เอกสารที่ออกแล้ว',
                    value: Fmt.count(usage.first['documents_issued'])),
                InfoRow('ใบสมัคร',
                    value: Fmt.count(usage.first['applications'])),
              ],
              const SizedBox(height: Gap.xl),
              const GroupHeader('สัญญา'),
              const SizedBox(height: Gap.md),
              if (subs.isEmpty)
                Text(
                    'ยังไม่เคยผูกแพ็กเกจ — ยังใช้งานได้ตามปกติ ไม่ถูกบังคับโควตา',
                    style: t.bodyMedium),
              for (final s in subs)
                InfoRow(
                  '${s['plan_name_th']} · ${s['status']}',
                  value: '${Fmt.dateShortOf(s['starts_on'])} – '
                      '${s['ends_on'] == null ? 'ไม่กำหนด' : Fmt.dateShortOf(s['ends_on'])}',
                ),
              const SizedBox(height: Gap.xl),
              const GroupHeader('การกระทำของผู้ให้บริการกับวิทยาลัยนี้'),
              const SizedBox(height: Gap.md),
              if (actions.isEmpty) Text('ยังไม่มีบันทึก', style: t.bodyMedium),
              for (final a in actions.take(20))
                InfoRow(
                  '${a['action']}',
                  value:
                      '${a['username']} · ${Fmt.dateShortOf(a['occurred_at'])}',
                ),
              if (widget.session.role.canWrite) ...[
                const SizedBox(height: Gap.xxl),
                PrimaryButton(
                  suspended ? 'คืนสิทธิ์การใช้งาน' : 'ระงับการใช้งาน',
                  ghost: !suspended,
                  onPressed: suspended ? _resume : _suspend,
                ),
                const SizedBox(height: Gap.md),
                Text(
                  suspended
                      ? 'คืนสิทธิ์แล้วผู้ใช้ของวิทยาลัยเข้าระบบได้ทันที'
                      : 'การระงับปิดเฉพาะการเข้าสู่ระบบ ไม่ลบและไม่ซ่อนข้อมูลของลูกค้า '
                          'และ session ที่ค้างอยู่จะถูกตัดทันที',
                  style: t.labelSmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// ถามเหตุผลก่อนระงับ
///
/// เหตุผลไม่ใช่พิธีกรรม — เป็นข้อความเดียวที่ผู้ใช้ของวิทยาลัยจะเห็นตอน
/// เข้าระบบไม่ได้ ทั้งฐานข้อมูลและ DTO บังคับให้มี หน้าจอจึงบังคับด้วย
/// เพื่อไม่ให้ผู้ใช้ไปเจอข้อความปฏิเสธจากเซิร์ฟเวอร์ทีหลัง
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      backgroundColor: context.c.bg,
      title: const Text('ระงับการใช้งาน'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ข้อความนี้จะแสดงให้ผู้ใช้ทุกคนของวิทยาลัยเห็นตอนเข้าระบบไม่ได้ '
              'เขียนให้ชัดว่าต้องทำอะไรต่อ',
              style: t.bodySmall,
            ),
            const SizedBox(height: Gap.lg),
            ConsoleField(
              controller: _reason,
              hint:
                  'ค้างชำระค่าบริการเกิน 60 วัน — ติดต่อฝ่ายบัญชี 02-xxx-xxxx',
              maxLines: 3,
            ),
            if (_error != null) ...[
              const SizedBox(height: Gap.md),
              Text(_error!,
                  style: t.bodySmall?.copyWith(color: context.c.crit)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        TextButton(
          onPressed: () {
            final v = _reason.text.trim();
            if (v.length < 10) {
              setState(() => _error = 'เหตุผลต้องยาวอย่างน้อย 10 ตัวอักษร');
              return;
            }
            Navigator.of(context).pop(v);
          },
          child: const Text('ระงับ'),
        ),
      ],
    );
  }
}
