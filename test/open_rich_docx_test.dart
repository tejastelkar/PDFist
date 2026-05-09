// ignore_for_file: avoid_print
// Run: flutter test test/open_rich_docx_test.dart --reporter=expanded

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

// ─── Image generators ─────────────────────────────────────────────────────────

/// Generates a bar-chart PNG. Returns raw PNG bytes.
Uint8List _makeBarChart() {
  final image = img.Image(width: 500, height: 280);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  // Grid lines.
  for (int y = 40; y <= 220; y += 36) {
    img.drawLine(image,
        x1: 60, y1: y, x2: 480, y2: y,
        color: img.ColorRgb8(220, 220, 220));
  }

  // Bars (Q1–Q4).
  final data = [
    ('Q1', 0.55, img.ColorRgb8(30, 30, 30)),
    ('Q2', 0.72, img.ColorRgb8(60, 60, 60)),
    ('Q3', 0.88, img.ColorRgb8(90, 90, 90)),
    ('Q4', 1.00, img.ColorRgb8(20, 20, 20)),
  ];
  final barW = 60;
  final gap = 30;
  final baseY = 220;
  final maxH = 180;
  for (int i = 0; i < data.length; i++) {
    final (label, ratio, color) = data[i];
    final x0 = 70 + i * (barW + gap);
    final barH = (maxH * ratio).round();
    img.fillRect(image,
        x1: x0, y1: baseY - barH, x2: x0 + barW, y2: baseY,
        color: color);
    // Label below bar.
    img.drawString(image, label,
        font: img.arial14,
        x: x0 + 14, y: baseY + 6,
        color: img.ColorRgb8(50, 50, 50));
  }

  // Axes.
  img.drawLine(image, x1: 60, y1: 40, x2: 60, y2: 220,
      color: img.ColorRgb8(0, 0, 0), thickness: 2);
  img.drawLine(image, x1: 60, y1: 220, x2: 480, y2: 220,
      color: img.ColorRgb8(0, 0, 0), thickness: 2);

  // Title.
  img.drawString(image, 'Quarterly Revenue (USD thousands)',
      font: img.arial14,
      x: 80, y: 10,
      color: img.ColorRgb8(0, 0, 0));

  return Uint8List.fromList(img.encodePng(image));
}

/// Generates a simple pie-chart-style donut PNG.
Uint8List _makePieChart() {
  final image = img.Image(width: 400, height: 300);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  // Draw filled circles for each segment (simplified pie).
  final cx = 150, cy = 150, r = 110;
  img.fillCircle(image, x: cx, y: cy, radius: r,
      color: img.ColorRgb8(30, 30, 30));
  // "Cut" segments with lighter colours.
  img.fillCircle(image, x: cx + 20, y: cy - 30, radius: 60,
      color: img.ColorRgb8(100, 100, 100));
  img.fillCircle(image, x: cx - 40, y: cy + 30, radius: 50,
      color: img.ColorRgb8(160, 160, 160));
  // Donut hole.
  img.fillCircle(image, x: cx, y: cy, radius: 45,
      color: img.ColorRgb8(255, 255, 255));

  // Legend.
  final legendItems = [
    ('Product A  45%', img.ColorRgb8(30, 30, 30)),
    ('Product B  32%', img.ColorRgb8(100, 100, 100)),
    ('Product C  23%', img.ColorRgb8(160, 160, 160)),
  ];
  for (int i = 0; i < legendItems.length; i++) {
    final (text, color) = legendItems[i];
    img.fillRect(image,
        x1: 290, y1: 80 + i * 30, x2: 310, y2: 95 + i * 30,
        color: color);
    img.drawString(image, text,
        font: img.arial14,
        x: 318, y: 80 + i * 30,
        color: img.ColorRgb8(0, 0, 0));
  }
  img.drawString(image, 'Revenue Split by Product',
      font: img.arial14,
      x: 20, y: 10,
      color: img.ColorRgb8(0, 0, 0));

  return Uint8List.fromList(img.encodePng(image));
}

// ─── PDF builder ──────────────────────────────────────────────────────────────

