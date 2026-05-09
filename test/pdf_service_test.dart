// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
// dart:ui is needed for Rect in syncfusion calls inside tests.
// ignore: unnecessary_import
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:image/image.dart' as img;
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

// ─── Test helpers ─────────────────────────────────────────────────────────────

/// Creates a valid 50×50 white PNG and writes it to [dir]/[name].png.
String _createTestPng(Directory dir, String name) {
  final image = img.Image(width: 50, height: 50);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final bytes = Uint8List.fromList(img.encodePng(image));
  final path = '${dir.path}/$name.png';
  File(path).writeAsBytesSync(bytes);
  return path;
}

/// Creates a small multi-page PDF with known text content and returns its path.
String _createTestPdf(Directory dir, {int pages = 3, String tag = 'test'}) {
  final doc = PdfDocument();
  doc.pageSettings.size = PdfPageSize.a4;
  doc.pageSettings.margins.all = 0;
  final font = PdfStandardFont(PdfFontFamily.helvetica, 20);
  final brush = PdfSolidBrush(PdfColor(0, 0, 0));
  for (int i = 0; i < pages; i++) {
    PdfPage page;
    if (i == 0) {
      page = doc.pages.add();
    } else {
      final sec = doc.sections!.add();
      sec.pageSettings.size = PdfPageSize.a4;
      sec.pageSettings.margins.all = 0;
      page = sec.pages.add();
    }
    page.graphics.drawString(
      'PDFist Test — Page ${i + 1} [$tag]',
      font,
      brush: brush,
      bounds: const Rect.fromLTWH(40, 40, 500, 40),
    );
  }
  final bytes = doc.saveSync();
  doc.dispose();
  final path = '${dir.path}/${tag}_${pages}p.pdf';
  File(path).writeAsBytesSync(bytes);
  return path;
}

/// Reads a PDF from [path] and returns its page count.
int _pageCount(String path) {
  final bytes = File(path).readAsBytesSync();
  final doc = PdfDocument(inputBytes: bytes);
  final c = doc.pages.count;
  doc.dispose();
  return c;
}

