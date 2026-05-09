// ignore_for_file: avoid_print
//
// Smoke-tests every PdfService function against tool/demo.pdf.
// Run: flutter test test/demo_smoke_test.dart --reporter=expanded
//
// Each test prints:
//   INPUT  : filename | size | pages
//   OUTPUT : success | size | pages | error | extras
//
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:pdfist/services/pdf_service.dart';
import 'package:pdfist/models/pdf_models.dart';

// ─── Path-provider mock ───────────────────────────────────────────────────────
class _FakePP extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String basePath;
  _FakePP(this.basePath);
  @override
  Future<String?> getApplicationDocumentsPath() async => basePath;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
int _pages(String path) {
  final bytes = File(path).readAsBytesSync();
  final doc = PdfDocument(inputBytes: bytes);
  final c = doc.pages.count;
  doc.dispose();
  return c;
}

String _fmt(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${(bytes / 1048576).toStringAsFixed(1)}MB';
}

void _in(String tag, String path) {
  final sz = File(path).lengthSync();
  int pg = 0;
  try { pg = _pages(path); } catch (_) {}
  print('  [$tag] IN  : ${path.split(Platform.pathSeparator).last} | ${_fmt(sz)} | $pg pages');
}

void _out(String tag, PdfResult r) {
  final sz = r.outputPath != null ? _fmt(File(r.outputPath!).lengthSync()) : '—';
  final pg = r.pageCount != null ? '${r.pageCount}p' : '—';
  final ex = r.extras?.entries.map((e) => '${e.key}=${e.value}').join(', ') ?? '';
  final err = r.error != null ? ' | ERR: ${r.error}' : '';
  print('  [$tag] OUT : ok=${r.success} | $sz | $pg$err${ex.isNotEmpty ? " | $ex" : ""}');
}

// ─── Fixtures ─────────────────────────────────────────────────────────────────
String _make2Page(Directory dir) {
  final doc = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 16);
  final brush = PdfSolidBrush(PdfColor(0, 0, 0));
  for (int i = 0; i < 2; i++) {
    doc.pages.add().graphics.drawString('Second PDF - page ${i + 1}', font,
        brush: brush, bounds: const Rect.fromLTWH(40, 40, 400, 30));
  }
  final bytes = doc.saveSync();
  doc.dispose();
  final path = '${dir.path}/second.pdf';
  File(path).writeAsBytesSync(bytes);
  return path;
}

String _makeFormPdf(Directory dir) {
  final doc = PdfDocument();
  final page = doc.pages.add();
  page.graphics.drawString('Name:',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
      brush: PdfSolidBrush(PdfColor(0, 0, 0)),
      bounds: const Rect.fromLTWH(40, 40, 80, 20));
  final field = PdfTextBoxField(
      page, 'Name', const Rect.fromLTWH(130, 36, 200, 22));
  doc.form.fields.add(field);
  final bytes = doc.saveSync();
  doc.dispose();
  final path = '${dir.path}/form.pdf';
  File(path).writeAsBytesSync(bytes);
  return path;
}

