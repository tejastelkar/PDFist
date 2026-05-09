import 'package:flutter/widgets.dart';

class ToolCategory {
  final String id;
  final String label;
  final List<PdfTool> tools;
  const ToolCategory({required this.id, required this.label, required this.tools});
}

class PdfTool {
  final String id;
  final String label;
  final String desc;
  final IconData? iconData;
  final String num;
  final String category;
  final String categoryId;

  const PdfTool({
    required this.id,
    required this.label,
    required this.desc,
    this.iconData,
    required this.num,
    required this.category,
    required this.categoryId,
  });
}

class HistoryItem {
  final String id;
  final String name;
  final String tool;
  final String time;
  final String size;

  const HistoryItem({
    required this.id,
    required this.name,
    required this.tool,
    required this.time,
    required this.size,
  });
}

const kHistoryItems = [
  HistoryItem(id: 'h1', name: 'Quarterly_Report_Q1.pdf', tool: 'Compress', time: 'Just now', size: '840 KB'),
  HistoryItem(id: 'h2', name: 'Lease_Agreement.pdf', tool: 'Protect', time: '1h ago', size: '1.1 MB'),
  HistoryItem(id: 'h3', name: 'Invoice_8821.pdf', tool: 'Merge', time: '3h ago', size: '420 KB'),
  HistoryItem(id: 'h4', name: 'Scan_2026_05_07.pdf', tool: 'Rotate', time: 'Yesterday', size: '6.8 MB'),
  HistoryItem(id: 'h5', name: 'Tax_Returns_2025.pdf', tool: 'Split', time: 'Yesterday', size: '3.2 MB'),
  HistoryItem(id: 'h6', name: 'Contract_Final.pdf', tool: 'Watermark', time: '2 days ago', size: '1.7 MB'),
  HistoryItem(id: 'h7', name: 'Resume_Alex_K.pdf', tool: 'Convert', time: '3 days ago', size: '180 KB'),
];

const kRecentItems = [
  HistoryItem(id: 'r1', name: 'Quarterly_Report_Q1.pdf', tool: 'Compress', time: '2m', size: '2.4 MB → 840 KB'),
  HistoryItem(id: 'r2', name: 'Lease_Agreement.pdf', tool: 'Protect', time: '1h', size: '1.1 MB'),
  HistoryItem(id: 'r3', name: 'Invoice_8821.pdf', tool: 'Merge', time: '3h', size: '420 KB'),
  HistoryItem(id: 'r4', name: 'Scan_2026_05_07.pdf', tool: 'Rotate', time: '1d', size: '6.8 MB'),
];