String _buildRichPdf(String outDir) {
  final doc = PdfDocument();
  doc.pageSettings.size = PdfPageSize.a4;
  doc.pageSettings.margins.all = 40;

  final W = doc.pageSettings.size.width - 80; // usable width

  // Fonts.
  final titleF  = PdfStandardFont(PdfFontFamily.helvetica, 26, style: PdfFontStyle.bold);
  final h2F     = PdfStandardFont(PdfFontFamily.helvetica, 16, style: PdfFontStyle.bold);
  final h3F     = PdfStandardFont(PdfFontFamily.helvetica, 13, style: PdfFontStyle.bold);
  final bodyF   = PdfStandardFont(PdfFontFamily.helvetica, 11);
  final captionF = PdfStandardFont(PdfFontFamily.helvetica, 9);

  // Brushes.
  final black  = PdfSolidBrush(PdfColor(0, 0, 0));
  final white  = PdfSolidBrush(PdfColor(255, 255, 255));
  final dark   = PdfSolidBrush(PdfColor(30, 30, 30));
  final grey   = PdfSolidBrush(PdfColor(120, 120, 120));
  final lightBg = PdfSolidBrush(PdfColor(245, 245, 245));

  // Pens.
  final thinPen   = PdfPen(PdfColor(200, 200, 200), width: 0.5);

  // ── Page 1: Title + intro + Feature comparison table + bar-chart image ──────
  final p1 = doc.pages.add();
  double y = 0;

  // Title block.
  p1.graphics.drawRectangle(
      brush: dark,
      bounds: Rect.fromLTWH(0, y, W, 56));
  p1.graphics.drawString('PDFist — Technical Report 2025',
      titleF, brush: white,
      bounds: Rect.fromLTWH(14, y + 12, W - 28, 36));
  y += 66;

  p1.graphics.drawString(
      'Prepared by the PDFist engineering team. All figures are Q4 2025.',
      bodyF, brush: grey,
      bounds: Rect.fromLTWH(0, y, W, 16));
  y += 26;

  p1.graphics.drawLine(thinPen, Offset(0, y), Offset(W, y));
  y += 14;

  // Section 1 heading.
  p1.graphics.drawString('1. Feature Comparison', h2F, brush: black,
      bounds: Rect.fromLTWH(0, y, W, 22));
  y += 30;

  // Feature comparison table (4 columns, 6 rows including header).
  final featTable = PdfGrid();
  featTable.columns.add(count: 4);
  featTable.columns[0].width = W * 0.34;
  featTable.columns[1].width = W * 0.22;
  featTable.columns[2].width = W * 0.22;
  featTable.columns[3].width = W * 0.22;

  featTable.style = PdfGridStyle(
    cellPadding: PdfPaddings(left: 8, right: 8, top: 5, bottom: 5),
  );

  // Header row.
  featTable.headers.add(1);
  final hdr = featTable.headers[0];
  for (final (i, txt) in [
    (0, 'Feature'), (1, 'Starter'), (2, 'Pro'), (3, 'Enterprise')
  ]) {
    hdr.cells[i].value = txt;
    hdr.cells[i].style = PdfGridCellStyle(
      backgroundBrush: dark,
      textBrush: white,
      font: PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
    );
    hdr.cells[i].stringFormat =
        PdfStringFormat(alignment: PdfTextAlignment.center);
  }

  // Data rows.
  final featData = [
    ['Merge & Split',       'Yes', 'Yes', 'Yes'],
    ['Password Protection', 'Yes', 'Yes', 'Yes'],
    ['OCR (text search)',   'No',  'Yes', 'Yes'],
    ['Watermark & Stamp',   'No',  'Yes', 'Yes'],
    ['Batch Processing',    'No',  'No',  'Yes'],
  ];
  for (int ri = 0; ri < featData.length; ri++) {
    final row = featTable.rows.add();
    for (int ci = 0; ci < 4; ci++) {
      row.cells[ci].value = featData[ri][ci];
      row.cells[ci].stringFormat =
          PdfStringFormat(alignment: ci == 0 ? PdfTextAlignment.left : PdfTextAlignment.center);
      if (ri % 2 == 1) {
        row.cells[ci].style =
            PdfGridCellStyle(backgroundBrush: lightBg);
      }
    }
  }

  final featLayout = featTable.draw(
      page: p1,
      bounds: Rect.fromLTWH(0, y, W, 0))!;
  y += featLayout.bounds.height + 20;

  // Bar chart image.
  p1.graphics.drawString('2. Quarterly Revenue', h2F, brush: black,
      bounds: Rect.fromLTWH(0, y, W, 22));
  y += 28;

  final barBytes = _makeBarChart();
  final barBitmap = PdfBitmap(barBytes);
  const chartW = 360.0;
  const chartH = 200.0;
  p1.graphics.drawImage(barBitmap, Rect.fromLTWH(0, y, chartW, chartH));
  y += chartH + 6;
  p1.graphics.drawString(
      'Figure 1 — Bar chart showing Q1–Q4 2025 revenue (USD thousands)',
      captionF, brush: grey,
      bounds: Rect.fromLTWH(0, y, chartW, 14));

  // ── Page 2: Financial data table + team directory table + pie chart ──────────
  final sec2 = doc.sections!.add();
  sec2.pageSettings.size = PdfPageSize.a4;
  sec2.pageSettings.margins.all = 40;
  final p2 = sec2.pages.add();
  y = 0;

  p2.graphics.drawString('3. Financial Summary', h2F, brush: black,
      bounds: Rect.fromLTWH(0, y, W, 22));
  y += 30;

  // 5-column financial table.
  final finTable = PdfGrid();
  finTable.columns.add(count: 5);
  finTable.columns[0].width = W * 0.14;
  finTable.columns[1].width = W * 0.22;
  finTable.columns[2].width = W * 0.22;
  finTable.columns[3].width = W * 0.22;
  finTable.columns[4].width = W * 0.20;
  finTable.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 7, right: 7, top: 5, bottom: 5));

  finTable.headers.add(1);
  final finHdr = finTable.headers[0];
  for (final (i, t) in [
    (0, 'Quarter'), (1, 'Revenue'), (2, 'Expenses'),
    (3, 'Net Profit'), (4, 'Margin')
  ]) {
    finHdr.cells[i].value = t;
    finHdr.cells[i].style = PdfGridCellStyle(
      backgroundBrush: dark,
      textBrush: white,
      font: PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
    );
    finHdr.cells[i].stringFormat =
        PdfStringFormat(alignment: PdfTextAlignment.center);
  }

  final finData = [
    ['Q1 2025', '\$820,000',  '\$540,000', '\$280,000', '34.1%'],
    ['Q2 2025', '\$910,000',  '\$570,000', '\$340,000', '37.4%'],
    ['Q3 2025', '\$1,010,000','\$620,000', '\$390,000', '38.6%'],
    ['Q4 2025', '\$1,060,000','\$640,000', '\$420,000', '39.6%'],
    ['Total',   '\$3,800,000','\$2,370,000','\$1,430,000','37.6%'],
  ];

  for (int ri = 0; ri < finData.length; ri++) {
    final row = finTable.rows.add();
    final isTotal = ri == finData.length - 1;
    for (int ci = 0; ci < 5; ci++) {
      row.cells[ci].value = finData[ri][ci];
      row.cells[ci].stringFormat =
          PdfStringFormat(alignment: ci == 0 ? PdfTextAlignment.center : PdfTextAlignment.right);
      if (isTotal) {
        row.cells[ci].style = PdfGridCellStyle(
          backgroundBrush: PdfSolidBrush(PdfColor(220, 220, 220)),
          font: PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
        );
      } else if (ri % 2 == 1) {
        row.cells[ci].style = PdfGridCellStyle(backgroundBrush: lightBg);
      }
    }
  }
  final finLayout = finTable.draw(
      page: p2, bounds: Rect.fromLTWH(0, y, W, 0))!;
  y += finLayout.bounds.height + 24;

  // Pie chart on right, team intro on left.
  p2.graphics.drawString('4. Revenue by Product', h2F, brush: black,
      bounds: Rect.fromLTWH(0, y, W, 22));
  y += 28;

  final pieBytes = _makePieChart();
  final pieBitmap = PdfBitmap(pieBytes);
  const pieW = 260.0, pieH = 195.0;
  p2.graphics.drawImage(pieBitmap, Rect.fromLTWH(W - pieW, y, pieW, pieH));

  // Mini text beside chart.
  p2.graphics.drawString(
      'Product A leads with 45% of total\nrevenue, driven by enterprise\nclient growth in H2 2025.\n\n'
      'Product C grew 18% YoY despite\nbeing the smallest segment.',
      bodyF, brush: black,
      bounds: Rect.fromLTWH(0, y + 10, W - pieW - 16, 160));

  p2.graphics.drawString(
      'Figure 2 — Revenue share by product line (Q4 2025)',
      captionF, brush: grey,
      bounds: Rect.fromLTWH(W - pieW, y + pieH + 4, pieW, 14));
  y += pieH + 30;

  // ── Page 3: Team directory (complex table) + notes ───────────────────────────
  final sec3 = doc.sections!.add();
  sec3.pageSettings.size = PdfPageSize.a4;
  sec3.pageSettings.margins.all = 40;
  final p3 = sec3.pages.add();
  y = 0;

  p3.graphics.drawString('5. Team Directory', h2F, brush: black,
      bounds: Rect.fromLTWH(0, y, W, 22));
  y += 30;

  // Team table — 6 columns, merged-concept header groups drawn manually.
  // Header group labels.
  final grpLabels = [
    Rect.fromLTWH(0,       y, W * 0.40, 18), 'Identity',
    Rect.fromLTWH(W * 0.40, y, W * 0.35, 18), 'Assignment',
    Rect.fromLTWH(W * 0.75, y, W * 0.25, 18), 'Status',
  ];
  for (int k = 0; k < grpLabels.length; k += 2) {
    final rect = grpLabels[k] as Rect;
    final lbl  = grpLabels[k + 1] as String;
    p3.graphics.drawRectangle(brush: dark, bounds: rect);
    p3.graphics.drawString(lbl, h3F, brush: white,
        bounds: Rect.fromLTRB(rect.left + 6, rect.top + 2, rect.right - 6, rect.bottom - 2),
        format: PdfStringFormat(alignment: PdfTextAlignment.center));
  }
  y += 20;

  // Sub-header row.
  final teamTable = PdfGrid();
  teamTable.columns.add(count: 6);
  teamTable.columns[0].width = W * 0.20;
  teamTable.columns[1].width = W * 0.20;
  teamTable.columns[2].width = W * 0.20;
  teamTable.columns[3].width = W * 0.15;
  teamTable.columns[4].width = W * 0.12;
  teamTable.columns[5].width = W * 0.13;
  teamTable.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 6, right: 6, top: 4, bottom: 4));

  teamTable.headers.add(1);
  final tHdr = teamTable.headers[0];
  for (final (i, t) in [
    (0,'Name'), (1,'Role'), (2,'Email'), (3,'Location'), (4,'Since'), (5,'Status')
  ]) {
    tHdr.cells[i].value = t;
    tHdr.cells[i].style = PdfGridCellStyle(
      backgroundBrush: PdfSolidBrush(PdfColor(60, 60, 60)),
      textBrush: white,
      font: PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold),
    );
  }

  final teamData = [
    ['Alice Chen',     'CEO',              'a.chen@pdfist.io',  'San Francisco', '2021', 'Active'],
    ['Bob Ramirez',    'CTO',              'b.ramirez@pdfist.io','Austin',       '2021', 'Active'],
    ['Clara Osei',     'Lead Engineer',    'c.osei@pdfist.io',  'London',        '2022', 'Active'],
    ['David Park',     'Product Manager',  'd.park@pdfist.io',  'Seoul',         '2022', 'Active'],
    ['Eva Müller',     'UX Designer',      'e.muller@pdfist.io','Berlin',        '2023', 'Active'],
    ['Frank Nguyen',   'Backend Engineer', 'f.nguyen@pdfist.io','Ho Chi Minh',   '2023', 'Active'],
    ['Grace Okonkwo',  'QA Engineer',      'g.okonkwo@pdfist.io','Lagos',        '2024', 'Active'],
    ['Henry Li',       'DevOps',           'h.li@pdfist.io',    'Singapore',     '2024', 'On Leave'],
  ];

  for (int ri = 0; ri < teamData.length; ri++) {
    final row = teamTable.rows.add();
    for (int ci = 0; ci < 6; ci++) {
      row.cells[ci].value = teamData[ri][ci];
      if (ri % 2 == 1) {
        row.cells[ci].style = PdfGridCellStyle(backgroundBrush: lightBg);
      }
      // Highlight "On Leave" in status column.
      if (ci == 5 && teamData[ri][ci] == 'On Leave') {
        row.cells[ci].style = PdfGridCellStyle(
          backgroundBrush: PdfSolidBrush(PdfColor(255, 230, 180)),
          font: PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.italic),
        );
      }
    }
  }
  final teamLayout = teamTable.draw(
      page: p3, bounds: Rect.fromLTWH(0, y, W, 0))!;
  y += teamLayout.bounds.height + 24;

  p3.graphics.drawLine(thinPen, Offset(0, y), Offset(W, y));
  y += 12;

  // Two-column notes layout (simulated).
  p3.graphics.drawString('6. Notes', h2F, brush: black,
      bounds: Rect.fromLTWH(0, y, W, 22));
  y += 30;

  final col1 = W / 2 - 8;
  final col2X = W / 2 + 8;
  final col2 = W / 2 - 8;

  p3.graphics.drawString('Data Privacy',
      h3F, brush: black, bounds: Rect.fromLTWH(0, y, col1, 16));
  p3.graphics.drawString('Version History',
      h3F, brush: black, bounds: Rect.fromLTWH(col2X, y, col2, 16));
  y += 22;
  p3.graphics.drawString(
      'All PDF processing is performed on-device. No document bytes '
      'are transmitted to any server. Firebase Auth is used only for '
      'account identity — no file content ever leaves the device.',
      bodyF, brush: black,
      bounds: Rect.fromLTWH(0, y, col1, 80));
  p3.graphics.drawString(
      'v1.0.0 — Initial release (May 2025)\n'
      'v1.1.0 — Added OCR support\n'
      'v1.2.0 — PDF→Word/Excel converters\n'
      'v1.3.0 — Firebase integration',
      bodyF, brush: black,
      bounds: Rect.fromLTWH(col2X, y, col2, 80));
  y += 90;

  // Footer.
  p3.graphics.drawLine(thinPen, Offset(0, y), Offset(W, y));
  y += 8;
  p3.graphics.drawString(
      'CONFIDENTIAL — PDFist Ltd. 2025 — All rights reserved',
      captionF, brush: grey,
      bounds: Rect.fromLTWH(0, y, W, 14),
      format: PdfStringFormat(alignment: PdfTextAlignment.center));

  // Save.
  final pdfPath = '$outDir/PDFist_report.pdf';
  File(pdfPath).writeAsBytesSync(doc.saveSync());
  doc.dispose();
  return pdfPath;
}