String _makePng(Directory dir) {
  final image = img.Image(width: 80, height: 80);
  img.fill(image, color: img.ColorRgb8(100, 149, 237));
  final path = '${dir.path}/test_img.png';
  File(path).writeAsBytesSync(img.encodePng(image));
  return path;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
void main() {
  late Directory tempDir;
  late String demo;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('pdfdemo_');
    PathProviderPlatform.instance = _FakePP(tempDir.path);
    await Directory('${tempDir.path}/PDFist/Output').create(recursive: true);

    final src = File('tool/demo.pdf');
    expect(src.existsSync(), isTrue,
        reason: 'Run: python tool/create_demo.py first');
    demo = '${tempDir.path}/demo.pdf';
    await src.copy(demo);
    print('\n=== Demo PDF: ${_fmt(File(demo).lengthSync())} | ${_pages(demo)} pages ===\n');
  });

  tearDownAll(() => tempDir.delete(recursive: true));

  // ── 1. Compress ─────────────────────────────────────────────────────────────
  test('01 compress', () async {
    _in('compress', demo);
    final r = await PdfService.compressPdf(demo, 'medium');
    _out('compress', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 2. Rotate ───────────────────────────────────────────────────────────────
  test('02 rotate 90', () async {
    _in('rotate', demo);
    final r = await PdfService.rotatePdf(demo, 90);
    _out('rotate', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 3. Merge ────────────────────────────────────────────────────────────────
  test('03 merge', () async {
    final second = _make2Page(tempDir);
    _in('merge', demo);
    print('  [merge]     + second.pdf (2 pages)');
    final r = await PdfService.mergePdfs([demo, second]);
    _out('merge', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.pageCount, equals(6));
  });

  // ── 4. Split individual ─────────────────────────────────────────────────────
  test('04 split individual', () async {
    _in('split', demo);
    final r = await PdfService.splitPdf(demo, mode: 'individual');
    _out('split', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 5. Split byPageRange ────────────────────────────────────────────────────
  test('05 split byPageRange 2-3', () async {
    _in('split-range', demo);
    final r = await PdfService.splitPdf(demo, mode: 'byPageRange', start: 2, end: 3);
    _out('split-range', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.pageCount, equals(2));
  });

  // ── 6. Protect + Unlock ─────────────────────────────────────────────────────
  test('06 protect', () async {
    _in('protect', demo);
    final r = await PdfService.addPassword(demo, 'secret123', 'secret123');
    _out('protect', r);
    expect(r.success, isTrue, reason: r.error);
  });

  test('07 unlock', () async {
    // Re-protect inline so this test is independent.
    final rp = await PdfService.addPassword(demo, 'abc', 'abc');
    expect(rp.success, isTrue);
    _in('unlock', rp.outputPath!);
    final r = await PdfService.removePassword(rp.outputPath!, 'abc');
    _out('unlock', r);
    expect(r.success, isTrue, reason: r.error);
    // Unlocked file must open without a password.
    final bytes = File(r.outputPath!).readAsBytesSync();
    expect(() => PdfDocument(inputBytes: bytes), returnsNormally);
    print('  [unlock] verified: opens without password ✓');
  });

  // ── 7. Watermark ────────────────────────────────────────────────────────────
  test('08 watermark', () async {
    _in('watermark', demo);
    final r = await PdfService.addWatermark(
        demo, WatermarkConfig(text: 'DEMO', opacity: 0.3, fontSize: 60, rotation: -45));
    _out('watermark', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 8. Stamp ────────────────────────────────────────────────────────────────
  test('09 stamp draft', () async {
    _in('stamp', demo);
    final r = await PdfService.addStamp(demo, StampType.draft, 'center');
    _out('stamp', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 9. Page numbers ─────────────────────────────────────────────────────────
  test('10 page-numbers', () async {
    _in('page-numbers', demo);
    final r = await PdfService.addPageNumbers(demo, PageNumberConfig());
    _out('page-numbers', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 10. Header / Footer ─────────────────────────────────────────────────────
  test('11 header-footer', () async {
    _in('header-footer', demo);
    final r = await PdfService.addHeaderFooter(
        demo, HeaderFooterConfig(headerText: 'PDFist Demo', footerText: 'Page {page}'));
    _out('header-footer', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 11. Extract pages ───────────────────────────────────────────────────────
  test('12 extract-pages [0,2]', () async {
    _in('extract-pages', demo);
    final r = await PdfService.extractPages(demo, [0, 2]);
    _out('extract-pages', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.pageCount, equals(2));
  });

  // ── 12. Delete pages ────────────────────────────────────────────────────────
  test('13 delete-pages [1]', () async {
    _in('delete-pages', demo);
    final r = await PdfService.deletePages(demo, [1]);
    _out('delete-pages', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.pageCount, equals(3));
  });

  // ── 13. Reorder pages ───────────────────────────────────────────────────────
  test('14 reorder-pages reverse', () async {
    _in('reorder-pages', demo);
    final r = await PdfService.reorderPages(demo, [3, 2, 1, 0]);
    _out('reorder-pages', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.pageCount, equals(4));
  });

  // ── 14. Interleave ──────────────────────────────────────────────────────────
  test('15 interleave', () async {
    final second = _make2Page(tempDir);
    _in('interleave', demo);
    print('  [interleave] + second.pdf (2 pages)');
    final r = await PdfService.interleavePdfs(demo, second);
    _out('interleave', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 15. N-up ────────────────────────────────────────────────────────────────
  test('16 nup 2x1', () async {
    _in('nup', demo);
    final r = await PdfService.nUpLayout(demo, 2, 1);
    _out('nup', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 16. Booklet ─────────────────────────────────────────────────────────────
  test('17 booklet', () async {
    _in('booklet', demo);
    final r = await PdfService.bookletLayout(demo);
    _out('booklet', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 17. Add Text ────────────────────────────────────────────────────────────
  test('18 add-text', () async {
    _in('add-text', demo);
    final r = await PdfService.addTextToPdf(
        demo, TextAnnotation(text: 'HELLO WORLD', x: 50, y: 50, fontSize: 18, pageIndex: 0));
    _out('add-text', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 18. Add Image ───────────────────────────────────────────────────────────
  test('19 add-image', () async {
    final imgPath = _makePng(tempDir);
    _in('add-image', demo);
    final r = await PdfService.addImageToPdf(demo, imgPath,
        x: 50, y: 50, w: 100, h: 100, page: 0);
    _out('add-image', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 19. Crop ────────────────────────────────────────────────────────────────
  test('20 crop', () async {
    _in('crop', demo);
    final r = await PdfService.cropPdf(demo, 30, 30, 30, 30);
    _out('crop', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 20. Redact ──────────────────────────────────────────────────────────────
  test('21 redact', () async {
    _in('redact', demo);
    final r = await PdfService.redactAreas(demo, [
      {'page': 0, 'x': 40.0, 'y': 40.0, 'w': 200.0, 'h': 30.0},
    ]);
    _out('redact', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 21. Find & Replace ──────────────────────────────────────────────────────
  test('22 find-replace', () async {
    _in('find-replace', demo);
    final r = await PdfService.findAndReplace(
        demo, 'FIND_THIS_TEXT', 'REPLACED_TEXT');
    _out('find-replace', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 22. Add QR ──────────────────────────────────────────────────────────────
  test('23 add-qr', () async {
    _in('add-qr', demo);
    final r = await PdfService.addQrCode(
        demo, 'https://pdfist.app', 'bottomRight', 80);
    _out('add-qr', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 23. Date Stamp ──────────────────────────────────────────────────────────
  test('24 date-stamp', () async {
    _in('date-stamp', demo);
    final r = await PdfService.addDateStamp(demo, '09/05/2026', 'bottomRight');
    _out('date-stamp', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 24. Bookmarks ───────────────────────────────────────────────────────────
  test('25 bookmarks', () async {
    _in('bookmarks', demo);
    final r = await PdfService.addBookmarks(demo, [
      {'title': 'Introduction', 'page': 1},
      {'title': 'Invoice',      'page': 3},
      {'title': 'End',          'page': 4},
    ]);
    _out('bookmarks', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 25. Edit Metadata ───────────────────────────────────────────────────────
  test('26 edit-meta', () async {
    _in('edit-meta', demo);
    final r = await PdfService.updateMetadata(
        demo,
        PdfMetadata(
          title: 'Smoke Test PDF',
          author: 'PDFist Bot',
          subject: 'Automated Test',
          keywords: 'test smoke pdfist',
        ));
    _out('edit-meta', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 26. View Metadata ───────────────────────────────────────────────────────
  test('27 view-meta', () async {
    _in('view-meta', demo);
    final raw = await PdfService.getMetadata(demo);
    print('  [view-meta] OUT : ${raw.entries.where((e) => e.value != null).map((e) => "${e.key}=${e.value}").join(" | ")}');
    expect(raw['success'], isTrue);
  });

  // ── 27. Word Count ──────────────────────────────────────────────────────────
  test('28 word-count', () async {
    _in('word-count', demo);
    final r = await PdfService.getWordCount(demo);
    print('  [word-count] OUT : pages=${r.pages} words=${r.words} '
        'chars=${r.characters} charsNoSpaces=${r.charsNoSpaces}');
    expect(r.words, greaterThan(0));
    expect(r.charsNoSpaces, lessThanOrEqualTo(r.characters));
  });

  // ── 28. File Stats ──────────────────────────────────────────────────────────
  test('29 file-stats', () async {
    _in('file-stats', demo);
    final raw = await PdfService.getFullStats(demo);
    print('  [file-stats] OUT : ${raw.entries.where((e) => e.value != null).map((e) => "${e.key}=${e.value}").join(" | ")}');
    expect(raw['success'], isTrue);
  });

  // ── 29. Compare identical ───────────────────────────────────────────────────
  test('30 compare identical', () async {
    _in('compare-same', demo);
    final r = await PdfService.comparePdfsText(demo, demo);
    _out('compare-same', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.extras?['Result'], equals('Identical'));
  });

  // ── 30. Compare different ───────────────────────────────────────────────────
  test('31 compare different', () async {
    final second = _make2Page(tempDir);
    _in('compare-diff', demo);
    print('  [compare-diff] vs second.pdf');
    final r = await PdfService.comparePdfsText(demo, second);
    _out('compare-diff', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.extras?['Result'], equals('Different'));
  });

  // ── 31. Extract Text ────────────────────────────────────────────────────────
  test('32 extract-text (pdfToText)', () async {
    _in('extract-text', demo);
    final r = await PdfService.pdfToText(demo);
    _out('extract-text', r);
    expect(r.success, isTrue, reason: r.error);
    if (r.outputPath != null) {
      final txt = File(r.outputPath!).readAsStringSync();
      print('  [extract-text] first 200 chars: "${txt.substring(0, txt.length.clamp(0, 200))}"');
      expect(txt.length, greaterThan(0));
    }
  });

  // ── 32. Fill Form ───────────────────────────────────────────────────────────
  test('33 fill-form', () async {
    final formPdf = _makeFormPdf(tempDir);
    _in('fill-form', formPdf);
    final r = await PdfService.fillFormFields(formPdf, {'Name': 'John Doe'});
    _out('fill-form', r);
    expect(r.success, isTrue, reason: r.error);
    // Verify field was written.
    final bytes = File(r.outputPath!).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    String? written;
    for (int i = 0; i < doc.form.fields.count; i++) {
      final f = doc.form.fields[i];
      if (f is PdfTextBoxField && f.name == 'Name') written = f.text;
    }
    doc.dispose();
    print('  [fill-form] field "Name" after fill = "$written"');
    expect(written, equals('John Doe'));
  });

  // ── 33. Flatten Form ────────────────────────────────────────────────────────
  test('34 flatten', () async {
    final formPdf = _makeFormPdf(tempDir);
    _in('flatten', formPdf);
    final r = await PdfService.flattenFormFields(formPdf);
    _out('flatten', r);
    expect(r.success, isTrue, reason: r.error);
    final bytes = File(r.outputPath!).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final cnt = doc.form.fields.count;
    doc.dispose();
    print('  [flatten] interactive fields after flatten: $cnt');
  });

  // ── 34. Add Permissions ─────────────────────────────────────────────────────
  test('35 add-perms', () async {
    _in('add-perms', demo);
    final r = await PdfService.addPermissions(demo, 'ownerpass');
    _out('add-perms', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 35. Remove Permissions ──────────────────────────────────────────────────
  test('36 remove-perms', () async {
    _in('remove-perms', demo);
    final r = await PdfService.removePermissions(demo, 'ownerpass');
    _out('remove-perms', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 36. Highlight ───────────────────────────────────────────────────────────
  test('37 highlight', () async {
    _in('highlight', demo);
    final r = await PdfService.addTextMarkup(demo, 'Lorem', 'highlight', 0);
    _out('highlight', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 37. Underline ───────────────────────────────────────────────────────────
  test('38 underline', () async {
    _in('underline', demo);
    final r = await PdfService.addTextMarkup(demo, 'fox', 'underline', 1);
    _out('underline', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 38. Strikethrough ───────────────────────────────────────────────────────
  test('39 strikethrough', () async {
    _in('strikethrough', demo);
    final r = await PdfService.addTextMarkup(demo, 'ipsum', 'strikethrough', 2);
    _out('strikethrough', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 39. Sticky Notes ────────────────────────────────────────────────────────
  test('40 sticky-notes', () async {
    _in('sticky-notes', demo);
    final r = await PdfService.addStickyNote(
        demo, 'Review this section', 1, 100, 200);
    _out('sticky-notes', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 40. Hyperlinks ──────────────────────────────────────────────────────────
  test('41 hyperlinks', () async {
    _in('hyperlinks', demo);
    final r = await PdfService.addHyperlink(
        demo, 'pdfist.app', 'https://pdfist.app');
    _out('hyperlinks', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 41. Add Shapes ──────────────────────────────────────────────────────────
  test('42 add-shapes rect', () async {
    _in('add-shapes', demo);
    final r = await PdfService.addShapeToPdf(demo, 'rect', 50, 50, 150, 80, 0);
    _out('add-shapes', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 42. Draw on PDF ─────────────────────────────────────────────────────────
  test('43 draw', () async {
    _in('draw', demo);
    final strokes = [
      [[40.0, 40.0], [100.0, 40.0], [100.0, 100.0]],
    ];
    final r = await PdfService.drawOnPdf(demo, strokes, 400, 566, 0);
    _out('draw', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 43. Signature ───────────────────────────────────────────────────────────
  test('44 signature image', () async {
    _in('signature', demo);
    final image = img.Image(width: 200, height: 60);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(image, 'John Doe',
        font: img.arial14, x: 10, y: 20,
        color: img.ColorRgb8(0, 0, 0));
    final sigBytes = Uint8List.fromList(img.encodePng(image));
    final r = await PdfService.addDrawnSignature(demo, sigBytes,
        SignaturePosition(x: 50, y: 700, width: 200, height: 60, pageIndex: 0));
    _out('signature', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 44. Duplicate ───────────────────────────────────────────────────────────
  test('45 duplicate', () async {
    _in('duplicate', demo);
    final r = await PdfService.duplicatePdf(demo);
    _out('duplicate', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.pageCount, equals(4));
  });

  // ── 45. Reverse ─────────────────────────────────────────────────────────────
  test('46 reverse', () async {
    _in('reverse', demo);
    final r = await PdfService.reversePages(demo);
    _out('reverse', r);
    expect(r.success, isTrue, reason: r.error);
    expect(r.pageCount, equals(4));
  });

  // ── 46. Optimise for Web ────────────────────────────────────────────────────
  test('47 optimize-web', () async {
    _in('optimize-web', demo);
    final r = await PdfService.optimizeForWeb(demo);
    _out('optimize-web', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 47. Remove Duplicates ───────────────────────────────────────────────────
  test('48 remove-duplicates', () async {
    _in('remove-duplicates', demo);
    final r = await PdfService.removeDuplicatePages(demo);
    _out('remove-duplicates', r);
    expect(r.success, isTrue, reason: r.error);
  });

  // ── 48. Repair ──────────────────────────────────────────────────────────────
  test('49 repair', () async {
    _in('repair', demo);
    final r = await PdfService.repairPdf(demo);
    _out('repair', r);
    expect(r.success, isTrue, reason: r.error);
  });

}
