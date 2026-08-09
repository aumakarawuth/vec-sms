import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/fmt.dart';
import '../../core/theme.dart';
import '../../screens/async_view.dart';
import '../../widgets.dart';
import '../console_widgets.dart';
import '../platform_session.dart';

/// แพ็กเกจและสัญญา
///
/// ─── ทำไมหน้าจอนี้เตือนเรื่องการแก้ราคา ───
/// ราคาที่แก้มีผลกับทุกวิทยาลัยที่ผูกแพ็กเกจนั้นอยู่ในงวดถัดไป เป็นการกระทำ
/// ที่กระทบสัญญาหลายฉบับพร้อมกันโดยไม่มีใครเห็น บันทึกฝั่งเซิร์ฟเวอร์จึงเก็บ
/// ทั้งค่าเดิมและค่าใหม่ และหน้าจอต้องบอกให้รู้ตัวก่อนกด
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.session});

  final PlatformSession session;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _key = GlobalKey<AsyncViewState<List<Map<String, dynamic>>>>();

  Future<Fetched<List<Map<String, dynamic>>>> _load() async {
    final data = await widget.session.api.get('/platform/plans') as List<dynamic>;
    return Fetched(data.map((e) => Map<String, dynamic>.from(e as Map)).toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final canWrite = widget.session.role.canWrite;

    return AsyncView<List<Map<String, dynamic>>>(
      key: _key,
      load: _load,
      builder: (context, plans) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ScreenHeader(
              kicker: 'ผู้ให้บริการ',
              title: 'แพ็กเกจ',
              subtitle: 'รายการสินค้าที่วิทยาลัยเลือกซื้อได้',
            ),
            const SizedBox(height: Gap.xl),
            for (final p in plans) ...[
              Divider(height: 1, color: context.c.rule),
              ConsoleRow(
                title: '${p['name_th']} (${p['code']})',
                subtitle: '${_limitOf(p)} · ${Fmt.money(p['price_per_year'])}/ปี'
                    '${Fmt.toNum(p['price_per_student']) == 0 ? '' : ' + ${Fmt.money(p['price_per_student'])}/คน'}',
                trailing: '${Fmt.count(p['institutions'])} แห่ง',
                badge: p['active'] == true
                    ? (p['enforcement'] == 'hard' ? 'บังคับโควตา' : null)
                    : 'ปิดการขาย',
                tone: p['active'] == true ? Tone.warn : Tone.neutral,
                onTap: canWrite
                    ? () => _openEditor(context, p)
                    : null,
              ),
            ],
            Divider(height: 1, color: context.c.rule),
            const SizedBox(height: Gap.xl),
            if (canWrite)
              PrimaryButton('เพิ่มแพ็กเกจใหม่', ghost: true, onPressed: () => _openEditor(context, null)),
            const SizedBox(height: Gap.lg),
            Text(
              'โควตาแบบ soft คือเกินได้แต่ขึ้นในรายงาน ส่วนแบบ hard จะรับนักศึกษา '
              'เพิ่มไม่ได้เมื่อเกินเพดานรวมการผ่อนผันแล้ว — การหยุดงานทะเบียน '
              'กลางภาคเรียนเสียหายกับลูกค้ามากกว่ามูลค่าที่ได้เพิ่ม',
              style: t.labelSmall,
            ),
          ],
        );
      },
    );
  }

  static String _limitOf(Map<String, dynamic> p) {
    final max = Fmt.toNum(p['max_students']);
    return max == null ? 'ไม่จำกัดจำนวนนักศึกษา' : 'ครอบ ${Fmt.count(max)} คน';
  }

  Future<void> _openEditor(BuildContext context, Map<String, dynamic>? plan) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _PlanDialog(session: widget.session, plan: plan),
    );
    if (saved == true) await _key.currentState?.reload();
  }
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({required this.session, this.plan});

  final PlatformSession session;
  final Map<String, dynamic>? plan;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final TextEditingController _code =
      TextEditingController(text: widget.plan?['code']?.toString() ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.plan?['name_th']?.toString() ?? '');
  late final TextEditingController _maxStudents = TextEditingController(
      text: widget.plan?['max_students']?.toString() ?? '');
  late final TextEditingController _pricePerYear = TextEditingController(
      text: Fmt.toNum(widget.plan?['price_per_year'])?.toString() ?? '0');
  late final TextEditingController _pricePerStudent = TextEditingController(
      text: Fmt.toNum(widget.plan?['price_per_student'])?.toString() ?? '0');

  late bool _hard = widget.plan?['enforcement'] == 'hard';
  late bool _active = widget.plan?['active'] != false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _maxStudents.dispose();
    _pricePerYear.dispose();
    _pricePerStudent.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.api.post('/platform/plans', {
        'code': _code.text.trim(),
        'nameTh': _name.text.trim(),
        if (_maxStudents.text.trim().isNotEmpty)
          'maxStudents': int.tryParse(_maxStudents.text.trim()),
        'pricePerYear': num.tryParse(_pricePerYear.text.trim()) ?? 0,
        'pricePerStudent': num.tryParse(_pricePerStudent.text.trim()) ?? 0,
        'enforcement': _hard ? 'hard' : 'soft',
        'active': _active,
      });
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on OfflineException {
      setState(() => _error = 'ต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final editing = widget.plan != null;

    return AlertDialog(
      backgroundColor: context.c.bg,
      title: Text(editing ? 'แก้แพ็กเกจ' : 'เพิ่มแพ็กเกจ'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const GroupHeader('รหัสแพ็กเกจ'),
              ConsoleField(controller: _code, enabled: !editing && !_busy, hint: 'standard'),
              const SizedBox(height: Gap.lg),
              const GroupHeader('ชื่อที่แสดง'),
              ConsoleField(controller: _name, enabled: !_busy),
              const SizedBox(height: Gap.lg),
              const GroupHeader('จำนวนนักศึกษาที่ครอบ'),
              ConsoleField(
                controller: _maxStudents,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                hint: 'เว้นว่างคือไม่จำกัด',
              ),
              const SizedBox(height: Gap.lg),
              const GroupHeader('ราคาต่อปี'),
              ConsoleField(
                controller: _pricePerYear,
                enabled: !_busy,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: Gap.lg),
              const GroupHeader('ราคาต่อนักศึกษาหนึ่งคน'),
              ConsoleField(
                controller: _pricePerStudent,
                enabled: !_busy,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: Gap.lg),
              SwitchListTile.adaptive(
                value: _hard,
                onChanged: _busy ? null : (v) => setState(() => _hard = v),
                title: Text('บังคับโควตา (hard)', style: t.bodyLarge),
                subtitle: Text(
                  'เกินแล้วรับนักศึกษาเพิ่มไม่ได้ — ใช้เมื่อตกลงกับลูกค้าแล้วเท่านั้น',
                  style: t.bodySmall,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _active,
                onChanged: _busy ? null : (v) => setState(() => _active = v),
                title: Text('เปิดขาย', style: t.bodyLarge),
                contentPadding: EdgeInsets.zero,
              ),
              if (editing) ...[
                const SizedBox(height: Gap.md),
                const Notice(
                  title: 'ราคาที่แก้มีผลกับลูกค้าที่ผูกแพ็กเกจนี้อยู่',
                  body: 'ค่าเดิมและค่าใหม่จะถูกบันทึกไว้ในประวัติการกระทำ',
                  tone: Tone.warn,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: Gap.md),
                Notice(title: 'บันทึกไม่สำเร็จ', body: _error, tone: Tone.crit),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'กำลังบันทึก' : 'บันทึก'),
        ),
      ],
    );
  }
}
