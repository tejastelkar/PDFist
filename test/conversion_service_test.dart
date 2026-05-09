// ignore_for_file: avoid_print

import 'dart:io';
// dart:ui needed for Rect in syncfusion calls.
// ignore: unnecessary_import
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:pdfist/services/conversion_service.dart';

// ─── Path-provider mock ───────────────────────────────────────────────────────

class _FakePP extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String basePath;
  _FakePP(this.basePath);
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Creates a multi-page PDF with headings and body text; returns its path.
String _richPdf(Directory dir, {String tag = 'rich'}) {
  final doc = PdfDocument();
  doc.pageSettings.size = PdfPageSize.a4;
  doc.pageSettings.margins.all = 0;

  // Page 1 — heading + body
  final headFont = PdfStandardFont(PdfFontFamily.helvetica, 24,
      style: PdfFontStyle.bold);
  final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 12);
  final brush = PdfSolidBrush(PdfColor(0, 0, 0));
  final page1 = doc.pages.add();
  page1.graphics.drawString('Annual Report 2025',
      headFont, brush: brush,
      bounds: const Rect.fromLTWH(40, 40, 500, 32));
  page1.graphics.drawString(
      'This document summarises the financial performance of PDFist Ltd. '
      'Revenue grew by 42 percent year-on-year to reach 3.8 million dollars. '
      'Operating profit improved to 1.2 million dollars.',
      bodyFont, brush: brush,
      bounds: const Rect.fromLTWH(40, 90, 500, 120));

  // Page 2 — second heading + table-like text
  final sec = doc.sections!.add();
  sec.pageSettings.size = PdfPageSize.a4;
  sec.pageSettings.margins.all = 0;
  final page2 = sec.pages.add();
  page2.graphics.drawString('Quarterly Breakdown',
      headFont, brush: brush,
      bounds: const Rect.fromLTWH(40, 40, 500, 32));
  final tableData = [
    'Q1   Revenue: 820,000   Profit: 240,000',
    'Q2   Revenue: 910,000   Profit: 290,000',
    'Q3   Revenue: 1,010,000 Profit: 330,000',
    'Q4   Revenue: 1,060,000 Profit: 340,000',
  ];
  for (int i = 0; i < tableData.length; i++) {
    page2.graphics.drawString(tableData[i], bodyFont, brush: brush,
        bounds: Rect.fromLTWH(40, 90 + i * 20.0, 500, 18));
  }

  final bytes = doc.saveSync();
  doc.dispose();
  final path = '${dir.path}/${tag}_rich.pdf';
  File(path).writeAsBytesSync(bytes);
  return path;
}

bool _isZip(String path) {
  // ZIP files start with PK signature: 0x50 0x4B
  final bytes = File(path).readAsBytesSync();
  return bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B;
}

