import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart' hide ZLibDecoder, ZLibEncoder;
import 'dart:math' as math;
// dart:ui gives us Offset, Size, Rect, Image, ImageByteFormat (all used below).
// ignore: unnecessary_import
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:qr/qr.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/pdf_models.dart';

// ─── Internal helpers ─────────────────────────────────────────────────────────

/// Adds one source page (including its content) into [outDoc] as a new section,
/// preserving the source page dimensions.
void _copyPage(PdfDocument outDoc, PdfPage srcPage) {
  final sz = srcPage.getClientSize();
  final section = outDoc.sections!.add();
  section.pageSettings.size = sz;
  section.pageSettings.margins.all = 0;
  final newPage = section.pages.add();
  newPage.graphics.drawPdfTemplate(
      srcPage.createTemplate(), const Offset(0, 0));
}

Map<String, dynamic> _ok(String outputPath, Uint8List outBytes, int pageCount,
    int inputSize, Stopwatch sw) {
  return {
    'success': true,
    'outputPath': outputPath,
    'outputSize': outBytes.length,
    'pageCount': pageCount,
    'inputSize': inputSize,
    'ms': sw.elapsedMilliseconds,
  };
}

Map<String, dynamic> _err(Object e) => {'success': false, 'error': '$e'};

PdfResult _toResult(Map<String, dynamic> m) => PdfResult(
      success: m['success'] as bool,
      outputPath: m['outputPath'] as String?,
      outputSize: (m['outputSize'] as int?) ?? 0,
      pageCount: m['pageCount'] as int?,
      inputSize: (m['inputSize'] as int?) ?? 0,
      processingTimeMs: (m['ms'] as int?) ?? 0,
      error: m['error'] as String?,
    );

// ─── Isolate-safe functions (pure Dart / syncfusion only) ────────────────────

