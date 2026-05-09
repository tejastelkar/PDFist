import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/tool_catalog.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  final String toolId;
  final String filename;
  const ProcessingScreen(
      {super.key, required this.toolId, required this.filename});
  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final params = ref.read(currentOperationProvider);
    if (params == null) {
      // Nothing to process — go back.
      if (mounted) context.go('/home');
      return;
    }
    await ref.read(pdfProcessingProvider.notifier).process(params);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfProcessingProvider);
    final tool = findTool(widget.toolId);
    final toolLabel = tool?.label ?? widget.toolId;

    // Navigate on completion.
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    ref.listen<ProcessingState>(pdfProcessingProvider, (prev, next) {
      if (next.status == ProcessingStatus.success) {
        ref.read(lastResultProvider.notifier).state = next.result;
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) {
            router.go(
                '/result/${widget.toolId}/${Uri.encodeComponent(widget.filename)}');
          }
        });
      } else if (next.status == ProcessingStatus.failed) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            messenger.showSnackBar(SnackBar(
              backgroundColor: AppColors.text,
              content: Text(
                next.error ?? 'Processing failed.',
                style: AppTextStyles.body(13, color: AppColors.bg),
              ),
            ));
            router.go('/home');
          }
        });
      }
    });

    final progress = state.progress.clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Eyebrow('Status / In progress'),
                    const SizedBox(height: 20),
                    Text(
                      widget.filename,
                      style: AppTextStyles.display(30, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(state.message.isNotEmpty
                            ? state.message
                            : '${toolLabel}ing',
                            style: AppTextStyles.body(14, color: AppColors.muted)),
                        if (state.status == ProcessingStatus.processing)
                          const _DotPulse(),
                      ],
                    ),
                    const SizedBox(height: 56),
                    // Progress counter
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('PROGRESS',
                            style:
                                AppTextStyles.mono(11, color: AppColors.muted)),
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: (progress * 100).round().toString(),
                              style: AppTextStyles.display(32,
                                  weight: FontWeight.w600),
                            ),
                            TextSpan(
                              text: '%',
                              style: AppTextStyles.display(16,
                                      weight: FontWeight.w400)
                                  .copyWith(color: AppColors.muted),
                            ),
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Progress bar
                    ClipRect(
                      child: Container(
                        height: 4,
                        color: AppColors.text.withValues(alpha: 0.12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedFractionallySizedBox(
                            widthFactor: progress,
                            duration: const Duration(milliseconds: 200),
                            child: Container(color: AppColors.text),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [0, 25, 50, 75, 100]
                          .map((t) => Text(t.toString(),
                              style:
                                  AppTextStyles.mono(9, color: AppColors.faint)))
                          .toList(),
                    ),
                    const SizedBox(height: 56),
                    // Stats
                    ...[
                      ['Engine', 'flutter · local'],
                      ['Network', 'never used'],
                    ].asMap().entries.map((e) => Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(
                              top: e.key > 0
                                  ? const BorderSide(color: AppColors.line)
                                  : BorderSide.none,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.value[0],
                                  style: AppTextStyles.body(12,
                                      color: AppColors.muted)),
                              Text(e.value[1],
                                  style: AppTextStyles.mono(12)),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    ref.read(pdfProcessingProvider.notifier).reset();
                    context.go('/home');
                  },
                  child: Text('Cancel',
                      style: AppTextStyles.body(13, weight: FontWeight.w500)
                          .copyWith(
                              letterSpacing: 0.04 * 13,
                              color: AppColors.muted)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotPulse extends StatefulWidget {
  const _DotPulse();
  @override
  State<_DotPulse> createState() => _DotPulseState();
}

class _DotPulseState extends State<_DotPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final t = (_ctrl.value - i * 0.14).clamp(0.0, 1.0);
              final opacity =
                  (0.5 + 0.5 * (1 - (2 * t - 1).abs())).clamp(0.0, 1.0);
              return Text(
                '.',
                style: AppTextStyles.body(14)
                    .copyWith(color: AppColors.muted.withValues(alpha: opacity)),
              );
            }),
          );
        },
      );
}
