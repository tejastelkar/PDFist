import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../models/tool_catalog.dart';
import '../models/tool_model.dart';

class AllToolsScreen extends StatelessWidget {
  const AllToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top nav
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/home'),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_back, color: AppColors.text, size: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text('All Tools',
                        style: AppTextStyles.display(28, weight: FontWeight.w700)
                            .copyWith(letterSpacing: -0.02 * 28)),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/search'),
                    child: Container(
                      width: 40, height: 40,
                      alignment: Alignment.center,
                      child: const Icon(Icons.search, color: AppColors.text, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: kCategories.map((cat) => _CategorySection(cat: cat)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final ToolCategory cat;
  const _CategorySection({required this.cat});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: SectionHeader(
              title: cat.label,
              count: cat.tools.length.toString().padLeft(2, '0'),
            ),
          ),
          ...cat.tools.map((t) {
            final tool = findTool(t.id)!;
            return _ToolRow(tool: tool);
          }),
        ],
      );
}

class _ToolRow extends StatelessWidget {
  final PdfTool tool;
  const _ToolRow({required this.tool});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.go('/tool/${tool.id}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(tool.num, style: AppTextStyles.mono(10, color: AppColors.faint)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(tool.label, style: AppTextStyles.body(14, weight: FontWeight.w500)),
              ),
              Icon(Icons.arrow_forward, color: AppColors.muted, size: 14),
            ],
          ),
        ),
      );
}
