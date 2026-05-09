import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/history_entry.dart';
import '../providers/providers.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _toast;

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _onTabTap(int i) {
    if (i == 0) context.go('/home');
    if (i == 2) context.go('/settings');
  }

  Future<void> _delete(HistoryEntry entry) async {
    await HistoryService.instance.deleteEntry(entry.id);
    ref.invalidate(historyProvider);
    _showToast('Deleted');
  }

  @override
  Widget build(BuildContext context) {
    final tick = ref.watch(historyRefreshProvider);
    final historyAsync = ref.watch(historyProvider(tick));

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('Archive'),
                      const SizedBox(height: 8),
                      historyAsync.when(
                        data: (items) => Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('History',
                                style: AppTextStyles.display(38,
                                    weight: FontWeight.w700)),
                            Text(
                                '${items.length.toString().padLeft(2, '0')} files',
                                style: AppTextStyles.mono(11,
                                    color: AppColors.muted)),
                          ],
                        ),
                        loading: () => Text('History',
                            style: AppTextStyles.display(38,
                                weight: FontWeight.w700)),
                        error: (err, st) => Text('History',
                            style: AppTextStyles.display(38,
                                weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: historyAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.text, strokeWidth: 2),
                  ),
                  error: (err, st) => Center(
                    child: Text('Could not load history.',
                        style: AppTextStyles.body(14, color: AppColors.muted)),
                  ),
                  data: (items) => items.isEmpty
                      ? const _EmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 24, bottom: 24),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _HistoryRow(
                            item: items[i],
                            onDelete: () => _delete(items[i]),
                          ),
                        ),
                ),
              ),
              AppBottomNav(currentIndex: 1, onTap: _onTabTap),
            ],
          ),
          ToastOverlay(message: _toast),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatefulWidget {
  final HistoryEntry item;
  final VoidCallback onDelete;
  const _HistoryRow({required this.item, required this.onDelete});
  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _swiped = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Stack(
        children: [
          // Delete background
          Positioned(
            right: 0, top: 0, bottom: 0, width: 80,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                color: AppColors.text,
                alignment: Alignment.center,
                child: Text('Delete',
                    style: AppTextStyles.body(12,
                        weight: FontWeight.w600, color: AppColors.bg)
                        .copyWith(letterSpacing: 0.1 * 12)),
              ),
            ),
          ),
          // Row
          GestureDetector(
            onTap: () => setState(() => _swiped = !_swiped),
            onHorizontalDragEnd: (d) {
              if (d.primaryVelocity == null) return;
              if (d.primaryVelocity! < -200) setState(() => _swiped = true);
              if (d.primaryVelocity! > 200) setState(() => _swiped = false);
            },
            child: AnimatedSlide(
              offset: _swiped ? const Offset(-0.205, 0) : Offset.zero,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: Container(
                color: AppColors.bg,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.insert_drive_file_outlined,
                        color: AppColors.text, size: 20),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(widget.item.fileName,
                              style: AppTextStyles.body(14,
                                  weight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              AppChip(widget.item.action),
                              const SizedBox(width: 8),
                              Text(widget.item.sizeFormatted,
                                  style: AppTextStyles.mono(10,
                                      color: AppColors.muted)),
                              const SizedBox(width: 4),
                              Text('· ${widget.item.timeAgo}',
                                  style: AppTextStyles.mono(10,
                                      color: AppColors.faint)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.more_horiz,
                        color: AppColors.text.withValues(alpha: 0.4),
                        size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                  size: const Size(120, 120), painter: _EmptyDocPainter()),
              const SizedBox(height: 24),
              const Eyebrow('No history yet'),
              const SizedBox(height: 8),
              Text('A blank page.',
                  style: AppTextStyles.display(22, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                "Process your first PDF and\nit'll appear here.",
                style: AppTextStyles.body(13, color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class _EmptyDocPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(Rect.fromLTWH(30, 20, 60, 80), paint);
    canvas.drawLine(const Offset(75, 20), const Offset(75, 35), paint);
    canvas.drawLine(const Offset(75, 35), const Offset(90, 35), paint);
    for (final y in [50.0, 60.0, 70.0, 80.0]) {
      canvas.drawLine(
          Offset(40, y), Offset(size.width * 0.625, y), paint..strokeWidth = 1.0);
    }
    final dash = Paint()
      ..color = AppColors.text.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (var i = 0; i < 24; i++) {
      canvas.drawArc(
          const Rect.fromLTWH(18, 18, 84, 84),
          i * 2 * 3.14159 / 24, 0.16, false, dash);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