Map<String, dynamic> _doMerge(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final paths = List<String>.from(p_['paths'] as List);
  final outputPath = p_['outputPath'] as String;
  try {
    int totalInput = 0;
    final outDoc = PdfDocument();
    bool first = true;
    for (final path in paths) {
      final bytes = File(path).readAsBytesSync();
      totalInput += bytes.length;
      final doc = PdfDocument(inputBytes: bytes);
      for (int i = 0; i < doc.pages.count; i++) {
        if (first) {
          // Remove the blank page that a new PdfDocument starts with.
          first = false;
          // Clear the default page by just using it for the first real page.
          final sz = doc.pages[i].getClientSize();
          outDoc.pageSettings.size = sz;
          outDoc.pageSettings.margins.all = 0;
          outDoc.pages.add().graphics.drawPdfTemplate(
              doc.pages[i].createTemplate(), const Offset(0, 0));
        } else {
          _copyPage(outDoc, doc.pages[i]);
        }
      }
      doc.dispose();
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    final pageCount = outDoc.pages.count;
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, totalInput, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doSplit(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final mode = p_['mode'] as String;
  final outputDir = p_['outputDir'] as String;
  final base = p_['base'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final total = doc.pages.count;
    final outputPaths = <String>[];
    int totalOutput = 0;
    int firstOutputPageCount = 0;

    List<List<int>> ranges = [];
    if (mode == 'individual') {
      ranges = List.generate(total, (i) => [i]);
    } else if (mode == 'byPageRange') {
      final start = ((p_['start'] as int) - 1).clamp(0, total - 1);
      final end = ((p_['end'] as int) - 1).clamp(start, total - 1);
      ranges = [List.generate(end - start + 1, (j) => start + j)];
    } else if (mode == 'everyN') {
      final n = p_['n'] as int;
      for (int i = 0; i < total; i += n) {
        ranges.add(List.generate((n).clamp(0, total - i), (j) => i + j));
      }
    }

    for (int ri = 0; ri < ranges.length; ri++) {
      final outDoc = PdfDocument();
      bool first = true;
      for (final idx in ranges[ri]) {
        if (idx < 0 || idx >= total) continue;
        if (first) {
          first = false;
          final sz = doc.pages[idx].getClientSize();
          outDoc.pageSettings.size = sz;
          outDoc.pageSettings.margins.all = 0;
          outDoc.pages.add().graphics.drawPdfTemplate(
              doc.pages[idx].createTemplate(), const Offset(0, 0));
        } else {
          _copyPage(outDoc, doc.pages[idx]);
        }
      }
      final outBytes = Uint8List.fromList(outDoc.saveSync());
      if (ri == 0) firstOutputPageCount = outDoc.pages.count;
      outDoc.dispose();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outPath = p.join(outputDir, '${base}_part${ri + 1}_$ts.pdf');
      File(outPath).writeAsBytesSync(outBytes);
      outputPaths.add(outPath);
      totalOutput += outBytes.length;
    }
    doc.dispose();
    // When mode produces multiple files, zip them for single-tap sharing.
    String finalPath = outputPaths.first;
    int finalSize = totalOutput;
    if (outputPaths.length > 1) {
      final archive = Archive();
      for (final op in outputPaths) {
        final data = File(op).readAsBytesSync();
        archive.addFile(ArchiveFile(p.basename(op), data.length, data));
      }
      final zipBytes = ZipEncoder().encode(archive);
      final zipPath = p.join(outputDir, '${base}_split_${DateTime.now().millisecondsSinceEpoch}.zip');
      File(zipPath).writeAsBytesSync(Uint8List.fromList(zipBytes));
      finalPath = zipPath;
      finalSize = zipBytes.length;
    }
    return {
      'success': true,
      'outputPath': finalPath,
      'outputPaths': outputPaths,
      'outputSize': finalSize,
      'pageCount': firstOutputPageCount,
      'inputSize': bytes.length,
      'ms': sw.elapsedMilliseconds,
    };
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doPageOp(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final op = p_['op'] as String;
  final indices = List<int>.from(p_['indices'] as List);
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final total = doc.pages.count;

    final pagesToProcess = switch (op) {
      'extract' => indices,
      'delete' => List.generate(total, (i) => i)
          .where((i) => !indices.contains(i))
          .toList(),
      'reorder' => indices,
      _ => indices,
    };

    final outDoc = PdfDocument();
    bool first = true;
    for (final idx in pagesToProcess) {
      if (idx < 0 || idx >= total) continue;
      if (first) {
        first = false;
        final sz = doc.pages[idx].getClientSize();
        outDoc.pageSettings.size = sz;
        outDoc.pageSettings.margins.all = 0;
        outDoc.pages.add().graphics.drawPdfTemplate(
            doc.pages[idx].createTemplate(), const Offset(0, 0));
      } else {
        _copyPage(outDoc, doc.pages[idx]);
      }
    }

    final outBytes = Uint8List.fromList(outDoc.saveSync());
    doc.dispose();
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pagesToProcess.length, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doRotate(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final degrees = p_['degrees'] as int;
  final pageIndices = p_['pageIndices'] as List?;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final rotation = switch (degrees % 360) {
      90 => PdfPageRotateAngle.rotateAngle90,
      180 => PdfPageRotateAngle.rotateAngle180,
      270 => PdfPageRotateAngle.rotateAngle270,
      _ => PdfPageRotateAngle.rotateAngle0,
    };
    for (int i = 0; i < doc.pages.count; i++) {
      if (pageIndices == null || pageIndices.contains(i)) {
        doc.pages[i].rotation = rotation;
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doCompress(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final level = p_['level'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    doc.compressionLevel = switch (level) {
      'high' => PdfCompressionLevel.best,
      'low' => PdfCompressionLevel.none,
      _ => PdfCompressionLevel.normal,
    };
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doPassword(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final op = p_['op'] as String;
  final userPw = p_['userPassword'] as String? ?? '';
  final ownerPw = p_['ownerPassword'] as String? ?? '';
  final openPw = p_['openPassword'] as String? ?? '';
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = openPw.isEmpty
        ? PdfDocument(inputBytes: bytes)
        : PdfDocument(inputBytes: bytes, password: openPw);
    if (op == 'add') {
      doc.security.userPassword = userPw;
      doc.security.ownerPassword = ownerPw.isEmpty ? userPw : ownerPw;
      doc.security.algorithm = PdfEncryptionAlgorithm.aesx256BitRevision6;
    } else {
      doc.security.userPassword = '';
      doc.security.ownerPassword = '';
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doWatermark(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final text = p_['text'] as String;
  final opacity = (p_['opacity'] as num).toDouble();
  final fontSize = (p_['fontSize'] as num).toDouble();
  final rotation = (p_['rotation'] as num).toDouble();
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final font = PdfStandardFont(PdfFontFamily.helvetica, fontSize,
        style: PdfFontStyle.bold);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    for (int i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final sz = page.getClientSize();
      final textSize = font.measureString(text);
      page.graphics.save();
      page.graphics.setTransparency(opacity);
      page.graphics.translateTransform(sz.width / 2, sz.height / 2);
      page.graphics.rotateTransform(rotation);
      page.graphics.drawString(
        text, font,
        brush: brush,
        bounds: Rect.fromLTWH(-textSize.width / 2, -textSize.height / 2,
            textSize.width, textSize.height),
      );
      page.graphics.restore();
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doStamp(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final stampText = p_['stampText'] as String;
  final position = p_['position'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final font = PdfStandardFont(PdfFontFamily.helvetica, 48,
        style: PdfFontStyle.bold);
    final pen = PdfPen(PdfColor(180, 0, 0), width: 3);
    final brush = PdfSolidBrush(PdfColor(180, 0, 0));
    for (int i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final sz = page.getClientSize();
      final textSize = font.measureString(stampText);
      const pad = 8.0;
      final offset = switch (position) {
        'topLeft' => const Offset(20, 20),
        'topRight' => Offset(sz.width - textSize.width - 20, 20),
        'bottomLeft' => Offset(20, sz.height - textSize.height - 20),
        'bottomRight' => Offset(sz.width - textSize.width - 20,
            sz.height - textSize.height - 20),
        _ => Offset(
            (sz.width - textSize.width) / 2, (sz.height - textSize.height) / 2),
      };
      page.graphics.drawRectangle(
        pen: pen,
        bounds: Rect.fromLTWH(offset.dx - pad, offset.dy - pad,
            textSize.width + pad * 2, textSize.height + pad * 2),
      );
      page.graphics.drawString(stampText, font, brush: brush,
          bounds: Rect.fromLTWH(
              offset.dx, offset.dy, textSize.width, textSize.height));
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doPageNumbers(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final format = p_['format'] as String;
  final position = p_['position'] as String;
  final fontSize = (p_['fontSize'] as num).toDouble();
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final total = doc.pages.count;
    final font = PdfStandardFont(PdfFontFamily.helvetica, fontSize);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    final align = switch (position) {
      'bottom-left' || 'top-left' => PdfTextAlignment.left,
      'bottom-right' || 'top-right' => PdfTextAlignment.right,
      _ => PdfTextAlignment.center,
    };
    final isTop = position.startsWith('top');
    for (int i = 0; i < total; i++) {
      final page = doc.pages[i];
      final sz = page.getClientSize();
      final text = format
          .replaceAll('{page}', '${i + 1}')
          .replaceAll('{total}', '$total');
      page.graphics.drawString(text, font, brush: brush,
          bounds: Rect.fromLTWH(0, isTop ? 8 : sz.height - 20, sz.width, 16),
          format: PdfStringFormat(alignment: align));
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, total, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doHeaderFooter(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final header = p_['header'] as String?;
  final footer = p_['footer'] as String?;
  final fontSize = (p_['fontSize'] as num).toDouble();
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final font = PdfStandardFont(PdfFontFamily.helvetica, fontSize);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    final fmt = PdfStringFormat(alignment: PdfTextAlignment.center);
    for (int i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final sz = page.getClientSize();
      if (header != null && header.isNotEmpty) {
        page.graphics.drawString(header, font, brush: brush,
            bounds: Rect.fromLTWH(0, 8, sz.width, 16), format: fmt);
      }
      if (footer != null && footer.isNotEmpty) {
        page.graphics.drawString(footer, font, brush: brush,
            bounds: Rect.fromLTWH(0, sz.height - 20, sz.width, 16),
            format: fmt);
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddText(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final text = p_['text'] as String;
  final x = (p_['x'] as num).toDouble();
  final y = (p_['y'] as num).toDouble();
  final fontSize = (p_['fontSize'] as num).toDouble();
  final pageIndex = p_['pageIndex'] as int;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    if (pageIndex < doc.pages.count) {
      doc.pages[pageIndex].graphics.drawString(
        text,
        PdfStandardFont(PdfFontFamily.helvetica, fontSize),
        brush: PdfSolidBrush(PdfColor(0, 0, 0)),
        bounds: Rect.fromLTWH(x, y, 400, 100),
      );
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddImage(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final imagePath = p_['imagePath'] as String;
  final x = (p_['x'] as num).toDouble();
  final y = (p_['y'] as num).toDouble();
  final w = (p_['width'] as num).toDouble();
  final h = (p_['height'] as num).toDouble();
  final pageIndex = p_['pageIndex'] as int;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    if (pageIndex < doc.pages.count) {
      final imgBytes = File(imagePath).readAsBytesSync();
      doc.pages[pageIndex].graphics
          .drawImage(PdfBitmap(imgBytes), Rect.fromLTWH(x, y, w, h));
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doImagesToPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final imagePaths = List<String>.from(p_['imagePaths'] as List);
  final outputPath = p_['outputPath'] as String;
  int totalInput = 0;
  try {
    final outDoc = PdfDocument();
    bool first = true;
    for (final imgPath in imagePaths) {
      final imgBytes = File(imgPath).readAsBytesSync();
      totalInput += imgBytes.length;
      final decoded = img.decodeImage(imgBytes);
      if (decoded == null) continue;
      final sz = Size(decoded.width.toDouble(), decoded.height.toDouble());
      if (first) {
        first = false;
        outDoc.pageSettings.size = sz;
        outDoc.pageSettings.margins.all = 0;
        outDoc.pages.add().graphics
            .drawImage(PdfBitmap(imgBytes), Rect.fromLTWH(0, 0, sz.width, sz.height));
      } else {
        final sec = outDoc.sections!.add();
        sec.pageSettings.size = sz;
        sec.pageSettings.margins.all = 0;
        sec.pages.add().graphics
            .drawImage(PdfBitmap(imgBytes), Rect.fromLTWH(0, 0, sz.width, sz.height));
      }
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, imagePaths.length, totalInput, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doExtractText(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    return {
      'success': true,
      'text': text,
      'inputSize': bytes.length,
      'ms': sw.elapsedMilliseconds,
    };
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doPdfToText(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(doc).extractText();
    doc.dispose();
    File(outputPath).writeAsStringSync(text);
    final outSize = File(outputPath).lengthSync();
    return {
      'success': true,
      'outputPath': outputPath,
      'outputSize': outSize,
      'pageCount': null,
      'inputSize': bytes.length,
      'ms': sw.elapsedMilliseconds,
    };
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doTextToPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final fontSize = (p_['fontSize'] as num? ?? 12).toDouble();
  try {
    final inputBytes = File(inputPath).readAsBytesSync();
    final text = String.fromCharCodes(inputBytes);
    final outDoc = PdfDocument();
    final font = PdfStandardFont(PdfFontFamily.helvetica, fontSize);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    const lineH = 14.0;
    const marginX = 40.0;
    const marginY = 40.0;
    outDoc.pageSettings.size = PdfPageSize.a4;
    outDoc.pageSettings.margins.all = 0;
    var page = outDoc.pages.add();
    var y = marginY;
    final pageH = page.getClientSize().height;
    final pageW = page.getClientSize().width;
    for (final line in text.split('\n')) {
      if (y + lineH > pageH - marginY) {
        final sec = outDoc.sections!.add();
        sec.pageSettings.size = PdfPageSize.a4;
        sec.pageSettings.margins.all = 0;
        page = sec.pages.add();
        y = marginY;
      }
      page.graphics.drawString(line, font, brush: brush,
          bounds: Rect.fromLTWH(marginX, y, pageW - marginX * 2, lineH));
      y += lineH;
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, 0, inputBytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doInterleavePdfs(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final pathA = p_['pathA'] as String;
  final pathB = p_['pathB'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytesA = File(pathA).readAsBytesSync();
    final bytesB = File(pathB).readAsBytesSync();
    final docA = PdfDocument(inputBytes: bytesA);
    final docB = PdfDocument(inputBytes: bytesB);
    final outDoc = PdfDocument();
    final maxP = docA.pages.count > docB.pages.count
        ? docA.pages.count
        : docB.pages.count;
    bool first = true;
    for (int i = 0; i < maxP; i++) {
      for (final (doc, hasPage) in [
        (docA, i < docA.pages.count),
        (docB, i < docB.pages.count),
      ]) {
        if (!hasPage) continue;
        if (first) {
          first = false;
          final sz = doc.pages[i].getClientSize();
          outDoc.pageSettings.size = sz;
          outDoc.pageSettings.margins.all = 0;
          outDoc.pages.add().graphics.drawPdfTemplate(
              doc.pages[i].createTemplate(), const Offset(0, 0));
        } else {
          _copyPage(outDoc, doc.pages[i]);
        }
      }
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    docA.dispose();
    docB.dispose();
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(
        outputPath, outBytes, maxP * 2, bytesA.length + bytesB.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doReversePages(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final total = doc.pages.count;
    final reversed = List.generate(total, (i) => total - 1 - i);
    final outDoc = PdfDocument();
    bool first = true;
    for (final idx in reversed) {
      if (first) {
        first = false;
        final sz = doc.pages[idx].getClientSize();
        outDoc.pageSettings.size = sz;
        outDoc.pageSettings.margins.all = 0;
        outDoc.pages.add().graphics.drawPdfTemplate(
            doc.pages[idx].createTemplate(), const Offset(0, 0));
      } else {
        _copyPage(outDoc, doc.pages[idx]);
      }
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    doc.dispose();
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, total, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doNUp(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final cols = p_['cols'] as int;
  final rows = p_['rows'] as int;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final total = doc.pages.count;
    const sheetW = 841.89;
    const sheetH = 595.28;
    final cellW = sheetW / cols;
    final cellH = sheetH / rows;
    final perSheet = cols * rows;
    final outDoc = PdfDocument();
    outDoc.pageSettings.size = const Size(sheetW, sheetH);
    outDoc.pageSettings.orientation = PdfPageOrientation.landscape;
    outDoc.pageSettings.margins.all = 0;
    bool first = true;
    PdfPage? curPage;
    for (int srcIdx = 0; srcIdx < total; srcIdx++) {
      final sheetIdx = srcIdx % perSheet;
      if (sheetIdx == 0) {
        if (first) {
          first = false;
          curPage = outDoc.pages.add();
        } else {
          final sec = outDoc.sections!.add();
          sec.pageSettings.size = const Size(sheetW, sheetH);
          sec.pageSettings.orientation = PdfPageOrientation.landscape;
          sec.pageSettings.margins.all = 0;
          curPage = sec.pages.add();
        }
      }
      final col = sheetIdx % cols;
      final row = sheetIdx ~/ cols;
      final srcPage = doc.pages[srcIdx];
      final srcSz = srcPage.getClientSize();
      final scaleX = cellW / srcSz.width;
      final scaleY = cellH / srcSz.height;
      final scale = scaleX < scaleY ? scaleX : scaleY;
      final scaledW = srcSz.width * scale;
      final scaledH = srcSz.height * scale;
      final destX = col * cellW + (cellW - scaledW) / 2;
      final destY = row * cellH + (cellH - scaledH) / 2;
      // drawPdfTemplate's size parameter scales the template to fit the cell.
      curPage!.graphics.drawPdfTemplate(
          srcPage.createTemplate(),
          Offset(destX, destY),
          Size(scaledW, scaledH));
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    doc.dispose();
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, (total / perSheet).ceil(), bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doUpdateMetadata(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    if (p_['title'] != null) {
      doc.documentInformation.title = p_['title'] as String;
    }
    if (p_['author'] != null) {
      doc.documentInformation.author = p_['author'] as String;
    }
    if (p_['subject'] != null) {
      doc.documentInformation.subject = p_['subject'] as String;
    }
    if (p_['keywords'] != null) {
      doc.documentInformation.keywords = p_['keywords'] as String;
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doWordToPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final zipBytes = File(inputPath).readAsBytesSync();
    // DOCX is a ZIP — find word/document.xml
    final archive = _readZip(zipBytes);
    final docFile = archive.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw Exception('Not a valid DOCX'));
    final xmlStr = utf8.decode(docFile.content as List<int>);

    // Extract text blocks from XML: <w:t> tags, <w:p> = paragraph break
    final paragraphs = <String>[];
    final paraRe = RegExp(r'<w:p[ >].*?</w:p>', dotAll: true);
    final textRe = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
    for (final paraM in paraRe.allMatches(xmlStr)) {
      final buf = StringBuffer();
      for (final tM in textRe.allMatches(paraM.group(0)!)) {
        buf.write(tM.group(1));
      }
      paragraphs.add(buf.toString());
    }

    final outDoc = PdfDocument();
    outDoc.pageSettings.size = PdfPageSize.a4;
    outDoc.pageSettings.margins.all = 0;
    const mx = 50.0; const my = 50.0; const lh = 15.0;
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    var page = outDoc.pages.add();
    var y = my;
    final pw = page.getClientSize().width;
    final ph = page.getClientSize().height;

    for (final para in paragraphs) {
      final text = _xmlUnescape(para.trim());
      if (y + lh > ph - my) {
        final sec = outDoc.sections!.add();
        sec.pageSettings.size = PdfPageSize.a4;
        sec.pageSettings.margins.all = 0;
        page = sec.pages.add();
        y = my;
      }
      if (text.isEmpty) { y += lh * 0.5; continue; }
      page.graphics.drawString(text, font, brush: brush,
          bounds: Rect.fromLTWH(mx, y, pw - mx * 2, lh),
          format: PdfStringFormat(wordWrap: PdfWordWrapType.word));
      y += lh;
    }

    final outBytes = Uint8List.fromList(outDoc.saveSync());
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, paragraphs.length, zipBytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doExcelToPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final zipBytes = File(inputPath).readAsBytesSync();
    final archive = _readZip(zipBytes);

    // Read shared strings table
    final ssFile = archive.firstWhereOrNull((f) => f.name == 'xl/sharedStrings.xml');
    final sharedStrings = <String>[];
    if (ssFile != null) {
      final ssXml = utf8.decode(ssFile.content as List<int>);
      final tRe = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
      for (final m in tRe.allMatches(ssXml)) {
        sharedStrings.add(_xmlUnescape(m.group(1) ?? ''));
      }
    }

    // Read first sheet
    final sheetFile = archive.firstWhereOrNull(
        (f) => f.name == 'xl/worksheets/sheet1.xml');
    if (sheetFile == null) return _err('No sheet found');
    final sheetXml = utf8.decode(sheetFile.content as List<int>);

    // Parse rows → cells
    final rows = <List<String>>[];
    final rowRe = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true);
    final cellRe = RegExp(r'<c [^>]*r="([^"]+)"[^>]*(?:t="([^"]*)")?[^>]*>.*?<v>(.*?)</v>.*?</c>', dotAll: true);
    for (final rowM in rowRe.allMatches(sheetXml)) {
      final cells = <String>[];
      for (final cM in cellRe.allMatches(rowM.group(1)!)) {
        final type = cM.group(2) ?? '';
        final val = cM.group(3) ?? '';
        if (type == 's') {
          final idx = int.tryParse(val) ?? -1;
          cells.add(idx >= 0 && idx < sharedStrings.length ? sharedStrings[idx] : '');
        } else {
          cells.add(val);
        }
      }
      if (cells.isNotEmpty) rows.add(cells);
    }

    final numCols = rows.isEmpty ? 1 : rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final outDoc = PdfDocument();
    outDoc.pageSettings.size = PdfPageSize.a4;
    outDoc.pageSettings.orientation = numCols > 5 ? PdfPageOrientation.landscape : PdfPageOrientation.portrait;
    outDoc.pageSettings.margins.all = 0;
    var page = outDoc.pages.add();
    final pw = page.getClientSize().width;
    final ph = page.getClientSize().height;
    const mx = 30.0; const my = 30.0;
    final colW = (pw - mx * 2) / numCols;
    const rowH = 18.0;
    final headerFont = PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);
    final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final black = PdfSolidBrush(PdfColor(0, 0, 0));
    final grey = PdfSolidBrush(PdfColor(220, 220, 220));
    var y = my;

    for (int ri = 0; ri < rows.length; ri++) {
      if (y + rowH > ph - my) {
        final sec = outDoc.sections!.add();
        sec.pageSettings.size = PdfPageSize.a4;
        sec.pageSettings.orientation = numCols > 5 ? PdfPageOrientation.landscape : PdfPageOrientation.portrait;
        sec.pageSettings.margins.all = 0;
        page = sec.pages.add();
        y = my;
      }
      if (ri == 0) {
        page.graphics.drawRectangle(brush: grey, bounds: Rect.fromLTWH(mx, y, pw - mx * 2, rowH));
      }
      final row = rows[ri];
      for (int ci = 0; ci < numCols; ci++) {
        final cell = ci < row.length ? row[ci] : '';
        page.graphics.drawString(cell, ri == 0 ? headerFont : bodyFont, brush: black,
            bounds: Rect.fromLTWH(mx + ci * colW + 2, y + 2, colW - 4, rowH - 4),
            format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle));
        page.graphics.drawRectangle(
            pen: PdfPen(PdfColor(180, 180, 180), width: 0.5),
            bounds: Rect.fromLTWH(mx + ci * colW, y, colW, rowH));
      }
      y += rowH;
    }

    final outBytes = Uint8List.fromList(outDoc.saveSync());
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, rows.length, zipBytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doHtmlToPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final html = File(inputPath).readAsStringSync();
    final inputSize = File(inputPath).lengthSync();
    // Extract title
    final titleM = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html);
    final title = _xmlUnescape(titleM?.group(1)?.trim() ?? '');
    // Strip all tags and decode entities
    final stripped = _xmlUnescape(html.replaceAll(RegExp(r'<[^>]+>'), '\n'));
    final lines = stripped.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final outDoc = PdfDocument();
    outDoc.pageSettings.size = PdfPageSize.a4;
    outDoc.pageSettings.margins.all = 0;
    const mx = 50.0; const my = 50.0; const lh = 15.0;
    if (title.isNotEmpty) {
      outDoc.documentInformation.title = title;
    }
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    var page = outDoc.pages.add();
    var y = my;
    final pw = page.getClientSize().width;
    final ph = page.getClientSize().height;

    for (final line in lines) {
      if (y + lh > ph - my) {
        final sec = outDoc.sections!.add();
        sec.pageSettings.size = PdfPageSize.a4;
        sec.pageSettings.margins.all = 0;
        page = sec.pages.add();
        y = my;
      }
      page.graphics.drawString(line, font, brush: brush,
          bounds: Rect.fromLTWH(mx, y, pw - mx * 2, lh),
          format: PdfStringFormat(wordWrap: PdfWordWrapType.word));
      y += lh;
    }

    final outBytes = Uint8List.fromList(outDoc.saveSync());
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, lines.length, inputSize, sw);
  } catch (e) {
    return _err(e);
  }
}

// Helper: decode a ZIP archive (DOCX/XLSX are ZIP files).
List<_ArchiveEntry> _readZip(Uint8List bytes) {
  final entries = <_ArchiveEntry>[];
  var i = 0;
  while (i < bytes.length - 4) {
    if (bytes[i] == 0x50 && bytes[i+1] == 0x4B &&
        bytes[i+2] == 0x03 && bytes[i+3] == 0x04) {
      // Local file header
      final compression = bytes[i+8] | (bytes[i+9] << 8);
      final compressedSize = bytes[i+18] | (bytes[i+19] << 8) |
          (bytes[i+20] << 16) | (bytes[i+21] << 24);
      final nameLen = bytes[i+26] | (bytes[i+27] << 8);
      final extraLen = bytes[i+28] | (bytes[i+29] << 8);
      final nameBytes = bytes.sublist(i+30, i+30+nameLen);
      final name = utf8.decode(nameBytes, allowMalformed: true);
      final dataStart = i + 30 + nameLen + extraLen;
      if (dataStart + compressedSize <= bytes.length) {
        final compData = bytes.sublist(dataStart, dataStart + compressedSize);
        List<int> content;
        try {
          content = compression == 0 ? compData : ZLibDecoder().convert(compData);
        } catch (_) {
          content = compData;
        }
        entries.add(_ArchiveEntry(name, Uint8List.fromList(content)));
      }
      i = dataStart + compressedSize;
    } else {
      i++;
    }
  }
  return entries;
}

class _ArchiveEntry {
  final String name;
  final Uint8List content;
  _ArchiveEntry(this.name, this.content);
}

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}

String _xmlUnescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#xD;', '')
    .replaceAll('&#xA;', '\n')
    .replaceAll(RegExp(r'&#(\d+);'), '');

Map<String, dynamic> _doRepair(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddPermissions(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final ownerPw = (p_['ownerPassword'] as String?) ?? 'owner';
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    doc.security.ownerPassword = ownerPw;
    doc.security.algorithm = PdfEncryptionAlgorithm.aesx256BitRevision6;
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doRemovePermissions(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final ownerPw = (p_['ownerPassword'] as String?) ?? '';
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = ownerPw.isEmpty
        ? PdfDocument(inputBytes: bytes)
        : PdfDocument(inputBytes: bytes, password: ownerPw);
    doc.security.ownerPassword = '';
    doc.security.userPassword = '';
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doDateStamp(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final dateText = p_['dateText'] as String;
  final position = p_['position'] as String? ?? 'bottomRight';
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final font = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final brush = PdfSolidBrush(PdfColor(0, 0, 0));
    for (int i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final sz = page.getClientSize();
      final ts = font.measureString(dateText);
      final offset = switch (position) {
        'topLeft' => const Offset(10, 10),
        'topRight' => Offset(sz.width - ts.width - 10, 10),
        'bottomLeft' => Offset(10, sz.height - ts.height - 10),
        _ => Offset(sz.width - ts.width - 10, sz.height - ts.height - 10),
      };
      page.graphics.drawString(dateText, font, brush: brush,
          bounds: Rect.fromLTWH(offset.dx, offset.dy, ts.width, ts.height));
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doCropPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final left = (p_['left'] as num).toDouble();
  final top = (p_['top'] as num).toDouble();
  final right = (p_['right'] as num).toDouble();
  final bottom = (p_['bottom'] as num).toDouble();
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final outDoc = PdfDocument();
    bool first = true;
    for (int i = 0; i < doc.pages.count; i++) {
      final src = doc.pages[i];
      final srcSz = src.getClientSize();
      final newW = (srcSz.width - left - right).clamp(10.0, srcSz.width);
      final newH = (srcSz.height - top - bottom).clamp(10.0, srcSz.height);
      final newSz = Size(newW, newH);
      if (first) {
        first = false;
        outDoc.pageSettings.size = newSz;
        outDoc.pageSettings.margins.all = 0;
        final pg = outDoc.pages.add();
        pg.graphics.drawPdfTemplate(src.createTemplate(),
            Offset(-left, -top));
      } else {
        final sec = outDoc.sections!.add();
        sec.pageSettings.size = newSz;
        sec.pageSettings.margins.all = 0;
        sec.pages.add().graphics.drawPdfTemplate(src.createTemplate(),
            Offset(-left, -top));
      }
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    final pageCount = outDoc.pages.count;
    doc.dispose();
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doRedact(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final areas = p_['areas'] as List;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    for (final area in areas) {
      final pageIndex = area['page'] as int? ?? 0;
      if (pageIndex < 0 || pageIndex >= doc.pages.count) continue;
      final x = (area['x'] as num).toDouble();
      final y = (area['y'] as num).toDouble();
      final w = (area['w'] as num).toDouble();
      final h = (area['h'] as num).toDouble();
      doc.pages[pageIndex].graphics.drawRectangle(
        brush: PdfSolidBrush(PdfColor(0, 0, 0)),
        bounds: Rect.fromLTWH(x, y, w, h),
      );
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddQrCode(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final content = p_['content'] as String;
  final position = p_['position'] as String? ?? 'bottomRight';
  final size = (p_['size'] as num? ?? 80).toDouble();
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final qrCode = QrCode(4, QrErrorCorrectLevel.L);
    qrCode.addData(content);
    final qrImage = QrImage(qrCode);
    final moduleCount = qrImage.moduleCount;
    final cellSize = size / moduleCount;
    for (int i = 0; i < doc.pages.count; i++) {
      final page = doc.pages[i];
      final sz = page.getClientSize();
      final qrX = switch (position) {
        'topLeft' => 10.0,
        'topRight' => sz.width - size - 10,
        'bottomLeft' => 10.0,
        _ => sz.width - size - 10,
      };
      final qrY = switch (position) {
        'topLeft' || 'topRight' => 10.0,
        _ => sz.height - size - 10,
      };
      final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
      final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
      page.graphics.drawRectangle(brush: whiteBrush,
          bounds: Rect.fromLTWH(qrX, qrY, size, size));
      for (int row = 0; row < moduleCount; row++) {
        for (int col = 0; col < moduleCount; col++) {
          if (qrImage.isDark(row, col)) {
            page.graphics.drawRectangle(brush: blackBrush,
                bounds: Rect.fromLTWH(
                    qrX + col * cellSize, qrY + row * cellSize,
                    cellSize, cellSize));
          }
        }
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doMarkdownToPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final mdText = File(inputPath).readAsStringSync();
    final lines = mdText.split('\n');
    final outDoc = PdfDocument();
    outDoc.pageSettings.size = PdfPageSize.a4;
    outDoc.pageSettings.margins.all = 0;
    const marginX = 40.0;
    const marginY = 40.0;
    const lineH = 16.0;
    const headingH = 24.0;
    var page = outDoc.pages.add();
    var y = marginY;
    final pageH = page.getClientSize().height;
    final pageW = page.getClientSize().width;

    void ensureSpace(double needed) {
      if (y + needed > pageH - marginY) {
        final sec = outDoc.sections!.add();
        sec.pageSettings.size = PdfPageSize.a4;
        sec.pageSettings.margins.all = 0;
        page = sec.pages.add();
        y = marginY;
      }
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) { y += lineH * 0.5; continue; }
      if (line.startsWith('# ')) {
        ensureSpace(headingH + 4);
        page.graphics.drawString(line.substring(2), PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold),
            brush: PdfSolidBrush(PdfColor(0, 0, 0)),
            bounds: Rect.fromLTWH(marginX, y, pageW - marginX * 2, headingH));
        y += headingH + 4;
      } else if (line.startsWith('## ')) {
        ensureSpace(headingH);
        page.graphics.drawString(line.substring(3), PdfStandardFont(PdfFontFamily.helvetica, 14, style: PdfFontStyle.bold),
            brush: PdfSolidBrush(PdfColor(0, 0, 0)),
            bounds: Rect.fromLTWH(marginX, y, pageW - marginX * 2, headingH));
        y += headingH;
      } else if (line.startsWith('### ')) {
        ensureSpace(lineH + 4);
        page.graphics.drawString(line.substring(4), PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold),
            brush: PdfSolidBrush(PdfColor(0, 0, 0)),
            bounds: Rect.fromLTWH(marginX, y, pageW - marginX * 2, lineH + 4));
        y += lineH + 4;
      } else if (line.startsWith('> ')) {
        ensureSpace(lineH);
        page.graphics.drawString('  ${line.substring(2)}', PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.italic),
            brush: PdfSolidBrush(PdfColor(80, 80, 80)),
            bounds: Rect.fromLTWH(marginX + 12, y, pageW - marginX * 2 - 12, lineH));
        y += lineH;
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        ensureSpace(lineH);
        final txt = '• ${line.substring(2)}';
        page.graphics.drawString(txt, PdfStandardFont(PdfFontFamily.helvetica, 11),
            brush: PdfSolidBrush(PdfColor(0, 0, 0)),
            bounds: Rect.fromLTWH(marginX + 8, y, pageW - marginX * 2 - 8, lineH));
        y += lineH;
      } else if (line.startsWith('---') || line.startsWith('===')) {
        ensureSpace(lineH);
        page.graphics.drawLine(PdfPen(PdfColor(180, 180, 180)), Offset(marginX, y + lineH / 2), Offset(pageW - marginX, y + lineH / 2));
        y += lineH;
      } else {
        final cleanLine = line.replaceAllMapped(RegExp(r'\*\*(.*?)\*\*|__(.*?)__|\*(.*?)\*|_(.*?)_|`(.*?)`'), (m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? m.group(5) ?? '');
        ensureSpace(lineH);
        page.graphics.drawString(cleanLine, PdfStandardFont(PdfFontFamily.helvetica, 11),
            brush: PdfSolidBrush(PdfColor(0, 0, 0)),
            bounds: Rect.fromLTWH(marginX, y, pageW - marginX * 2, lineH));
        y += lineH;
      }
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    outDoc.dispose();
    final inputSize = File(inputPath).lengthSync();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, 0, inputSize, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doFindReplace(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final find = p_['find'] as String;
  final replace = p_['replace'] as String;
  final caseSensitive = p_['caseSensitive'] as bool? ?? false;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final whiteBrush = PdfSolidBrush(PdfColor(255, 255, 255));
    final blackBrush = PdfSolidBrush(PdfColor(0, 0, 0));
    int count = 0;
    for (int i = 0; i < doc.pages.count; i++) {
      final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      for (final line in lines) {
        final lineText = caseSensitive ? line.text : line.text.toLowerCase();
        final findText = caseSensitive ? find : find.toLowerCase();
        if (lineText.contains(findText)) {
          final b = line.bounds;
          final approxFontSize = b.height.clamp(6.0, 72.0);
          final font = PdfStandardFont(PdfFontFamily.helvetica, approxFontSize);
          doc.pages[i].graphics.drawRectangle(brush: whiteBrush, bounds: b);
          final newText = line.text.replaceAll(
              caseSensitive ? find : RegExp(find, caseSensitive: false), replace);
          doc.pages[i].graphics.drawString(newText, font, brush: blackBrush,
              bounds: Rect.fromLTWH(b.left, b.top, b.width, b.height));
          count++;
        }
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return {
      'success': true, 'outputPath': outputPath,
      'outputSize': outBytes.length, 'pageCount': pageCount,
      'inputSize': bytes.length, 'ms': sw.elapsedMilliseconds,
      'count': count,
    };
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddBookmarks(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final entries = p_['entries'] as List;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    for (final entry in entries) {
      final title = entry['title'] as String? ?? 'Bookmark';
      final pageIndex = (entry['page'] as int? ?? 1) - 1;
      if (pageIndex < 0 || pageIndex >= doc.pages.count) continue;
      final bookmark = doc.bookmarks.add(title);
      bookmark.destination = PdfDestination(doc.pages[pageIndex], const Offset(0, 0));
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doFillFormFields(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final fields = p_['fields'] as Map;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    for (int i = 0; i < doc.form.fields.count; i++) {
      final field = doc.form.fields[i];
      final value = fields[field.name];
      if (value == null) continue;
      if (field is PdfTextBoxField) field.text = value as String;
      if (field is PdfCheckBoxField) field.isChecked = value as bool;
      if (field is PdfComboBoxField) {
        try { field.selectedIndex = int.parse(value as String); } catch (_) {}
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doExtractImagesToDir(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputDir = p_['outputDir'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    Directory(outputDir).createSync(recursive: true);
    final base = p.basenameWithoutExtension(inputPath);
    int count = 0;
    int totalOut = 0;
    // Use image package to try decoding any stream objects that are JPEG/PNG.
    // We find JPEG markers in the raw bytes and save them.
    // Find JPEG streams: SOI marker FF D8 ... EOI marker FF D9
    int i = 0;
    while (i < bytes.length - 2) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
        // Possible JPEG start. Find the end.
        int j = i + 2;
        bool found = false;
        while (j < bytes.length - 1) {
          if (bytes[j] == 0xFF && bytes[j + 1] == 0xD9) {
            j += 2;
            found = true;
            break;
          }
          j++;
        }
        if (found && j - i > 500) {
          final imgBytes = bytes.sublist(i, j);
          final decoded = img.decodeJpg(imgBytes);
          if (decoded != null) {
            count++;
            final outPath = p.join(outputDir, '${base}_img${count.toString().padLeft(3, '0')}.jpg');
            File(outPath).writeAsBytesSync(imgBytes);
            totalOut += imgBytes.length;
          }
        }
        i = j;
      } else {
        i++;
      }
    }
    return {
      'success': true,
      'outputPath': outputDir,
      'outputSize': totalOut,
      'pageCount': count,
      'inputSize': bytes.length,
      'ms': sw.elapsedMilliseconds,
      'count': count,
    };
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doComparePdfsText(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final pathA = p_['pathA'] as String;
  final pathB = p_['pathB'] as String;
  try {
    final bytesA = File(pathA).readAsBytesSync();
    final bytesB = File(pathB).readAsBytesSync();
    final docA = PdfDocument(inputBytes: bytesA);
    final docB = PdfDocument(inputBytes: bytesB);
    final textA = PdfTextExtractor(docA).extractText();
    final textB = PdfTextExtractor(docB).extractText();
    docA.dispose();
    docB.dispose();
    final linesA = textA.split('\n');
    final linesB = textB.split('\n');
    int diff = 0;
    final maxLen = linesA.length > linesB.length ? linesA.length : linesB.length;
    for (int i = 0; i < maxLen; i++) {
      final a = i < linesA.length ? linesA[i] : '';
      final b = i < linesB.length ? linesB[i] : '';
      if (a != b) diff++;
    }
    return {
      'success': true,
      'identical': diff == 0,
      'diffLines': diff,
      'linesA': linesA.length,
      'linesB': linesB.length,
      'inputSize': bytesA.length + bytesB.length,
      'ms': sw.elapsedMilliseconds,
    };
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doGetMetadata(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final info = doc.documentInformation;
    final result = {
      'success': true,
      'title': info.title,
      'author': info.author,
      'subject': info.subject,
      'keywords': info.keywords,
      'creator': info.creator,
      'producer': info.producer,
      'pageCount': doc.pages.count,
      'inputSize': bytes.length,
      'ms': sw.elapsedMilliseconds,
    };
    doc.dispose();
    return result;
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doGetFullStats(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final formFieldCount = doc.form.fields.count;
    final bookmarkCount = doc.bookmarks.count;
    final pageCount = doc.pages.count;
    doc.dispose();
    return {
      'success': true,
      'fileSize': bytes.length,
      'pageCount': pageCount,
      'formFields': formFieldCount,
      'bookmarks': bookmarkCount,
      'inputSize': bytes.length,
      'ms': sw.elapsedMilliseconds,
    };
  } catch (e) {
    return _err(e);
  }
}

// ─── Canvas / annotation isolate functions ────────────────────────────────────

Map<String, dynamic> _doDrawOnPdf(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final strokesRaw = p_['strokes'] as List;
  final canvasW = (p_['canvasW'] as num).toDouble();
  final canvasH = (p_['canvasH'] as num).toDouble();
  final pageIndex = p_['pageIndex'] as int? ?? 0;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final idx = pageIndex.clamp(0, doc.pages.count - 1);
    final page = doc.pages[idx];
    final sz = page.getClientSize();
    final scaleX = canvasW > 0 ? sz.width / canvasW : 1.0;
    final scaleY = canvasH > 0 ? sz.height / canvasH : 1.0;
    final pen = PdfPen(PdfColor(0, 0, 0), width: 2);
    for (final strokeRaw in strokesRaw) {
      final stroke = (strokeRaw as List).map((pt) {
        final ptList = pt as List;
        return [
          (ptList[0] as num).toDouble(),
          (ptList[1] as num).toDouble(),
        ];
      }).toList();
      for (int i = 1; i < stroke.length; i++) {
        page.graphics.drawLine(
          pen,
          Offset(stroke[i - 1][0] * scaleX, stroke[i - 1][1] * scaleY),
          Offset(stroke[i][0] * scaleX, stroke[i][1] * scaleY),
        );
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddShape(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final shapeType = p_['shapeType'] as String;
  final x = (p_['x'] as num).toDouble();
  final y = (p_['y'] as num).toDouble();
  final w = (p_['w'] as num).toDouble();
  final h = (p_['h'] as num).toDouble();
  final pageIndex = p_['pageIndex'] as int? ?? 0;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final idx = pageIndex.clamp(0, doc.pages.count - 1);
    final page = doc.pages[idx];
    final pen = PdfPen(PdfColor(0, 0, 0), width: 2);
    final bounds = Rect.fromLTWH(x, y, w, h);
    switch (shapeType) {
      case 'rect':
        page.graphics.drawRectangle(pen: pen, bounds: bounds);
      case 'circle':
        page.graphics.drawEllipse(bounds, pen: pen);
      case 'line':
        page.graphics.drawLine(pen, Offset(x, y), Offset(x + w, y + h));
      case 'arrow':
        final endX = x + w;
        final endY = y + h;
        page.graphics.drawLine(pen, Offset(x, y), Offset(endX, endY));
        const arrowLen = 14.0;
        final angle = math.atan2(endY - y, endX - x);
        page.graphics.drawLine(pen, Offset(endX, endY),
            Offset(endX - arrowLen * math.cos(angle - 0.45),
                   endY - arrowLen * math.sin(angle - 0.45)));
        page.graphics.drawLine(pen, Offset(endX, endY),
            Offset(endX - arrowLen * math.cos(angle + 0.45),
                   endY - arrowLen * math.sin(angle + 0.45)));
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doTextMarkup(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final searchText = p_['searchText'] as String;
  final markupType = p_['markupType'] as String;
  final pageNum = p_['pageNum'] as int? ?? 0;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final startPage = pageNum > 0 ? (pageNum - 1).clamp(0, doc.pages.count - 1) : 0;
    final endPage = pageNum > 0 ? (pageNum - 1).clamp(0, doc.pages.count - 1) : doc.pages.count - 1;
    int count = 0;
    for (int i = startPage; i <= endPage; i++) {
      final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      for (final line in lines) {
        if (line.text.toLowerCase().contains(searchText.toLowerCase())) {
          final b = line.bounds;
          final color = switch (markupType) {
            'highlight' => PdfColor(255, 235, 0),
            'underline' => PdfColor(0, 0, 200),
            _ => PdfColor(200, 0, 0),
          };
          final annotation = PdfTextMarkupAnnotation(b, searchText, color);
          annotation.textMarkupAnnotationType = switch (markupType) {
            'underline' => PdfTextMarkupAnnotationType.underline,
            'strikethrough' => PdfTextMarkupAnnotationType.strikethrough,
            _ => PdfTextMarkupAnnotationType.highlight,
          };
          doc.pages[i].annotations.add(annotation);
          count++;
        }
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return {..._ok(outputPath, outBytes, pageCount, bytes.length, sw), 'count': count};
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddStickyNote(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final noteText = p_['text'] as String;
  final pageIndex = ((p_['page'] as int? ?? 1) - 1);
  final x = (p_['x'] as num).toDouble();
  final y = (p_['y'] as num).toDouble();
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final idx = pageIndex.clamp(0, doc.pages.count - 1);
    final page = doc.pages[idx];
    final sz = page.getClientSize();
    const boxW = 180.0, boxH = 72.0;
    final bx = x.clamp(0.0, sz.width - boxW);
    final by = y.clamp(0.0, sz.height - boxH);
    page.graphics.drawRectangle(
      pen: PdfPen(PdfColor(0, 0, 0), width: 1.5),
      bounds: Rect.fromLTWH(bx, by, boxW, boxH),
    );
    page.graphics.drawString(
      noteText,
      PdfStandardFont(PdfFontFamily.helvetica, 9),
      brush: PdfSolidBrush(PdfColor(0, 0, 0)),
      bounds: Rect.fromLTWH(bx + 5, by + 5, boxW - 10, boxH - 10),
    );
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return _ok(outputPath, outBytes, pageCount, bytes.length, sw);
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doAddHyperlink(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  final searchText = p_['text'] as String;
  final url = p_['url'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    int count = 0;
    for (int i = 0; i < doc.pages.count; i++) {
      final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      for (final line in lines) {
        if (line.text.toLowerCase().contains(searchText.toLowerCase())) {
          final b = line.bounds;
          final annotation = PdfUriAnnotation(bounds: b, uri: url);
          doc.pages[i].annotations.add(annotation);
          count++;
        }
      }
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pageCount = doc.pages.count;
    doc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return {..._ok(outputPath, outBytes, pageCount, bytes.length, sw), 'count': count};
  } catch (e) {
    return _err(e);
  }
}

Map<String, dynamic> _doRemoveDuplicates(Map<String, dynamic> p_) {
  final sw = Stopwatch()..start();
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final total = doc.pages.count;
    final extractor = PdfTextExtractor(doc);
    final seen = <String>{};
    final keepIndices = <int>[];
    for (int i = 0; i < total; i++) {
      String key = '';
      try {
        key = extractor.extractText(startPageIndex: i, endPageIndex: i)
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
      } catch (_) {}
      if (!seen.contains(key)) {
        seen.add(key);
        keepIndices.add(i);
      }
    }
    final removed = total - keepIndices.length;
    if (removed == 0) {
      final outBytes = Uint8List.fromList(doc.saveSync());
      doc.dispose();
      File(outputPath).writeAsBytesSync(outBytes);
      return {..._ok(outputPath, outBytes, total, bytes.length, sw), 'removed': 0};
    }
    final outDoc = PdfDocument();
    bool first = true;
    for (final idx in keepIndices) {
      if (first) {
        first = false;
        final sz = doc.pages[idx].getClientSize();
        outDoc.pageSettings.size = sz;
        outDoc.pageSettings.margins.all = 0;
        outDoc.pages.add().graphics.drawPdfTemplate(
            doc.pages[idx].createTemplate(), const Offset(0, 0));
      } else {
        _copyPage(outDoc, doc.pages[idx]);
      }
    }
    final outBytes = Uint8List.fromList(outDoc.saveSync());
    doc.dispose();
    outDoc.dispose();
    File(outputPath).writeAsBytesSync(outBytes);
    return {..._ok(outputPath, outBytes, keepIndices.length, bytes.length, sw), 'removed': removed};
  } catch (e) {
    return _err(e);
  }
}


Map<String, dynamic> _doJpegCompress(Map<String, dynamic> p_) {
  final pixels = p_['pixels'] as Uint8List;
  final width = p_['width'] as int;
  final height = p_['height'] as int;
  final quality = p_['quality'] as int;
  final outputPath = p_['outputPath'] as String;
  try {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: pixels.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpegBytes = img.encodeJpg(image, quality: quality);
    File(outputPath).writeAsBytesSync(jpegBytes);
    return {'success': true};
  } catch (e) {
    return {'success': false, 'error': '$e'};
  }
}

// ─── PdfService — public API ─────────────────────────────────────────────────

class PdfService {
  PdfService._();

  static Future<String> _out(String inputPath, String action,
      {String ext = 'pdf'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir =
        Directory(p.join(dir.path, 'PDFist', 'Output'));
    await outDir.create(recursive: true);
    final base = p.basenameWithoutExtension(inputPath);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return p.join(outDir.path, '${base}_${action}_$ts.$ext');
  }

  // ── Core ──────────────────────────────────────────────────────────────────

  static Future<PdfResult> mergePdfs(List<String> inputPaths) async {
    final out = await _out(inputPaths.first, 'merged');
    return _toResult(
        await compute(_doMerge, {'paths': inputPaths, 'outputPath': out}));
  }

  static Future<PdfResult> splitPdf(String path,
      {String mode = 'individual', int start = 1, int end = -1, int n = 1}) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = p.join(dir.path, 'PDFist', 'Output');
    await Directory(outDir).create(recursive: true);
    return _toResult(await compute(_doSplit, {
      'inputPath': path,
      'mode': mode,
      'outputDir': outDir,
      'base': p.basenameWithoutExtension(path),
      'start': start,
      'end': end,
      'n': n,
    }));
  }

  static Future<PdfResult> extractPages(
      String path, List<int> pageIndices) async {
    final out = await _out(path, 'extracted');
    return _toResult(await compute(_doPageOp,
        {'inputPath': path, 'outputPath': out, 'op': 'extract', 'indices': pageIndices}));
  }

  static Future<PdfResult> deletePages(
      String path, List<int> pageIndices) async {
    final out = await _out(path, 'deleted');
    return _toResult(await compute(_doPageOp,
        {'inputPath': path, 'outputPath': out, 'op': 'delete', 'indices': pageIndices}));
  }

  static Future<PdfResult> reorderPages(
      String path, List<int> newOrder) async {
    final out = await _out(path, 'reordered');
    return _toResult(await compute(_doPageOp,
        {'inputPath': path, 'outputPath': out, 'op': 'reorder', 'indices': newOrder}));
  }

  static Future<PdfResult> rotatePdf(String path, int degrees,
      {List<int>? pages}) async {
    final out = await _out(path, 'rotated');
    return _toResult(await compute(_doRotate, {
      'inputPath': path,
      'outputPath': out,
      'degrees': degrees,
      'pageIndices': pages,
    }));
  }

  // ── Compress ──────────────────────────────────────────────────────────────

  static Future<PdfResult> compressPdf(String path, String level) async {
    final out = await _out(path, 'compressed');
    return _toResult(await compute(
        _doCompress, {'inputPath': path, 'outputPath': out, 'level': level}));
  }

  // ── Security ──────────────────────────────────────────────────────────────

  static Future<PdfResult> addPassword(
      String path, String userPassword, String ownerPassword) async {
    final out = await _out(path, 'protected');
    return _toResult(await compute(_doPassword, {
      'inputPath': path,
      'outputPath': out,
      'op': 'add',
      'userPassword': userPassword,
      'ownerPassword': ownerPassword,
    }));
  }

  static Future<PdfResult> removePassword(String path, String password) async {
    final out = await _out(path, 'unlocked');
    return _toResult(await compute(_doPassword, {
      'inputPath': path,
      'outputPath': out,
      'op': 'remove',
      'openPassword': password,
    }));
  }

  // ── Annotate & Edit ───────────────────────────────────────────────────────

  static Future<PdfResult> addWatermark(
      String path, WatermarkConfig cfg) async {
    final out = await _out(path, 'watermarked');
    return _toResult(await compute(_doWatermark, {
      'inputPath': path,
      'outputPath': out,
      'text': cfg.text,
      'opacity': cfg.opacity,
      'fontSize': cfg.fontSize,
      'rotation': cfg.rotation,
    }));
  }

  static Future<PdfResult> addStamp(
      String path, StampType stamp, String position) async {
    final label = switch (stamp) {
      StampType.draft => 'DRAFT',
      StampType.approved => 'APPROVED',
      StampType.confidential => 'CONFIDENTIAL',
      StampType.final_ => 'FINAL',
      StampType.rejected => 'REJECTED',
    };
    final out = await _out(path, 'stamped');
    return _toResult(await compute(_doStamp, {
      'inputPath': path,
      'outputPath': out,
      'stampText': label,
      'position': position,
    }));
  }

  static Future<PdfResult> addPageNumbers(
      String path, PageNumberConfig cfg) async {
    final out = await _out(path, 'numbered');
    return _toResult(await compute(_doPageNumbers, {
      'inputPath': path,
      'outputPath': out,
      'format': cfg.format,
      'position': cfg.position,
      'fontSize': cfg.fontSize,
    }));
  }

  static Future<PdfResult> addHeaderFooter(
      String path, HeaderFooterConfig cfg) async {
    final out = await _out(path, 'headerfooter');
    return _toResult(await compute(_doHeaderFooter, {
      'inputPath': path,
      'outputPath': out,
      'header': cfg.headerText,
      'footer': cfg.footerText,
      'fontSize': cfg.fontSize,
    }));
  }

  static Future<PdfResult> addTextToPdf(
      String path, TextAnnotation ann) async {
    final out = await _out(path, 'text');
    return _toResult(await compute(_doAddText, {
      'inputPath': path,
      'outputPath': out,
      'text': ann.text,
      'x': ann.x,
      'y': ann.y,
      'fontSize': ann.fontSize,
      'pageIndex': ann.pageIndex,
    }));
  }

  static Future<PdfResult> addImageToPdf(String path, String imagePath,
      {double x = 0, double y = 0, double w = 150, double h = 150, int page = 0}) async {
    final out = await _out(path, 'image');
    return _toResult(await compute(_doAddImage, {
      'inputPath': path,
      'outputPath': out,
      'imagePath': imagePath,
      'x': x,
      'y': y,
      'width': w,
      'height': h,
      'pageIndex': page,
    }));
  }

  // ── Convert: To PDF ───────────────────────────────────────────────────────

  static Future<PdfResult> imagesToPdf(List<String> imagePaths) async {
    final out = await _out(imagePaths.first, 'pdf');
    return _toResult(await compute(
        _doImagesToPdf, {'imagePaths': imagePaths, 'outputPath': out}));
  }

  static Future<PdfResult> textToPdf(String path,
      {double fontSize = 12}) async {
    final out = await _out(path, 'pdf');
    return _toResult(await compute(_doTextToPdf,
        {'inputPath': path, 'outputPath': out, 'fontSize': fontSize}));
  }

  // ── Convert: From PDF ─────────────────────────────────────────────────────

  static Future<PdfResult> pdfToText(String path) async {
    final out = await _out(path, 'text', ext: 'txt');
    return _toResult(
        await compute(_doPdfToText, {'inputPath': path, 'outputPath': out}));
  }

  /// Renders each PDF page to a PNG file. Returns list of image file paths.
  /// Runs in main isolate (uses pdfrx which requires platform channels).
  static Future<List<String>> pdfToImages(String path, {int dpi = 150}) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outDir = Directory(p.join(dir.path, 'PDFist', 'Output', 'img_$ts'));
    await outDir.create(recursive: true);

    final doc = await pdfrx.PdfDocument.openFile(path);
    final scale = dpi / 72.0;
    final paths = <String>[];

    for (int i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final pdfImg = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: 0xFFFFFFFF,
      );
      if (pdfImg == null) continue;
      final dartImg = await pdfImg.createImage();
      final byteData = await dartImg.toByteData(format: ImageByteFormat.png);
      dartImg.dispose();
      pdfImg.dispose();
      if (byteData == null) continue;
      final imgPath = p.join(outDir.path, 'page_${i + 1}.png');
      await File(imgPath).writeAsBytes(byteData.buffer.asUint8List());
      paths.add(imgPath);
    }
    return paths;
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static Future<PdfResult> reversePages(String path) async {
    final out = await _out(path, 'reversed');
    return _toResult(await compute(
        _doReversePages, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> interleavePdfs(String pathA, String pathB) async {
    final out = await _out(pathA, 'interleaved');
    return _toResult(await compute(
        _doInterleavePdfs, {'pathA': pathA, 'pathB': pathB, 'outputPath': out}));
  }

  static Future<PdfResult> nUpLayout(String path, int cols, int rows) async {
    final out = await _out(path, '${cols}x${rows}up');
    return _toResult(await compute(
        _doNUp, {'inputPath': path, 'outputPath': out, 'cols': cols, 'rows': rows}));
  }

  static Future<PdfResult> bookletLayout(String path) =>
      nUpLayout(path, 2, 1);

  static Future<PdfResult> updateMetadata(
      String path, PdfMetadata meta) async {
    final out = await _out(path, 'meta');
    return _toResult(await compute(_doUpdateMetadata, {
      'inputPath': path,
      'outputPath': out,
      'title': meta.title,
      'author': meta.author,
      'subject': meta.subject,
      'keywords': meta.keywords,
    }));
  }

  static Future<String> extractAllText(String path) async {
    final r = await compute(_doExtractText, {'inputPath': path});
    return r['text'] as String? ?? '';
  }

  static Future<FileStats> getFileStats(String path) async {
    final bytes = await File(path).readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    final stats = FileStats(
      fileSize: bytes.length,
      pageCount: doc.pages.count,
      title: doc.documentInformation.title,
      author: doc.documentInformation.author,
    );
    doc.dispose();
    return stats;
  }

  static Future<WordCountResult> getWordCount(String path) async {
    final r = await compute(_doExtractText, {'inputPath': path});
    final text = r['text'] as String? ?? '';
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    final bytes = await File(path).readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    final pages = doc.pages.count;
    doc.dispose();
    final charsNoSpaces = text.replaceAll(RegExp(r'\s'), '').length;
    return WordCountResult(words: words, characters: text.length, charsNoSpaces: charsNoSpaces, pages: pages);
  }

  static Future<PdfResult> duplicatePdf(String path) async {
    final out = await _out(path, 'copy');
    final bytes = await File(path).readAsBytes();
    await File(out).writeAsBytes(bytes);
    final doc = PdfDocument(inputBytes: bytes);
    final pc = doc.pages.count;
    doc.dispose();
    return PdfResult(
        success: true,
        outputPath: out,
        outputSize: bytes.length,
        pageCount: pc,
        inputSize: bytes.length);
  }

  static Future<PdfResult> flattenFormFields(String path) async {
    final out = await _out(path, 'flattened');
    final bytes = await File(path).readAsBytes();
    final doc = PdfDocument(inputBytes: bytes);
    if (doc.form.fields.count > 0) {
      doc.form.flattenAllFields();
    }
    final outBytes = Uint8List.fromList(doc.saveSync());
    final pc = doc.pages.count;
    doc.dispose();
    await File(out).writeAsBytes(outBytes);
    return PdfResult(
        success: true,
        outputPath: out,
        outputSize: outBytes.length,
        pageCount: pc,
        inputSize: bytes.length);
  }

  // ── Signature ─────────────────────────────────────────────────────────────

  static Future<PdfResult> addDrawnSignature(
      String path, Uint8List signatureBytes, SignaturePosition pos) async {
    final tmpImg = await _out(path, '_sig_tmp', ext: 'png');
    await File(tmpImg).writeAsBytes(signatureBytes);
    return addImageToPdf(path, tmpImg,
        x: pos.x, y: pos.y, w: pos.width, h: pos.height, page: pos.pageIndex);
  }

  // ── OCR (ML Kit — must run in main isolate) ────────────────────────────────

  static Future<OcrResult> makeSearchable(String path,
      {void Function(double)? onProgress}) async {
    try {
      final imagePaths = await pdfToImages(path, dpi: 150);
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final allText = StringBuffer();
      for (int i = 0; i < imagePaths.length; i++) {
        final result = await recognizer
            .processImage(InputImage.fromFilePath(imagePaths[i]));
        allText.writeln(result.text);
        onProgress?.call((i + 1) / imagePaths.length);
      }
      recognizer.close();

      final outPath = await _out(path, 'searchable');
      final bytes = await File(path).readAsBytes();
      final doc = PdfDocument(inputBytes: bytes);
      final lines = allText.toString().split('\n');
      final linesPerPage =
          doc.pages.count > 0 ? (lines.length / doc.pages.count).ceil() : 1;
      final font = PdfStandardFont(PdfFontFamily.helvetica, 1);
      final brush = PdfSolidBrush(PdfColor(255, 255, 255, 0));
      int lineIdx = 0;
      for (int i = 0; i < doc.pages.count; i++) {
        final page = doc.pages[i];
        final sz = page.getClientSize();
        for (int l = 0; l < linesPerPage && lineIdx < lines.length; l++, lineIdx++) {
          final yPos = (l / linesPerPage) * sz.height;
          page.graphics.drawString(lines[lineIdx], font, brush: brush,
              bounds: Rect.fromLTWH(
                  0, yPos, sz.width, sz.height / linesPerPage));
        }
      }
      final outBytes = Uint8List.fromList(doc.saveSync());
      doc.dispose();
      await File(outPath).writeAsBytes(outBytes);
      return OcrResult(
          success: true,
          outputPath: outPath,
          extractedText: allText.toString());
    } catch (e) {
      return OcrResult(success: false, error: '$e');
    }
  }

  static Future<String> extractTextFromScan(String path,
      {void Function(double)? onProgress}) async {
    final imagePaths = await pdfToImages(path, dpi: 200);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final allText = StringBuffer();
    for (int i = 0; i < imagePaths.length; i++) {
      final result =
          await recognizer.processImage(InputImage.fromFilePath(imagePaths[i]));
      allText.writeln(result.text);
      onProgress?.call((i + 1) / imagePaths.length);
    }
    recognizer.close();
    return allText.toString();
  }

  // ── Thumbnails ────────────────────────────────────────────────────────────

  // ── Phase 4 new methods ────────────────────────────────────────────────────

  static Future<PdfResult> wordToPdf(String path) async {
    final out = await _out(path, 'pdf');
    return _toResult(
        await compute(_doWordToPdf, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> excelToPdf(String path) async {
    final out = await _out(path, 'pdf');
    return _toResult(
        await compute(_doExcelToPdf, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> htmlToPdf(String path) async {
    final out = await _out(path, 'pdf');
    return _toResult(
        await compute(_doHtmlToPdf, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> optimizeForWeb(String path) async {
    final out = await _out(path, 'optimized');
    return _toResult(await compute(
        _doCompress, {'inputPath': path, 'outputPath': out, 'level': 'high'}));
  }

  static Future<PdfResult> repairPdf(String path) async {
    final out = await _out(path, 'repaired');
    return _toResult(
        await compute(_doRepair, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> addPermissions(
      String path, String ownerPassword) async {
    final out = await _out(path, 'perms');
    return _toResult(await compute(_doAddPermissions,
        {'inputPath': path, 'outputPath': out, 'ownerPassword': ownerPassword}));
  }

  static Future<PdfResult> removePermissions(
      String path, String ownerPassword) async {
    final out = await _out(path, 'noperms');
    return _toResult(await compute(_doRemovePermissions,
        {'inputPath': path, 'outputPath': out, 'ownerPassword': ownerPassword}));
  }

  static Future<PdfResult> addDateStamp(
      String path, String dateText, String position) async {
    final out = await _out(path, 'dated');
    return _toResult(await compute(_doDateStamp, {
      'inputPath': path,
      'outputPath': out,
      'dateText': dateText,
      'position': position,
    }));
  }

  static Future<PdfResult> cropPdf(
      String path, double left, double top, double right, double bottom) async {
    final out = await _out(path, 'cropped');
    return _toResult(await compute(_doCropPdf, {
      'inputPath': path,
      'outputPath': out,
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    }));
  }

  static Future<PdfResult> redactAreas(
      String path, List<Map<String, dynamic>> areas) async {
    final out = await _out(path, 'redacted');
    return _toResult(await compute(
        _doRedact, {'inputPath': path, 'outputPath': out, 'areas': areas}));
  }

  static Future<PdfResult> addQrCode(
      String path, String content, String position, double size) async {
    final out = await _out(path, 'qr');
    return _toResult(await compute(_doAddQrCode, {
      'inputPath': path,
      'outputPath': out,
      'content': content,
      'position': position,
      'size': size,
    }));
  }

  static Future<PdfResult> markdownToPdf(String path) async {
    final out = await _out(path, 'pdf', ext: 'pdf');
    return _toResult(await compute(
        _doMarkdownToPdf, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> findAndReplace(
      String path, String find, String replace,
      {bool caseSensitive = false}) async {
    final out = await _out(path, 'replaced');
    return _toResult(await compute(_doFindReplace, {
      'inputPath': path,
      'outputPath': out,
      'find': find,
      'replace': replace,
      'caseSensitive': caseSensitive,
    }));
  }

  static Future<PdfResult> addBookmarks(
      String path, List<Map<String, dynamic>> entries) async {
    final out = await _out(path, 'bookmarked');
    return _toResult(await compute(_doAddBookmarks,
        {'inputPath': path, 'outputPath': out, 'entries': entries}));
  }

  static Future<PdfResult> fillFormFields(
      String path, Map<String, dynamic> fields) async {
    final out = await _out(path, 'filled');
    return _toResult(await compute(_doFillFormFields,
        {'inputPath': path, 'outputPath': out, 'fields': fields}));
  }

  static Future<PdfResult> extractImagesToFiles(String path) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outDir =
        p.join(dir.path, 'PDFist', 'Output', 'images_$ts');
    return _toResult(await compute(_doExtractImagesToDir,
        {'inputPath': path, 'outputDir': outDir}));
  }

  static Future<Map<String, dynamic>> getMetadata(String path) async {
    return compute(_doGetMetadata, {'inputPath': path});
  }

  static Future<Map<String, dynamic>> getFullStats(String path) async {
    return compute(_doGetFullStats, {'inputPath': path});
  }

  static Future<PdfResult> comparePdfsText(
      String pathA, String pathB) async {
    final r = await compute(_doComparePdfsText,
        {'pathA': pathA, 'pathB': pathB});
    final identical = r['identical'] as bool? ?? false;
    final diffLines = r['diffLines'] as int? ?? 0;
    final linesA = r['linesA'] as int? ?? 0;
    final linesB = r['linesB'] as int? ?? 0;
    return PdfResult(
      success: r['success'] as bool? ?? false,
      outputPath: null,
      outputSize: 0,
      pageCount: null,
      inputSize: r['inputSize'] as int? ?? 0,
      processingTimeMs: r['ms'] as int? ?? 0,
      error: identical ? null : '$diffLines line(s) differ',
      extras: {
        'Result': identical ? 'Identical' : 'Different',
        'Lines in A': '$linesA',
        'Lines in B': '$linesB',
        'Differing lines': '$diffLines',
      },
    );
  }

  // ── Thumbnails ────────────────────────────────────────────────────────────

  static Future<List<Uint8List>> getPageThumbnails(String path,
      {int dpi = 72}) async {
    final doc = await pdfrx.PdfDocument.openFile(path);
    final thumbnails = <Uint8List>[];
    final scale = dpi / 72.0;
    for (int i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final pdfImg = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: 0xFFFFFFFF,
      );
      if (pdfImg == null) continue;
      final dartImg = await pdfImg.createImage();
      final byteData = await dartImg.toByteData(format: ImageByteFormat.png);
      dartImg.dispose();
      pdfImg.dispose();
      if (byteData != null) thumbnails.add(byteData.buffer.asUint8List());
    }
    return thumbnails;
  }

  // ── Canvas / annotation tools ─────────────────────────────────────────────

  static Future<PdfResult> drawOnPdf(
      String path, List<List<List<double>>> strokes,
      double canvasW, double canvasH, int pageIndex) async {
    final out = await _out(path, 'drawn');
    return _toResult(await compute(_doDrawOnPdf, {
      'inputPath': path,
      'outputPath': out,
      'strokes': strokes,
      'canvasW': canvasW,
      'canvasH': canvasH,
      'pageIndex': pageIndex,
    }));
  }

  static Future<PdfResult> addShapeToPdf(
      String path, String shapeType,
      double x, double y, double w, double h, int pageIndex) async {
    final out = await _out(path, 'shape');
    return _toResult(await compute(_doAddShape, {
      'inputPath': path,
      'outputPath': out,
      'shapeType': shapeType,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
      'pageIndex': pageIndex,
    }));
  }

  static Future<PdfResult> addTextMarkup(
      String path, String searchText, String markupType, int pageNum) async {
    final out = await _out(path, markupType);
    return _toResult(await compute(_doTextMarkup, {
      'inputPath': path,
      'outputPath': out,
      'searchText': searchText,
      'markupType': markupType,
      'pageNum': pageNum,
    }));
  }

  static Future<PdfResult> addStickyNote(
      String path, String text, int page, double x, double y) async {
    final out = await _out(path, 'note');
    return _toResult(await compute(_doAddStickyNote, {
      'inputPath': path,
      'outputPath': out,
      'text': text,
      'page': page,
      'x': x,
      'y': y,
    }));
  }

  static Future<PdfResult> addHyperlink(
      String path, String searchText, String url) async {
    final out = await _out(path, 'linked');
    return _toResult(await compute(_doAddHyperlink, {
      'inputPath': path,
      'outputPath': out,
      'text': searchText,
      'url': url,
    }));
  }

  static Future<PdfResult> removeDuplicatePages(String path) async {
    final out = await _out(path, 'deduped');
    return _toResult(await compute(
        _doRemoveDuplicates, {'inputPath': path, 'outputPath': out}));
  }


  /// Renders each page to JPEG at [targetDpi] then rebuilds as an image-only
  /// PDF. Genuinely reduces image DPI — text layers are not preserved.
  static Future<PdfResult> downsamplePdf(String path, int targetDpi) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tmpDir = Directory(p.join(dir.path, 'PDFist', 'Output', 'ds_$ts'));
    await tmpDir.create(recursive: true);

    final doc = await pdfrx.PdfDocument.openFile(path);
    final scale = targetDpi / 72.0;
    final jpegPaths = <String>[];

    for (int i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final pdfImg = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: 0xFFFFFFFF,
      );
      if (pdfImg == null) continue;
      final dartImg = await pdfImg.createImage();
      final byteData =
          await dartImg.toByteData(format: ImageByteFormat.rawRgba);
      dartImg.dispose();
      pdfImg.dispose();
      if (byteData == null) continue;
      final jpegPath = p.join(tmpDir.path, 'p${i.toString().padLeft(3, '0')}.jpg');
      await compute(_doJpegCompress, {
        'pixels': byteData.buffer.asUint8List(),
        'width': (page.width * scale).round(),
        'height': (page.height * scale).round(),
        'quality': 75,
        'outputPath': jpegPath,
      });
      jpegPaths.add(jpegPath);
    }

    if (jpegPaths.isEmpty) return PdfResult.failure('No pages rendered');
    final out = await _out(path, 'downsampled');
    final inSize = await File(path).length();
    final r = _toResult(await compute(
        _doImagesToPdf, {'imagePaths': jpegPaths, 'outputPath': out}));
    return PdfResult(
      success: r.success,
      outputPath: r.outputPath,
      outputSize: r.outputSize,
      pageCount: r.pageCount,
      inputSize: inSize.toInt(),
      processingTimeMs: r.processingTimeMs,
      error: r.error,
    );
  }
}
