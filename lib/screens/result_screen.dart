import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../models/tool_catalog.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final String toolId;
  final String filename;
  const ResultScreen(
      {super.key, required this.toolId, required this.filename});
  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _circleCtrl;
  late AnimationController _checkCtrl;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _circleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _checkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    Future.delayed(const Duration(milliseconds: 100),
        () => _circleCtrl.forward());
    Future.delayed(const Duration(milliseconds: 700),
        () => _checkCtrl.forward());
  }

  @override
  void dispose() {
    _circleCtrl.dispose();
    _checkCtrl.dispose();
    super.dispose();
  }

  void _showToast(String msg) {
    setState(() => _toast = msg);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  Future<void> _share(String? outputPath) async {
    if (outputPath == null || !File(outputPath).existsSync()) {
      _showToast('Output file not found');
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(outputPath)],
        text: 'Processed with PDFist',
      ),
    );
  }

  Future<void> _saveToDevice(String? outputPath) async {
    if (outputPath == null || !File(outputPath).existsSync()) {
      _showToast('Output file not found');
      return;
    }
    // share_plus handles the "save" dialog via ShareParams with only files.
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(outputPath)],
      ),
    );
    _showToast('Saved — choose a location in the share sheet');
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(lastResultProvider);
    final tool = findTool(widget.toolId);
    final toolLabel = tool?.label ?? widget.toolId;
    final outputName = result?.outputPath != null
        ? p.basename(result!.outputPath!)
        : '${widget.toolId}_${widget.filename.split('.').first}.pdf';
    final isCompress = widget.toolId == 'compress';
    final hasExtras = result?.extras != null && result!.extras!.isNotEmpty;
    final hasOutput = result?.outputPath != null;
    final outputExt = result?.outputPath != null
        ? p.extension(result!.outputPath!).replaceFirst('.', '').toUpperCase()
        : 'PDF';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Back button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.line),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.arrow_back,
                              color: AppColors.text, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        // Animated checkmark
                        const SizedBox(height: 36),
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CustomPaint(
                            painter: _CheckmarkPainter(
                              circleProgress: _circleCtrl,
                              checkProgress: _checkCtrl,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Column(
                          children: [
                            Eyebrow('$toolLabel · Complete'),
                            const SizedBox(height: 10),
                            Text('Done.',
                                style: AppTextStyles.display(32,
                                    weight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 36),
                        // Extras card (metadata / stats / thumbnails info)
                        if (hasExtras) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.line),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Eyebrow('Details'),
                                const SizedBox(height: 14),
                                ...(result.extras ?? {}).entries.map((e) => Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: const BoxDecoration(
                                          border: Border(top: BorderSide(color: AppColors.line))),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(e.key,
                                              style: AppTextStyles.body(13,
                                                  color: AppColors.muted)),
                                          Flexible(
                                            child: Text(e.value,
                                                style: AppTextStyles.mono(12),
                                                textAlign: TextAlign.right,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    )),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        // File output card — only when there is an output file
                        if (hasOutput) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.line),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    PdfFileThumbnail(label: outputExt),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Eyebrow('Output'),
                                          const SizedBox(height: 4),
                                          Text(outputName,
                                              style: AppTextStyles.body(14, weight: FontWeight.w500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(height: 1, color: AppColors.line),
                                const SizedBox(height: 16),
                                if (isCompress && result != null)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Eyebrow('Before'),
                                            const SizedBox(height: 4),
                                            Text(result.sizeBeforeFormatted,
                                                style: AppTextStyles.mono(18, weight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.arrow_forward, color: AppColors.text, size: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            const Eyebrow('After'),
                                            const SizedBox(height: 4),
                                            Text(result.sizeAfterFormatted,
                                                style: AppTextStyles.mono(18, weight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _Stat(label: 'Size', value: result?.sizeAfterFormatted ?? '—'),
                                      _Stat(
                                          label: 'Pages',
                                          value: result?.pageCount != null ? '${result!.pageCount}' : '—'),
                                      _Stat(
                                          label: 'Time',
                                          value: result?.processingTimeMs != null
                                              ? '${(result!.processingTimeMs / 1000).toStringAsFixed(1)}s'
                                              : '—'),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          FillButton(
                            label: 'Save to Device',
                            icon: const Icon(Icons.save_alt, color: AppColors.bg, size: 18),
                            onTap: () => _saveToDevice(result?.outputPath),
                          ),
                          const SizedBox(height: 10),
                          OutlineButton(
                            label: 'Share',
                            icon: const Icon(Icons.share, color: AppColors.text, size: 18),
                            onTap: () => _share(result?.outputPath),
                          ),
                        ] else if (!hasExtras) ...[
                          // No output file and no extras — generic done state
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.line),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _Stat(label: 'Pages', value: result?.pageCount != null ? '${result!.pageCount}' : '—'),
                                _Stat(label: 'Input', value: result?.sizeBeforeFormatted ?? '—'),
                                _Stat(label: 'Time',
                                    value: result?.processingTimeMs != null
                                        ? '${(result!.processingTimeMs / 1000).toStringAsFixed(1)}s' : '—'),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 48),
                        GestureDetector(
                          onTap: () => context.go('/history'),
                          child: Text(
                            'View History →',
                            style: AppTextStyles.body(13,
                                    weight: FontWeight.w500)
                                .copyWith(
                                    color: AppColors.muted,
                                    letterSpacing: 0.04 * 13),
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ToastOverlay(message: _toast),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.mono(14)),
        ],
      );
}

class _CheckmarkPainter extends CustomPainter {
  final Animation<double> circleProgress;
  final Animation<double> checkProgress;

  _CheckmarkPainter(
      {required this.circleProgress, required this.checkProgress})
      : super(repaint: Listenable.merge([circleProgress, checkProgress]));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.square;

    canvas.drawArc(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      -1.5708,
      2 * 3.14159 * circleProgress.value,
      false,
      paint,
    );

    if (checkProgress.value > 0) {
      paint.strokeWidth = 2.5;
      final points = [
        Offset(24 / 80 * size.width, 40 / 80 * size.height),
        Offset(36 / 80 * size.width, 52 / 80 * size.height),
        Offset(58 / 80 * size.width, 30 / 80 * size.height),
      ];
      final totalLen = _len(points);
      final drawLen = checkProgress.value * totalLen;
      double acc = 0;
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        final seg = (points[i] - points[i - 1]).distance;
        if (acc + seg <= drawLen) {
          path.lineTo(points[i].dx, points[i].dy);
          acc += seg;
        } else {
          final t = (drawLen - acc) / seg;
          path.lineTo(
            points[i - 1].dx + t * (points[i].dx - points[i - 1].dx),
            points[i - 1].dy + t * (points[i].dy - points[i - 1].dy),
          );
          break;
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  double _len(List<Offset> pts) {
    double l = 0;
    for (int i = 1; i < pts.length; i++) {
      l += (pts[i] - pts[i - 1]).distance;
    }
    return l;
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter old) => true;
}