// ─── Test ─────────────────────────────────────────────────────────────────────

void main() {
  test('Build rich 3-page PDF (tables + images) and convert to Word',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final desktop = '/Users/tejastelkar/Desktop';
    final outDir = Directory('$desktop/PDFist_preview');
    await outDir.create(recursive: true);
    await Directory('${outDir.path}/PDFist/Output').create(recursive: true);
    PathProviderPlatform.instance = _FakePP(outDir.path);

    // ── Build the rich PDF ───────────────────────────────────────────────────
    print('\nBuilding rich 3-page PDF with tables + images…');
    final pdfPath = _buildRichPdf(outDir.path);
    final pdfSize = File(pdfPath).lengthSync();
    print('📄 PDF saved → $pdfPath  ($pdfSize bytes, 3 pages)');

    // ── Convert to Word (table detection, no pdfrx — works in test env) ────────
    print('Converting to Word with table detection…');
    final result = await ConversionService.pdfToWordWithTables(pdfPath);

    expect(result.success, isTrue, reason: result.error);
    print('📝 Word saved → ${result.outputPath}');
    print('   Input PDF : $pdfSize bytes');
    print('   Output DOCX: ${result.outputSize} bytes');
    print('   Pages     : ${result.pageCount}');
    print('   Time      : ${result.processingTimeMs}ms');

    // ── Validate ZIP structure ───────────────────────────────────────────────
    final docxBytes = File(result.outputPath!).readAsBytesSync();
    expect(docxBytes[0], equals(0x50), reason: 'Not a ZIP (no PK signature)');
    expect(docxBytes[1], equals(0x4B));
    print('✓ Valid ZIP/DOCX signature');

    // ── Open both files ──────────────────────────────────────────────────────
    print('\nOpening both files…');
    await Process.run('open', [pdfPath]);
    await Future.delayed(const Duration(milliseconds: 600));
    await Process.run('open', [result.outputPath!]);

    print('\n✅ Both open. Compare side by side:');
    print('   • Tables → proper Word [w:tbl] with dark header rows + alternating shading');
    print('   • Section headings → Heading 1 / Heading 2 Word styles');
    print('   • Body text → Calibri 11pt');
    print('   Note: images show in PDF only — on-device (Android) pdfToWordRich() embeds them');
    print('\nFiles in: ${outDir.path}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
