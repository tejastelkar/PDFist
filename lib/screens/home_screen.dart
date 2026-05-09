import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/history_entry.dart';
import '../models/tool_catalog.dart';
import '../models/tool_model.dart';
import '../providers/providers.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tick = ref.watch(historyRefreshProvider);
    final historyAsync = ref.watch(historyProvider(tick));
    final initials = AuthService.instance.isAnonymousSession
        ? '?'
        : AuthService.instance.initials;

    void onTabTap(int i) {
      if (i == 1) context.go('/history');
      if (i == 2) context.go('/settings');
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: _buildHeader(context, initials),
              ),
              Expanded(
                child: _buildScrollBody(context, ref, historyAsync),
              ),
              AppBottomNav(currentIndex: 0, onTap: onTabTap),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 92,
            child: _Fab(onTap: () => context.go('/tool/merge')),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String initials) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PDFist',
              style: AppTextStyles.display(26, weight: FontWeight.w800)
                  .copyWith(letterSpacing: -0.04 * 26),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/search'),
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    child: const Icon(Icons.search,
                        color: AppColors.text, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => context.go('/settings'),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.text),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(initials,
                        style: AppTextStyles.body(12,
                            weight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _buildScrollBody(BuildContext context, WidgetRef ref,
      AsyncValue<List<HistoryEntry>> historyAsync) {
    final greeting = _greeting();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // Hero greeting
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(greeting),
              const SizedBox(height: 10),
              Text(
                "What shall we\nrefine today?",
                style: AppTextStyles.display(34, weight: FontWeight.w700)
                    .copyWith(letterSpacing: -0.03 * 34),
              ),
            ],
          ),
        ),

        // Category rows
        ...kCategories.asMap().entries.map((entry) {
          final i = entry.key;
          final cat = entry.value;
          return _CategoryRow(cat: cat, topSpacing: i == 0 ? 8 : 22);
        }),

        // All Tools link
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: GestureDetector(
            onTap: () => context.go('/all-tools'),
            child: Text(
              'All Tools',
              style: AppTextStyles.body(14, weight: FontWeight.w500).copyWith(
                decoration: TextDecoration.underline,
                decorationColor: AppColors.text,
              ),
            ),
          ),
        ),

        // Recent Activity
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Eyebrow('Recent Activity'),
              GestureDetector(
                onTap: () => context.go('/history'),
                child: Text('VIEW ALL →',
                    style: AppTextStyles.mono(10,
                        color: AppColors.text.withValues(alpha: 0.7))),
              ),
            ],
          ),
        ),

        historyAsync.when(
          loading: () => const SizedBox(
            height: 148,
            child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.text, strokeWidth: 2),
            ),
          ),
          error: (err, st) => const SizedBox(height: 148),
          data: (items) => items.isEmpty
              ? SizedBox(
                  height: 148,
                  child: Center(
                    child: Text('No recent activity.',
                        style: AppTextStyles.mono(11,
                            color: AppColors.faint)),
                  ),
                )
              : SizedBox(
                  height: 148,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: items.take(10).length,
                    separatorBuilder: (ctx, i) => const SizedBox(width: 10),
                    itemBuilder: (context, i) =>
                        _RecentCard(item: items[i]),
                  ),
                ),
        ),

        // Footer
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 36, 20, 120),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('OFFLINE — ALL OPS LOCAL',
                  style: AppTextStyles.mono(9,
                      color: AppColors.text.withValues(alpha: 0.3))),
              Text('○',
                  style: AppTextStyles.mono(9,
                      color: AppColors.text.withValues(alpha: 0.3))),
            ],
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _CategoryRow extends StatelessWidget {
  final ToolCategory cat;
  final double topSpacing;
  const _CategoryRow({required this.cat, this.topSpacing = 22});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topSpacing),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SectionHeader(
              title: cat.label,
              count: cat.tools.length.toString().padLeft(2, '0'),
            ),
          ),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: cat.tools.length,
              separatorBuilder: (ctx, i) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final t = cat.tools[i];
                final tool = findTool(t.id)!;
                return _ToolCard(tool: tool);
              },
            ),
          ),
        ],
      );
}

class _ToolCard extends StatefulWidget {
  final PdfTool tool;
  const _ToolCard({required this.tool});
  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        context.go('/tool/${widget.tool.id}');
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 130,
        height: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _pressed ? AppColors.text : AppColors.bg,
          border: Border.all(
              color: _pressed ? AppColors.text : AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.picture_as_pdf_outlined,
                    size: 20,
                    color: _pressed ? AppColors.bg : AppColors.text),
                Text(widget.tool.num,
                    style: AppTextStyles.mono(10,
                        color: _pressed
                            ? AppColors.bg.withValues(alpha: 0.5)
                            : AppColors.faint)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tool.label,
                  style: AppTextStyles.display(14, weight: FontWeight.w600)
                      .copyWith(
                          color: _pressed ? AppColors.bg : AppColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.tool.desc,
                  style: AppTextStyles.body(10,
                          color: (_pressed ? AppColors.bg : AppColors.text)
                              .withValues(alpha: 0.5))
                      .copyWith(height: 1.3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final HistoryEntry item;
  const _RecentCard({required this.item});

  @override
  Widget build(BuildContext context) => Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bg,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    color: AppColors.text, size: 18),
                AppChip(item.action),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName,
                  style: AppTextStyles.body(13, weight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(item.sizeFormatted,
                    style: AppTextStyles.mono(10, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(item.timeAgo,
                    style: AppTextStyles.mono(10, color: AppColors.faint)),
              ],
            ),
          ],
        ),
      );
}

class _Fab extends StatefulWidget {
  final VoidCallback onTap;
  const _Fab({required this.onTap});
  @override
  State<_Fab> createState() => _FabState();
}

class _FabState extends State<_Fab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
              color: AppColors.text, shape: BoxShape.circle),
          child: Transform.rotate(
            angle: _pressed ? 0.785398 : 0,
            child: const Icon(Icons.add, color: AppColors.bg, size: 22),
          ),
        ),
      );
}