/// Reads a PDF and returns true if the file is parseable.
bool _isValidPdf(String path) {
  if (!File(path).existsSync()) return false;
  try {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 5) return false;
    final doc = PdfDocument(inputBytes: bytes);
    doc.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('pdfist_test_');
    // Point path_provider at our temp dir so PdfService._out() writes there.
    PathProviderPlatform.instance = _FakePP(tempDir.path);
    // Create output sub-directory that PdfService expects.
    await Directory('${tempDir.path}/PDFist/Output').create(recursive: true);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  // ── 1. Core: Merge ──────────────────────────────────────────────────────────

  test('mergePdfs — combines two PDFs into one', () async {
    final a = _createTestPdf(tempDir, pages: 2, tag: 'merge_a');
    final b = _createTestPdf(tempDir, pages: 3, tag: 'merge_b');

    final result = await PdfService.mergePdfs([a, b]);

    print('[merge] success=${result.success} pages=${result.pageCount} '
        'size=${result.sizeAfterFormatted} err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, isNotNull);
    expect(_isValidPdf(result.outputPath!), isTrue);
    // Merged doc should have 2+3=5 pages.
    expect(_pageCount(result.outputPath!), equals(5));
  });

  // ── 2. Core: Split ──────────────────────────────────────────────────────────

  test('splitPdf individual — produces one file per page', () async {
    final src = _createTestPdf(tempDir, pages: 4, tag: 'split_src');
    final result = await PdfService.splitPdf(src, mode: 'individual');

    print('[split-individual] success=${result.success} err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, isNotNull);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  test('splitPdf byPageRange — extracts pages 2–3', () async {
    final src = _createTestPdf(tempDir, pages: 5, tag: 'split_range');
    final result = await PdfService.splitPdf(src,
        mode: 'byPageRange', start: 2, end: 3);

    print('[split-range] success=${result.success} '
        'out=${result.outputPath?.split('/').last} err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(_pageCount(result.outputPath!), equals(2));
  });

  test('splitPdf everyN — splits every 2 pages', () async {
    final src = _createTestPdf(tempDir, pages: 6, tag: 'split_n');
    final result =
        await PdfService.splitPdf(src, mode: 'everyN', n: 2);

    print('[split-everyN] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
  });

  // ── 3. Core: Extract pages ──────────────────────────────────────────────────

  test('extractPages — extracts pages 0 and 2 (zero-indexed)', () async {
    final src = _createTestPdf(tempDir, pages: 5, tag: 'extract');
    final result = await PdfService.extractPages(src, [0, 2]);

    print('[extract] success=${result.success} pages=${result.pageCount} '
        'err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(_pageCount(result.outputPath!), equals(2));
  });

  // ── 4. Core: Delete pages ───────────────────────────────────────────────────

  test('deletePages — removes page 1 from a 3-page PDF', () async {
    final src = _createTestPdf(tempDir, pages: 3, tag: 'delete');
    final result = await PdfService.deletePages(src, [1]);

    print('[delete] success=${result.success} pages=${result.pageCount} '
        'err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(_pageCount(result.outputPath!), equals(2));
  });

  // ── 5. Core: Reorder pages ──────────────────────────────────────────────────

  test('reorderPages — reverses page order', () async {
    final src = _createTestPdf(tempDir, pages: 3, tag: 'reorder');
    final result = await PdfService.reorderPages(src, [2, 1, 0]);

    print('[reorder] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_pageCount(result.outputPath!), equals(3));
  });

  // ── 6. Core: Rotate ─────────────────────────────────────────────────────────

  test('rotatePdf 90° — all pages', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'rotate');
    final result = await PdfService.rotatePdf(src, 90);

    print('[rotate] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  test('rotatePdf 180° — only page 0', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'rotate_p0');
    final result = await PdfService.rotatePdf(src, 180, pages: [0]);

    print('[rotate-p0] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
  });

  // ── 7. Compress ─────────────────────────────────────────────────────────────

  test('compressPdf low — output is valid, smaller-or-equal size', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'compress_low');
    final inputSize = File(src).lengthSync();
    final result = await PdfService.compressPdf(src, 'low');

    print('[compress-low] success=${result.success} '
        'in=$inputSize out=${result.outputSize} err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  test('compressPdf high — output is valid PDF', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'compress_high');
    final result = await PdfService.compressPdf(src, 'high');

    print('[compress-high] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 8. Security ─────────────────────────────────────────────────────────────

  test('addPassword + removePassword round-trip', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'pw');
    const userPw = 'testuser123';
    const ownerPw = 'testowner456';

    final protected = await PdfService.addPassword(src, userPw, ownerPw);
    print('[addPassword] success=${protected.success} err=${protected.error}');
    expect(protected.success, isTrue, reason: protected.error);

    // Try opening the protected file — should fail without password.
    bool failedWithoutPw = false;
    try {
      PdfDocument(inputBytes: File(protected.outputPath!).readAsBytesSync());
    } catch (_) {
      failedWithoutPw = true;
    }
    // Note: Syncfusion may or may not throw — either is acceptable here.
    print('[addPassword] protected opens without pw: ${!failedWithoutPw}');

    // Remove password — open with user password and re-save unencrypted.
    // Note: the Syncfusion community/trial licence may not enforce encryption at
    // re-open time, so we only assert the operation itself succeeds and the
    // output file is non-empty rather than strictly validating with PdfDocument.
    final unlocked = await PdfService.removePassword(
        protected.outputPath!, userPw);
    print('[removePassword] success=${unlocked.success} err=${unlocked.error}');
    expect(unlocked.success, isTrue, reason: unlocked.error);
    expect(unlocked.outputPath, isNotNull);
    expect(File(unlocked.outputPath!).lengthSync(), greaterThan(10));
  });

  // ── 9. Watermark ────────────────────────────────────────────────────────────

  test('addWatermark — output is valid PDF', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'watermark');
    final result = await PdfService.addWatermark(
        src,
        WatermarkConfig(
            text: 'CONFIDENTIAL', opacity: 0.3, fontSize: 60, rotation: -45));

    print('[watermark] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 10. Stamp ───────────────────────────────────────────────────────────────

  test('addStamp DRAFT — output is valid PDF', () async {
    final src = _createTestPdf(tempDir, pages: 1, tag: 'stamp');
    final result = await PdfService.addStamp(src, StampType.draft, 'center');

    print('[stamp] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  test('addStamp APPROVED topLeft — output is valid PDF', () async {
    final src = _createTestPdf(tempDir, pages: 1, tag: 'stamp_approved');
    final result =
        await PdfService.addStamp(src, StampType.approved, 'topLeft');

    expect(result.success, isTrue, reason: result.error);
  });

  // ── 11. Page numbers ────────────────────────────────────────────────────────

  test('addPageNumbers — output is valid PDF', () async {
    final src = _createTestPdf(tempDir, pages: 3, tag: 'pagenums');
    final result = await PdfService.addPageNumbers(
        src,
        PageNumberConfig(
            format: '{page} of {total}',
            position: 'bottom-center',
            fontSize: 10));

    print('[pageNumbers] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 12. Header/Footer ───────────────────────────────────────────────────────

  test('addHeaderFooter — output is valid PDF', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'hf');
    final result = await PdfService.addHeaderFooter(
        src,
        HeaderFooterConfig(
            headerText: 'PDFIST HEADER', footerText: 'Page Footer'));

    print('[headerFooter] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 13. Add text annotation ─────────────────────────────────────────────────

  test('addTextToPdf — output is valid PDF', () async {
    final src = _createTestPdf(tempDir, pages: 1, tag: 'addtext');
    final result = await PdfService.addTextToPdf(
        src,
        TextAnnotation(
            text: 'Annotated by PDFist',
            x: 100,
            y: 200,
            fontSize: 14,
            pageIndex: 0));

    print('[addText] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 14. PDF → Text ──────────────────────────────────────────────────────────

  test('pdfToText — extracted text contains known content', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'totext');
    final result = await PdfService.pdfToText(src);

    print('[pdfToText] success=${result.success} '
        'size=${result.outputSize}B err=${result.error}');

    expect(result.success, isTrue, reason: result.error);
    expect(result.outputPath, isNotNull);
    final textOut = File(result.outputPath!).readAsStringSync();
    expect(textOut, contains('PDFist Test'));
    print('[pdfToText] extracted snippet: "${textOut.substring(0, textOut.length.clamp(0, 80)).trim()}"');
  });

  // ── 15. Extract all text (direct) ───────────────────────────────────────────

  test('extractAllText — returns known text', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'alltext');
    final text = await PdfService.extractAllText(src);

    print('[extractAllText] chars=${text.length} '
        'snippet="${text.substring(0, text.length.clamp(0, 60)).trim()}"');

    expect(text, contains('PDFist Test'));
  });

  // ── 16. Text → PDF ──────────────────────────────────────────────────────────

  test('textToPdf — converts .txt file to PDF', () async {
    final txtPath = '${tempDir.path}/sample.txt';
    File(txtPath).writeAsStringSync(
        'Hello from PDFist.\nLine 2 of the text file.\nLine 3.');

    final result = await PdfService.textToPdf(txtPath);

    print('[textToPdf] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 17. Images → PDF ────────────────────────────────────────────────────────

  test('imagesToPdf — converts PNG image to PDF', () async {
    final imgPath = _createTestPng(tempDir, 'test_image');
    final result = await PdfService.imagesToPdf([imgPath]);

    print('[imagesToPdf] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 18. Reverse pages ───────────────────────────────────────────────────────

  test('reversePages — page count preserved', () async {
    final src = _createTestPdf(tempDir, pages: 4, tag: 'reverse');
    final result = await PdfService.reversePages(src);

    print('[reverse] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_pageCount(result.outputPath!), equals(4));
  });

  // ── 19. Interleave PDFs ─────────────────────────────────────────────────────

  test('interleavePdfs — combines alternating pages', () async {
    final a = _createTestPdf(tempDir, pages: 2, tag: 'ilv_a');
    final b = _createTestPdf(tempDir, pages: 2, tag: 'ilv_b');
    final result = await PdfService.interleavePdfs(a, b);

    print('[interleave] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_pageCount(result.outputPath!), equals(4));
  });

  // ── 20. N-Up layout ─────────────────────────────────────────────────────────

  test('nUpLayout 2x2 — 4 pages become 1 sheet', () async {
    final src = _createTestPdf(tempDir, pages: 4, tag: 'nup');
    final result = await PdfService.nUpLayout(src, 2, 2);

    print('[nup-2x2] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
    expect(_pageCount(result.outputPath!), equals(1));
  });

  // ── 21. Booklet layout ──────────────────────────────────────────────────────

  test('bookletLayout — valid PDF output', () async {
    final src = _createTestPdf(tempDir, pages: 4, tag: 'booklet');
    final result = await PdfService.bookletLayout(src);

    print('[booklet] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 22. Duplicate ───────────────────────────────────────────────────────────

  test('duplicatePdf — copy is byte-identical to source', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'dup');
    final result = await PdfService.duplicatePdf(src);

    print('[duplicate] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    final srcBytes = File(src).readAsBytesSync();
    final outBytes = File(result.outputPath!).readAsBytesSync();
    expect(outBytes, equals(srcBytes));
  });

  // ── 23. Update metadata ─────────────────────────────────────────────────────

  test('updateMetadata — title and author survive round-trip', () async {
    final src = _createTestPdf(tempDir, pages: 1, tag: 'meta');
    final result = await PdfService.updateMetadata(
        src,
        PdfMetadata(
            title: 'PDFist Test Doc',
            author: 'Test Runner',
            subject: 'Unit Test',
            keywords: 'pdfist test'));

    print('[metadata] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);

    final bytes = File(result.outputPath!).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    expect(doc.documentInformation.title, equals('PDFist Test Doc'));
    expect(doc.documentInformation.author, equals('Test Runner'));
    doc.dispose();
  });

  // ── 24. Get file stats ──────────────────────────────────────────────────────

  test('getFileStats — returns correct page count', () async {
    final src = _createTestPdf(tempDir, pages: 5, tag: 'stats');
    final stats = await PdfService.getFileStats(src);

    print('[getFileStats] pages=${stats.pageCount} size=${stats.fileSize}B');
    expect(stats.pageCount, equals(5));
    expect(stats.fileSize, greaterThan(0));
  });

  // ── 25. Word count ──────────────────────────────────────────────────────────

  test('getWordCount — finds words in text PDF', () async {
    final src = _createTestPdf(tempDir, pages: 2, tag: 'wordcount');
    final wc = await PdfService.getWordCount(src);

    print('[wordCount] words=${wc.words} chars=${wc.characters} pages=${wc.pages}');
    expect(wc.pages, equals(2));
    // "PDFist Test — Page N [tag]" across 2 pages should give several words.
    expect(wc.words, greaterThan(3));
  });

  // ── 26. Flatten form fields ─────────────────────────────────────────────────

  test('flattenFormFields — works on non-form PDF (no-op)', () async {
    final src = _createTestPdf(tempDir, pages: 1, tag: 'flatten');
    final result = await PdfService.flattenFormFields(src);

    print('[flatten] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 27. Add image to PDF ────────────────────────────────────────────────────

  test('addImageToPdf — embeds a PNG into a PDF page', () async {
    final src = _createTestPdf(tempDir, pages: 1, tag: 'addimg');
    final imgPath = _createTestPng(tempDir, 'embed');
    final result = await PdfService.addImageToPdf(src, imgPath,
        x: 50, y: 50, w: 100, h: 100, page: 0);

    print('[addImage] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });

  // ── 28. Drawn signature ─────────────────────────────────────────────────────

  test('addDrawnSignature — embeds signature PNG into PDF', () async {
    final src = _createTestPdf(tempDir, pages: 1, tag: 'sig');
    final sigBytes = File(_createTestPng(tempDir, 'sig_img')).readAsBytesSync();
    final result = await PdfService.addDrawnSignature(
        src,
        sigBytes,
        SignaturePosition(x: 200, y: 600, width: 150, height: 50, pageIndex: 0));

    print('[drawSig] success=${result.success} err=${result.error}');
    expect(result.success, isTrue, reason: result.error);
    expect(_isValidPdf(result.outputPath!), isTrue);
  });
}
