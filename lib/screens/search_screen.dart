import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';
import '../models/tool_catalog.dart';
import '../models/tool_model.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  List<PdfTool> get _results => _query.trim().isEmpty
      ? []
      : kTools.where((t) =>
          t.label.toLowerCase().contains(_query.toLowerCase()) ||
          t.category.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.text, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      style: AppTextStyles.display(22, weight: FontWeight.w600),
                      cursorColor: AppColors.text,
                      decoration: InputDecoration(
                        hintText: 'Search tools…',
                        hintStyle: AppTextStyles.display(22, weight: FontWeight.w600)
                            .copyWith(color: AppColors.faint),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/home'),
                    child: Text('CANCEL', style: AppTextStyles.mono(11, color: AppColors.text.withValues(alpha: 0.7))),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.text, margin: const EdgeInsets.symmetric(horizontal: 20)),

            Expanded(
              child: _query.trim().isEmpty
                  ? _buildSuggestions()
                  : _results.isEmpty
                      ? _buildNoResults()
                      : _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Suggested'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Compress', 'Merge', 'Sign', 'Redact', 'OCR', 'Rotate', 'Watermark']
                  .map((s) => GestureDetector(
                        onTap: () => setState(() {
                          _query = s;
                          _controller.text = s;
                        }),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.text),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: Text(s, style: AppTextStyles.chip.copyWith(fontSize: 11)),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      );

  Widget _buildNoResults() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, color: AppColors.text, size: 64),
              const SizedBox(height: 20),
              const Eyebrow('No matches'),
              const SizedBox(height: 6),
              Text('Nothing here.', style: AppTextStyles.display(22, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Try a different word.', style: AppTextStyles.body(13, color: AppColors.muted)),
            ],
          ),
        ),
      );

  Widget _buildResults() => ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Eyebrow('${_results.length.toString().padLeft(2, '0')} results'),
          ),
          ...(_results.map((t) => _ResultRow(tool: t))),
        ],
      );
}

class _ResultRow extends StatelessWidget {
  final PdfTool tool;
  const _ResultRow({required this.tool});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.go('/tool/${tool.id}'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined, color: AppColors.text, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tool.label, style: AppTextStyles.body(14, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(tool.category.toUpperCase(),
                        style: AppTextStyles.mono(10, color: AppColors.muted)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, color: AppColors.muted, size: 16),
            ],
          ),
        ),
      );
}
