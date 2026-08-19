import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/theme.dart';
import '../widgets.dart';

/// ตัวห่อสำหรับหน้าจอที่ต้องโหลดข้อมูล
///
/// จัดการสามสถานะให้เหมือนกันทั้งแอป: กำลังโหลด · ผิดพลาด · ออฟไลน์
/// เมื่อออฟไลน์แต่มีข้อมูลเก่าอยู่ จะแสดงข้อมูลเก่าพร้อมแถบบอกอายุข้อมูล
/// ไม่ใช่หน้าจอว่างเปล่า เพราะโรงฝึกงานและสถานประกอบการมักไม่มีสัญญาณ
class AsyncView<T> extends StatefulWidget {
  const AsyncView({
    super.key,
    required this.load,
    required this.builder,
    this.padding = const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
  });

  final Future<Fetched<T>> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final EdgeInsets padding;

  @override
  State<AsyncView<T>> createState() => AsyncViewState<T>();
}

class AsyncViewState<T> extends State<AsyncView<T>> {
  Future<Fetched<T>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> reload() async {
    setState(() {
      _future = widget.load();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: reload,
      color: context.c.ink,
      backgroundColor: context.c.bg,
      child: FutureBuilder<Fetched<T>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _scroll(
              child: Padding(
                padding: const EdgeInsets.only(top: Gap.xxl),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: context.c.ink3,
                    ),
                  ),
                ),
              ),
            );
          }

          if (snap.hasError) {
            final e = snap.error;
            return _scroll(
              child: Padding(
                padding: widget.padding.copyWith(top: Gap.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Notice(
                      title: e is OfflineException
                          ? 'ต่อเซิร์ฟเวอร์ไม่ได้'
                          : 'เปิดข้อมูลไม่สำเร็จ',
                      body: e is OfflineException
                          ? 'ยังไม่มีข้อมูลที่บันทึกไว้สำหรับหน้านี้ ลองอีกครั้งเมื่อมีสัญญาณ'
                          : e.toString(),
                      tone: Tone.crit,
                    ),
                    const SizedBox(height: Gap.xl),
                    PrimaryButton('ลองอีกครั้ง',
                        ghost: true, onPressed: reload),
                  ],
                ),
              ),
            );
          }

          final result = snap.data as Fetched<T>;
          return _scroll(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (result.fromCache) OfflineBanner(cachedAt: result.cachedAt),
                Padding(
                  padding: widget.padding,
                  child: widget.builder(context, result.data),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _scroll({required Widget child}) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [child],
      );
}