void main() {
  late Directory tempDir;
  late String richPdfPath;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('pdfist_conv_');
    await Directory('${tempDir.path}/PDFist/Output').create(recursive: true);
    PathProviderPlatform.instance = _FakePP(tempDir.path);
    richPdfPath = _richPdf(tempDir);
  });

  tearDownAll(() => tempDir.delete(recursive: true));

  // ── PDF → Word ──────────────────────────────────────────────────────────────

  test('pdfToWord — produces valid .docx ZIP', () async {
    final result = await ConversionService.pdfToWord(richPdfPath);

    print('[pdfToWord] success=${result.success} '
        'size=${result.outputSize}B pages=${result.pageCount} '
        'err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, endsWith('.docx'));
    expect(File(result.outputPath!).existsSync(), isTrue);
    // A .docx is a ZIP — verify PK header.
    expect(_isZip(result.outputPath!), isTrue,
        reason: 'Output is not a valid ZIP/DOCX');
    expect(result.outputSize, greaterThan(500));
    expect(result.pageCount, equals(2));
    print('[pdfToWord] ✓ ${result.outputSize} bytes — valid DOCX');
  });

  test('pdfToWord — document.xml contains expected text', () async {
    final result = await ConversionService.pdfToWord(richPdfPath);
    expect(result.success, isTrue, reason: result.error);

    // Unzip and check document.xml for content.
    final zipBytes = File(result.outputPath!).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final docXmlFile = archive.findFile('word/document.xml');
    expect(docXmlFile, isNotNull, reason: 'word/document.xml missing from ZIP');

    final docXml = String.fromCharCodes(docXmlFile!.content as List<int>);
    expect(docXml, contains('Annual Report'));
    expect(docXml, contains('Quarterly'));
    expect(docXml, contains('Revenue'));
    print('[pdfToWord] ✓ word/document.xml contains expected headings and body text');
  });

  test('pdfToWord — styles.xml and settings.xml are present', () async {
    final result = await ConversionService.pdfToWord(richPdfPath);
    final archive = ZipDecoder().decodeBytes(File(result.outputPath!).readAsBytesSync());
    expect(archive.findFile('word/styles.xml'), isNotNull);
    expect(archive.findFile('word/settings.xml'), isNotNull);
    expect(archive.findFile('[Content_Types].xml'), isNotNull);
    expect(archive.findFile('_rels/.rels'), isNotNull);
    print('[pdfToWord] ✓ all required DOCX parts present');
  });

  // ── PDF → Excel ─────────────────────────────────────────────────────────────

  test('pdfToExcel — produces valid .xlsx ZIP', () async {
    final result = await ConversionService.pdfToExcel(richPdfPath);

    print('[pdfToExcel] success=${result.success} '
        'size=${result.outputSize}B err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, endsWith('.xlsx'));
    expect(_isZip(result.outputPath!), isTrue,
        reason: 'Output is not a valid ZIP/XLSX');
    expect(result.outputSize, greaterThan(300));
    print('[pdfToExcel] ✓ ${result.outputSize} bytes — valid XLSX');
  });

  test('pdfToExcel — workbook.xml has correct sheet count', () async {
    final result = await ConversionService.pdfToExcel(richPdfPath);
    final archive = ZipDecoder().decodeBytes(File(result.outputPath!).readAsBytesSync());

    final workbook = archive.findFile('xl/workbook.xml');
    expect(workbook, isNotNull);
    final xml = String.fromCharCodes(workbook!.content as List<int>);
    expect(xml, contains('Page 1'));
    expect(xml, contains('Page 2'));

    final sheet1 = archive.findFile('xl/worksheets/sheet1.xml');
    final sheet2 = archive.findFile('xl/worksheets/sheet2.xml');
    expect(sheet1, isNotNull, reason: 'sheet1.xml missing');
    expect(sheet2, isNotNull, reason: 'sheet2.xml missing');

    final sharedStrings = archive.findFile('xl/sharedStrings.xml');
    final ssXml = String.fromCharCodes(sharedStrings!.content as List<int>);
    expect(ssXml, contains('Revenue'));
    print('[pdfToExcel] ✓ workbook has 2 sheets; sharedStrings contains "Revenue"');
  });

  // ── PDF → HTML ──────────────────────────────────────────────────────────────

  test('pdfToHtml — produces valid HTML file', () async {
    final result = await ConversionService.pdfToHtml(richPdfPath);

    print('[pdfToHtml] success=${result.success} '
        'size=${result.outputSize}B err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, endsWith('.html'));
    expect(File(result.outputPath!).existsSync(), isTrue);
    expect(result.outputSize, greaterThan(100));

    final html = File(result.outputPath!).readAsStringSync();
    expect(html, startsWith('<!DOCTYPE html>'));
    expect(html, contains('<h1>'));
    expect(html, contains('Annual Report'));
    expect(html, contains('Quarterly'));
    expect(html, contains('Page 1'));
    expect(html, contains('Page 2'));
    print('[pdfToHtml] ✓ valid HTML with h1 headings and page divs');
  });

  // ── PDF → Markdown ───────────────────────────────────────────────────────────

  test('pdfToMarkdown — produces valid Markdown file', () async {
    final result = await ConversionService.pdfToMarkdown(richPdfPath);

    print('[pdfToMarkdown] success=${result.success} '
        'size=${result.outputSize}B err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, endsWith('.md'));
    expect(File(result.outputPath!).existsSync(), isTrue);

    final md = File(result.outputPath!).readAsStringSync();
    expect(md, contains('# '));         // H1 from filename
    expect(md, contains('Annual Report'));
    expect(md, contains('Page 1'));
    expect(md, contains('Page 2'));
    expect(md, contains('---'));        // page separator
    print('[pdfToMarkdown] ✓ valid Markdown with headings and separators');
  });

  // ── PDF → Excel column detection ────────────────────────────────────────────

  test('pdfToExcel — multi-column data lands in correct columns (not just A)', () async {
    // Build a PDF whose page 1 has text positioned in 3 clear columns.
    final doc = PdfDocument();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    final page = doc.pages.add();
    // Row 1 header (y=40)
    page.graphics.drawString('Item',     font, brush: brush, bounds: const Rect.fromLTWH(40,  40, 100, 14));
    page.graphics.drawString('Qty',      font, brush: brush, bounds: const Rect.fromLTWH(200, 40, 100, 14));
    page.graphics.drawString('Price',    font, brush: brush, bounds: const Rect.fromLTWH(350, 40, 100, 14));
    // Row 2 data (y=60)
    page.graphics.drawString('Widget A', font, brush: brush, bounds: const Rect.fromLTWH(40,  60, 100, 14));
    page.graphics.drawString('10',       font, brush: brush, bounds: const Rect.fromLTWH(200, 60, 100, 14));
    page.graphics.drawString('9.99',     font, brush: brush, bounds: const Rect.fromLTWH(350, 60, 100, 14));
    // Row 3 data (y=80)
    page.graphics.drawString('Widget B', font, brush: brush, bounds: const Rect.fromLTWH(40,  80, 100, 14));
    page.graphics.drawString('5',        font, brush: brush, bounds: const Rect.fromLTWH(200, 80, 100, 14));
    page.graphics.drawString('19.99',    font, brush: brush, bounds: const Rect.fromLTWH(350, 80, 100, 14));
    final pdfPath = '${tempDir.path}/multicol.pdf';
    File(pdfPath).writeAsBytesSync(doc.saveSync());
    doc.dispose();

    final result = await ConversionService.pdfToExcel(pdfPath);
    expect(result.success, isTrue, reason: result.error);

    // Parse the xlsx and check columns.
    final archive = ZipDecoder().decodeBytes(File(result.outputPath!).readAsBytesSync());
    final sheet1 = archive.findFile('xl/worksheets/sheet1.xml');
    expect(sheet1, isNotNull);
    final sheetXml = String.fromCharCodes(sheet1!.content as List<int>);

    print('[pdfToExcel-cols] sheet1.xml snippet: ${sheetXml.substring(0, sheetXml.length.clamp(0, 400))}');

    // Headers should be in A1, B1, C1 — NOT all in A.
    expect(sheetXml, contains('A1'), reason: 'Item header missing in A1');
    expect(sheetXml, contains('B1'), reason: 'Qty header missing in B1 — still dumping into column A only');
    expect(sheetXml, contains('C1'), reason: 'Price header missing in C1');

    final ssFile = archive.findFile('xl/sharedStrings.xml');
    final ssXml = String.fromCharCodes(ssFile!.content as List<int>);
    expect(ssXml, contains('Item'));
    expect(ssXml, contains('Qty'));
    expect(ssXml, contains('Price'));
    expect(ssXml, contains('Widget A'));
    expect(ssXml, contains('9.99'));
    print('[pdfToExcel-cols] ✓ multi-column data in correct A/B/C columns');
  });

  // ── Edge case: single-page PDF ───────────────────────────────────────────────

  test('pdfToWord — single-page PDF has no page-break element', () async {
    final doc = PdfDocument();
    doc.pageSettings.size = PdfPageSize.a4;
    final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
    doc.pages.add().graphics.drawString('Only page.',
        font, brush: PdfSolidBrush(PdfColor(0, 0, 0)),
        bounds: const Rect.fromLTWH(40, 40, 400, 20));
    final path = '${tempDir.path}/single_page.pdf';
    File(path).writeAsBytesSync(doc.saveSync());
    doc.dispose();

    final result = await ConversionService.pdfToWord(path);
    expect(result.success, isTrue, reason: result.error);

    final archive = ZipDecoder()
        .decodeBytes(File(result.outputPath!).readAsBytesSync());
    final xml = String.fromCharCodes(
        archive.findFile('word/document.xml')!.content as List<int>);

    // Single-page doc must NOT have a page break.
    expect(xml, isNot(contains('w:type="page"')));
    expect(xml, contains('Only page.'));
    print('[pdfToWord-single] ✓ no spurious page break; text present');
  });

  // ── Verify all four share the same result shape ───────────────────────────────

  test('all converters return consistent PdfResult shape', () async {
    final results = await Future.wait([
      ConversionService.pdfToWord(richPdfPath),
      ConversionService.pdfToExcel(richPdfPath),
      ConversionService.pdfToHtml(richPdfPath),
      ConversionService.pdfToMarkdown(richPdfPath),
    ]);

    for (final r in results) {
      expect(r.success, isTrue, reason: r.error);
      expect(r.outputPath, isNotNull);
      expect(r.outputSize, greaterThan(0));
      expect(r.pageCount, equals(2));
      expect(r.inputSize, greaterThan(0));
      expect(File(r.outputPath!).existsSync(), isTrue);
    }

    print('[all-converters] Word=${results[0].outputSize}B '
        'Excel=${results[1].outputSize}B '
        'HTML=${results[2].outputSize}B '
        'MD=${results[3].outputSize}B');
  });
}
