import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/pdf_models.dart';

// ─── Shared helpers ───────────────────────────────────────────────────────────

String _xe(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

bool _isBold(List<PdfFontStyle> s) => s.contains(PdfFontStyle.bold);

// 1 point = 12700 EMU (English Metric Units used by OOXML).
int _emu(double pts) => (pts * 12700).round();

Future<String> _outPath(String inputPath, String suffix) async {
  final dir = await getApplicationDocumentsDirectory();
  final out = Directory(p.join(dir.path, 'PDFist', 'Output'));
  await out.create(recursive: true);
  final base = p.basenameWithoutExtension(inputPath);
  return p.join(out.path, '${base}_${DateTime.now().millisecondsSinceEpoch}.$suffix');
}

// ─── PDF image extraction (pure Dart, no pdfrx) ──────────────────────────────

class _PdfImgInfo {
  final Uint8List pngBytes;
  final double widthPts;
  final double heightPts;
  final double yFromTopPts; // Y of image top from page top, in PDF pts
  final int pageIdx;
  _PdfImgInfo(this.pngBytes, this.widthPts, this.heightPts, this.yFromTopPts, this.pageIdx);
}

/// Reconstructs a valid PNG from a PDF FlateDecode image stream.
/// The IDAT bytes (zlib-compressed PNG-filtered rows) are identical to what
/// PNG stores in its IDAT chunk, so we just wrap them in PNG chunks.
Uint8List _buildPngFromIdat(Uint8List idat, int width, int height, int channels) {
  final buf = BytesBuilder();
  buf.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  void chunk(String type, List<int> data) {
    final t = type.codeUnits;
    final lenBuf = ByteData(4)..setUint32(0, data.length);
    buf.add(lenBuf.buffer.asUint8List());
    buf.add(t);
    buf.add(data);
    final crc = getCrc32([...t, ...data]);
    final crcBuf = ByteData(4)..setUint32(0, crc & 0xFFFFFFFF);
    buf.add(crcBuf.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, channels == 4 ? 6 : channels == 1 ? 0 : 2)
    ..setUint8(10, 0)..setUint8(11, 0)..setUint8(12, 0);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', idat);
  chunk('IEND', const []);
  return buf.toBytes();
}

/// Extracts images embedded in a Syncfusion-generated PDF.
/// Uses raw-byte parsing (no pdfrx) — works in tests and on-device.
List<_PdfImgInfo> _extractPdfImages(Uint8List pdfBytes) {
  final text = latin1.decode(pdfBytes);

  // Locate every PDF object header and the "stream" keyword that follows it.
  // Using object-header→stream (not <<…>>) avoids [^<>] breaking on adjacent ">>" chars.
  final objHeaderRe = RegExp(r'(\d+)\s+0\s+obj');

  // Step 1 — find all FlateDecode image XObjects.
  final objImages = <String, ({Uint8List idat, int w, int h})>{};
  for (final objM in objHeaderRe.allMatches(text)) {
    final objNum = objM.group(1)!;
    final searchFrom = objM.end;
    final streamIdx = text.indexOf('stream', searchFrom);
    if (streamIdx < 0 || streamIdx - searchFrom > 1500) continue;
    final hdr = text.substring(searchFrom, streamIdx);
    if (!hdr.contains('/Subtype') || !hdr.contains('Image')) continue;
    if (!hdr.contains('FlateDecode')) continue;
    final wM = RegExp(r'/Width\s+(\d+)').firstMatch(hdr);
    final hM = RegExp(r'/Height\s+(\d+)').firstMatch(hdr);
    final lenM = RegExp(r'/Length\s+(\d+)').firstMatch(hdr);
    if (wM == null || hM == null || lenM == null) continue;
    final len = int.parse(lenM.group(1)!);
    int ds = streamIdx + 6;
    if (ds < pdfBytes.length && pdfBytes[ds] == 0x0D) ds++;
    if (ds < pdfBytes.length && pdfBytes[ds] == 0x0A) ds++;
    if (ds + len > pdfBytes.length) continue;
    objImages[objNum] = (
      idat: pdfBytes.sublist(ds, ds + len),
      w: int.parse(wM.group(1)!),
      h: int.parse(hM.group(1)!),
    );
  }
  if (objImages.isEmpty) return [];

  // Step 2 — collect ALL GUID→ObjNum from resource dicts (no filter yet).
  final guidToObj = <String, String>{};
  final guidRe = RegExp(
    r'/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+(\d+)\s+0\s+R',
    caseSensitive: false,
  );
  for (final m in guidRe.allMatches(text)) {
    final obj = m.group(2)!;
    if (objImages.containsKey(obj)) {
      guidToObj[m.group(1)!.toLowerCase()] = obj;
    }
  }

  // Step 3 — decode page content streams and find cm+Do image placements.
  final placements = <({String objNum, double wPts, double hPts, double yFromTop, int pageIdx})>[];
  int pageIdx = 0;
  final cmDoRe = RegExp(
    r'([\-\d\.]+)\s+([\-\d\.]+)\s+([\-\d\.]+)\s+([\-\d\.]+)\s+([\-\d\.]+)\s+([\-\d\.]+)\s+cm\s*'
    r'/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s+Do',
    caseSensitive: false,
  );
  for (final objM in objHeaderRe.allMatches(text)) {
    final searchFrom = objM.end;
    final streamIdx = text.indexOf('stream', searchFrom);
    if (streamIdx < 0 || streamIdx - searchFrom > 1500) continue;
    final hdr = text.substring(searchFrom, streamIdx);
    if (hdr.contains('/Subtype')) continue; // XObject — skip
    if (!hdr.contains('FlateDecode')) continue;
    final lenM = RegExp(r'/Length\s+(\d+)').firstMatch(hdr);
    if (lenM == null) continue;
    final len = int.parse(lenM.group(1)!);
    int ds = streamIdx + 6;
    if (ds < pdfBytes.length && pdfBytes[ds] == 0x0D) ds++;
    if (ds < pdfBytes.length && pdfBytes[ds] == 0x0A) ds++;
    if (ds + len > pdfBytes.length) continue;
    String decoded;
    try {
      decoded = latin1.decode(ZLibCodec(raw: false).decode(pdfBytes.sublist(ds, ds + len)));
    } catch (_) { continue; }
    if (decoded.length < 50) continue; // skip tiny placeholder streams
    for (final doM in cmDoRe.allMatches(decoded)) {
      final a = double.tryParse(doM.group(1)!) ?? 0;
      final d = double.tryParse(doM.group(4)!) ?? 0;
      final f = double.tryParse(doM.group(6)!) ?? 0;
      final guid = doM.group(7)!.toLowerCase();
      final objNum = guidToObj[guid];
      if (objNum != null) {
        placements.add((
          objNum: objNum,
          wPts: a.abs(),
          hPts: d.abs(),
          yFromTop: f.abs(),
          pageIdx: pageIdx,
        ));
      }
    }
    pageIdx++; // each large content stream = one page
  }

  // Step 4 — reconstruct PNGs and return.
  return placements.map((pl) {
    final img = objImages[pl.objNum];
    if (img == null) return null;
    final uncompressed = ZLibCodec(raw: false).decode(img.idat);
    final ch = ((uncompressed.length / img.h) - 1) ~/ img.w;
    final png = _buildPngFromIdat(img.idat, img.w, img.h, ch.clamp(1, 4));
    return _PdfImgInfo(png, pl.wPts, pl.hPts, pl.yFromTop, pl.pageIdx);
  }).whereType<_PdfImgInfo>().toList();
}

// ─── Table detection ──────────────────────────────────────────────────────────

/// Returns groups of words within a line separated by gaps > [minGap] pts.
/// If the line has <2 groups, returns empty → not a table row.
List<List<TextWord>> _columnGroups(TextLine line, {double minGap = 12.0}) {
  final words = line.wordCollection;
  if (words.length < 2) return [];
  final groups = <List<TextWord>>[[words[0]]];
  for (int i = 1; i < words.length; i++) {
    final gap = words[i].bounds.left - words[i - 1].bounds.right;
    if (gap > minGap) {
      groups.add([words[i]]);
    } else {
      groups.last.add(words[i]);
    }
  }
  return groups.length >= 2 ? groups : [];
}

/// Joins a group of words into a single cell string.
String _cellText(List<TextWord> group) =>
    group.map((w) => w.text).join(' ').trim();

/// Returns the left-edge X of a word group.
double _groupX(List<TextWord> group) => group.first.bounds.left;

/// Check if two column X-lists are "compatible" (each X close to one in [ref]).
bool _colsMatch(List<double> ref, List<double> cand, double tol) {
  if (cand.isEmpty) return false;
  for (final cx in cand) {
    if (!ref.any((rx) => (rx - cx).abs() <= tol)) return false;
  }
  return true;
}

// ─── Document model ───────────────────────────────────────────────────────────

sealed class _Block {}

class _ParaBlock extends _Block {
  final String text;
  final bool isBold;
  final double fontSize;
  _ParaBlock(this.text, this.isBold, this.fontSize);
}

class _TableBlock extends _Block {
  final List<List<String>> rows; // rows[r][c]
  final bool hasHeaderRow;
  _TableBlock(this.rows, {this.hasHeaderRow = true});
}

class _ImageBlock extends _Block {
  final int imageIndex; // index into page's image list
  final double widthPts;
  final double heightPts;
  _ImageBlock(this.imageIndex, this.widthPts, this.heightPts);
}

class _PageModel {
  final List<_Block> blocks;
  final List<Uint8List> images; // PNG bytes, one per embedded image
  _PageModel(this.blocks, this.images);
}

// ─── PDF content analysis (main isolate — uses both syncfusion + pdfrx) ───────

Future<_PageModel> _analysePage(
    PdfDocument sfDoc, int pageIndex, pdfrx.PdfDocument? pdfrxDoc,
    {List<_PdfImgInfo> extractedImages = const []}) async {
  final extractor = PdfTextExtractor(sfDoc);
  final lines = extractor.extractTextLines(
      startPageIndex: pageIndex, endPageIndex: pageIndex);

  // Sort lines top-to-bottom.
  lines.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));

  // ── Detect image blocks by rendering the page ──────────────────────────────
  // We render the page at 144 DPI and look for non-white content outside text
  // bounding boxes to detect embedded images.
  final pageImages = <Uint8List>[];
  final imageBlocks = <({int insertAfterLine, Uint8List png, double w, double h})>[];

  if (pdfrxDoc != null && pageIndex < pdfrxDoc.pages.length) {
    final pdfrxPage = pdfrxDoc.pages[pageIndex];
    const dpi = 144.0;
    final scale = dpi / 72.0;
    final pdfImg = await pdfrxPage.render(
      fullWidth: pdfrxPage.width * scale,
      fullHeight: pdfrxPage.height * scale,
      backgroundColor: 0xFFFFFFFF,
    );
    if (pdfImg != null) {
      final dartImg = await pdfImg.createImage();
      final byteData =
          await dartImg.toByteData(format: ui.ImageByteFormat.png);
      dartImg.dispose();
      pdfImg.dispose();
      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();

        // Check if page has non-text content by sampling pixels.
        // We use a simple heuristic: if the page has images (drawn via
        // PdfBitmap), the rendered PNG will have non-white pixel regions
        // not covered by text bounds.
        final hasNonText = _pageHasImageContent(pdfImg.width, pdfImg.height,
            lines, pdfrxPage.width, pdfrxPage.height, scale);

        if (hasNonText) {
          pageImages.add(pngBytes);
          imageBlocks.add((
            insertAfterLine: -1, // before any text
            png: pngBytes,
            w: pdfrxPage.width * 0.6, // 60% of page width in pts
            h: pdfrxPage.height * 0.6 * (pdfrxPage.height / pdfrxPage.width),
          ));
        }
      }
    }
  } else {
    // Use pre-extracted images (from _extractPdfImages) — no pdfrx needed.
    for (final img in extractedImages) {
      pageImages.add(img.pngBytes);
      // Find the last text line whose top Y is above the image.
      int insertAfter = -1;
      for (int li = 0; li < lines.length; li++) {
        if (lines[li].bounds.top <= img.yFromTopPts) {
          insertAfter = li;
        } else {
          break;
        }
      }
      imageBlocks.add((
        insertAfterLine: insertAfter,
        png: img.pngBytes,
        w: img.widthPts,
        h: img.heightPts,
      ));
    }
  }

  // ── Detect table regions ───────────────────────────────────────────────────
  // Build a list of (lineIndex, groups) for rows that look like table rows.
  final candidateRows = <int>[];
  final rowGroups = <int, List<List<TextWord>>>{};
  for (int i = 0; i < lines.length; i++) {
    final groups = _columnGroups(lines[i], minGap: 12);
    if (groups.isNotEmpty) {
      candidateRows.add(i);
      rowGroups[i] = groups;
    }
  }

  // Group consecutive candidate rows into table regions.
  final tableRegions = <List<int>>[];
  if (candidateRows.isNotEmpty) {
    var region = [candidateRows[0]];
    for (int k = 1; k < candidateRows.length; k++) {
      final prev = candidateRows[k - 1];
      final curr = candidateRows[k];
      final prevGroups = rowGroups[prev]!;
      final currGroups = rowGroups[curr]!;
      final prevXs = prevGroups.map(_groupX).toList();
      final currXs = currGroups.map(_groupX).toList();
      // Same table if: consecutive lines and columns are compatible.
      if (curr - prev <= 2 && _colsMatch(prevXs, currXs, 25.0)) {
        region.add(curr);
      } else {
        if (region.length >= 2) tableRegions.add(region);
        region = [curr];
      }
    }
    if (region.length >= 2) tableRegions.add(region);
  }

  final tableLineSet = tableRegions.expand((r) => r).toSet();

  // ── Build page blocks ──────────────────────────────────────────────────────
  final blocks = <_Block>[];
  imageBlocks.sort((a, b) => a.insertAfterLine.compareTo(b.insertAfterLine));
  int imgPtr = 0;

  void flushImages(int beforeLineIdx) {
    while (imgPtr < imageBlocks.length &&
        imageBlocks[imgPtr].insertAfterLine < beforeLineIdx) {
      final id = imageBlocks[imgPtr++];
      blocks.add(_ImageBlock(pageImages.indexOf(id.png), id.w, id.h));
    }
  }

  // Images that appear before all text.
  flushImages(0);

  int lineIdx = 0;
  while (lineIdx < lines.length) {
    final line = lines[lineIdx];

    final region = tableRegions.where((r) => r.first == lineIdx).firstOrNull;
    if (region != null) {
      final firstGroups = rowGroups[region.first]!;
      final colXs = firstGroups.map(_groupX).toList();
      final numCols = colXs.length;
      final tableRows = <List<String>>[];
      for (final rowLineIdx in region) {
        final groups = rowGroups[rowLineIdx]!;
        final cells = List<String>.filled(numCols, '');
        for (final g in groups) {
          final gx = _groupX(g);
          int bestCol = 0;
          double bestDist = double.infinity;
          for (int c = 0; c < numCols; c++) {
            final d = (colXs[c] - gx).abs();
            if (d < bestDist) { bestDist = d; bestCol = c; }
          }
          cells[bestCol] = [cells[bestCol], _cellText(g)]
              .where((s) => s.isNotEmpty)
              .join(' ');
        }
        tableRows.add(cells);
      }
      blocks.add(_TableBlock(tableRows, hasHeaderRow: tableRows.length > 1));
      lineIdx = region.last + 1;
    } else {
      if (!tableLineSet.contains(lineIdx)) {
        final text = line.text.trim();
        if (text.isNotEmpty) {
          blocks.add(_ParaBlock(text, _isBold(line.fontStyle), line.fontSize));
        }
      }
      lineIdx++;
    }
    flushImages(lineIdx);
  }

  // Any remaining images at end of page.
  while (imgPtr < imageBlocks.length) {
    final id = imageBlocks[imgPtr++];
    blocks.add(_ImageBlock(pageImages.indexOf(id.png), id.w, id.h));
  }

  return _PageModel(blocks, pageImages);
}

// Heuristic: page has image content if the text bounding boxes cover < 40%
// of the page area (suggesting non-text visuals are present).
bool _pageHasImageContent(
    int imgW, int imgH,
    List<TextLine> lines,
    double pageW, double pageH,
    double scale) {
  double textArea = 0;
  for (final line in lines) {
    textArea += line.bounds.width * line.bounds.height;
  }
  final pageArea = pageW * pageH;
  return pageArea > 0 && textArea / pageArea < 0.40;
}

// ─── DOCX builder ─────────────────────────────────────────────────────────────

Uint8List _buildDocxBytes(Map<String, dynamic> params) {
  final pages = params['pages'] as List<Map<String, dynamic>>;

  final archive = Archive();
  final mediaFiles = <String, Uint8List>{};
  int imgCounter = 0;
  int rIdBase = 3; // rId1=styles, rId2=settings, rId3+ = images

  // Collect images across all pages and assign rIds.
  final pageImageRIds = <int, List<String>>{}; // pageIdx → [rId, ...]
  for (int pi = 0; pi < pages.length; pi++) {
    final pageData = pages[pi];
    final imgs = pageData['images'] as List<Map<String, dynamic>>? ?? [];
    final rIds = <String>[];
    for (final imgMap in imgs) {
      final bytes = imgMap['bytes'] as Uint8List;
      final rId = 'rId${rIdBase++}';
      imgCounter++;
      final fname = 'word/media/image$imgCounter.png';
      mediaFiles[fname] = bytes;
      rIds.add(rId);
    }
    pageImageRIds[pi] = rIds;
  }

  // ── Build document.xml body ────────────────────────────────────────────────
  final body = StringBuffer();
  int drawingId = 1;

  for (int pi = 0; pi < pages.length; pi++) {
    final pageData = pages[pi];
    final blocks = pageData['blocks'] as List<Map<String, dynamic>>;
    final imgs = pageData['images'] as List<Map<String, dynamic>>? ?? [];
    final rIds = pageImageRIds[pi] ?? [];

    if (pi > 0) {
      body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
    }

    for (final block in blocks) {
      final type = block['type'] as String;

      if (type == 'para') {
        final text = block['text'] as String;
        final bold = block['bold'] as bool;
        final fontSize = (block['fontSize'] as num).toDouble();
        final halfPts = (fontSize * 2).round().clamp(16, 72);
        final isH1 = fontSize >= 18 && bold;
        final isH2 = fontSize >= 14 && bold;

        body.write('<w:p>');
        if (isH1 || isH2) {
          body.write(
              '<w:pPr><w:pStyle w:val="${isH1 ? "Heading1" : "Heading2"}"/></w:pPr>');
        }
        body.write('<w:r><w:rPr>');
        if (bold) body.write('<w:b/>');
        body.write('<w:sz w:val="$halfPts"/><w:szCs w:val="$halfPts"/>');
        body.write('</w:rPr>');
        body.write('<w:t xml:space="preserve">${_xe(text)}</w:t>');
        body.write('</w:r></w:p>');
      } else if (type == 'table') {
        final rows = block['rows'] as List<List<String>>;
        final hasHeader = block['hasHeader'] as bool? ?? true;
        final numCols = rows.isEmpty ? 0 : rows[0].length;
        final colWidthDxa = (numCols > 0) ? (9360 ~/ numCols) : 1000;

        body.write('<w:tbl>');
        body.write('<w:tblPr>');
        body.write('<w:tblW w:w="9360" w:type="dxa"/>');
        body.write('<w:tblBorders>');
        for (final side in ['top', 'left', 'bottom', 'right', 'insideH', 'insideV']) {
          body.write(
              '<w:$side w:val="single" w:sz="4" w:space="0" w:color="000000"/>');
        }
        body.write('</w:tblBorders>');
        body.write('<w:tblCellMar>');
        body.write('<w:top w:w="80" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>');
        body.write(
            '<w:bottom w:w="80" w:type="dxa"/><w:right w:w="108" w:type="dxa"/>');
        body.write('</w:tblCellMar>');
        body.write('</w:tblPr>');

        for (int ri = 0; ri < rows.length; ri++) {
          final isHeader = ri == 0 && hasHeader;
          body.write('<w:tr>');
          if (isHeader) {
            body.write(
                '<w:trPr><w:shd w:val="clear" w:color="auto" w:fill="1F1F1F" '
                'w:themeFill="text1"/><w:tblHeader/></w:trPr>');
          }
          for (int ci = 0; ci < rows[ri].length; ci++) {
            final cell = rows[ri][ci];
            body.write('<w:tc>');
            body.write(
                '<w:tcPr><w:tcW w:w="$colWidthDxa" w:type="dxa"/>');
            if (isHeader) {
              body.write(
                  '<w:shd w:val="clear" w:color="auto" w:fill="1F1F1F"/>');
            } else if (ri % 2 == 0) {
              body.write(
                  '<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>');
            }
            body.write('</w:tcPr>');
            body.write('<w:p><w:r><w:rPr>');
            if (isHeader) {
              body.write(
                  '<w:b/><w:color w:val="FFFFFF"/><w:sz w:val="22"/><w:szCs w:val="22"/>');
            } else {
              body.write('<w:sz w:val="20"/><w:szCs w:val="20"/>');
            }
            body.write('</w:rPr>');
            body.write('<w:t xml:space="preserve">${_xe(cell)}</w:t>');
            body.write('</w:r></w:p></w:tc>');
          }
          body.write('</w:tr>');
        }
        body.write('</w:tbl>');
        body.write('<w:p/>'); // blank line after table
      } else if (type == 'image') {
        final imgIdx = block['imageIndex'] as int;
        final widthPts = (block['widthPts'] as num).toDouble();
        final heightPts = (block['heightPts'] as num).toDouble();
        if (imgIdx < rIds.length && imgIdx < imgs.length) {
          final rId = rIds[imgIdx];
          final cx = _emu(widthPts);
          final cy = _emu(heightPts);
          body.write('<w:p><w:r><w:drawing>');
          body.write(
              '<wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">');
          body.write('<wp:extent cx="$cx" cy="$cy"/>');
          body.write('<wp:docPr id="$drawingId" name="Image$drawingId"/>');
          body.write(
              '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">');
          body.write(
              '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">');
          body.write(
              '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">');
          body.write('<pic:nvPicPr>'
              '<pic:cNvPr id="$drawingId" name="Image$drawingId"/>'
              '<pic:cNvPicPr/>'
              '</pic:nvPicPr>');
          body.write('<pic:blipFill>'
              '<a:blip r:embed="$rId" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>'
              '<a:stretch><a:fillRect/></a:stretch>'
              '</pic:blipFill>');
          body.write('<pic:spPr>'
              '<a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
              '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
              '</pic:spPr>');
          body.write('</pic:pic></a:graphicData></a:graphic>');
          body.write('</wp:inline>');
          body.write('</w:drawing></w:r></w:p>');
          drawingId++;
        }
      }
    }
  }

  // ── document.xml ──────────────────────────────────────────────────────────
  final docXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document '
      'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
      '<w:body>$body'
      '<w:sectPr>'
      '<w:pgSz w:w="12240" w:h="15840"/>'
      '<w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080"/>'
      '</w:sectPr></w:body></w:document>';

  // ── Image relationships ────────────────────────────────────────────────────
  final imgRels = StringBuffer();
  int imgRIdIdx = rIdBase - imgCounter;
  for (int i = 1; i <= imgCounter; i++) {
    imgRels.write(
        '<Relationship Id="rId${imgRIdIdx++}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/image$i.png"/>');
  }

  void addXml(String name, String content) {
    final data = utf8.encode(content);
    archive.addFile(ArchiveFile(name, data.length, data));
  }

  void addBytes(String name, Uint8List bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  // Build the correct rId list for the rels file.
  // rId1=styles, rId2=settings, rId3..N = images in order.
  final allImgRels = StringBuffer();
  int rIdCtr = 3;
  for (int i = 1; i <= imgCounter; i++) {
    allImgRels.write(
        '<Relationship Id="rId$rIdCtr" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="media/image$i.png"/>');
    rIdCtr++;
  }

  // Content types — add PNG if we have images.
  final pngType = imgCounter > 0
      ? '<Default Extension="png" ContentType="image/png"/>'
      : '';
  addXml('[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '$pngType'
      '<Override PartName="/word/document.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '<Override PartName="/word/styles.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
      '<Override PartName="/word/settings.xml" '
      'ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
      '</Types>');

  addXml('_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
      'Target="word/document.xml"/>'
      '</Relationships>');

  addXml('word/_rels/document.xml.rels',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/>'
      '<Relationship Id="rId2" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" '
      'Target="settings.xml"/>'
      '$allImgRels'
      '</Relationships>');

  addXml('word/settings.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:defaultTabStop w:val="720"/>'
      '</w:settings>');

  addXml('word/styles.xml',
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/>'
      '</w:rPr></w:rPrDefault></w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
      '<w:name w:val="Normal"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading1">'
      '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
      '<w:pPr><w:outlineLvl w:val="0"/>'
      '<w:spacing w:before="240" w:after="120"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr>'
      '</w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2">'
      '<w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
      '<w:pPr><w:outlineLvl w:val="1"/>'
      '<w:spacing w:before="200" w:after="100"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/></w:rPr>'
      '</w:style>'
      '</w:styles>');

  addXml('word/document.xml', docXml);

  // Add all media files.
  for (final entry in mediaFiles.entries) {
    addBytes(entry.key, entry.value);
  }

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

// ─── Public ConversionService ─────────────────────────────────────────────────

class ConversionService {
  ConversionService._();

  static PdfResult _toResult(Map<String, dynamic> m) => PdfResult(
        success: m['success'] as bool,
        outputPath: m['outputPath'] as String?,
        outputSize: (m['outputSize'] as int?) ?? 0,
        pageCount: m['pageCount'] as int?,
        inputSize: (m['inputSize'] as int?) ?? 0,
        error: m['error'] as String?,
      );

  // ── Basic converters (isolate-safe, no pdfrx) ──────────────────────────────

  static Future<PdfResult> pdfToWord(String path) async {
    final out = await _outPath(path, 'docx');
    return _toResult(await compute(_buildDocx, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> pdfToExcel(String path) async {
    final out = await _outPath(path, 'xlsx');
    return _toResult(await compute(_buildXlsx, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> pdfToHtml(String path) async {
    final out = await _outPath(path, 'html');
    return _toResult(await compute(_buildHtml, {'inputPath': path, 'outputPath': out}));
  }

  static Future<PdfResult> pdfToMarkdown(String path) async {
    final out = await _outPath(path, 'md');
    return _toResult(await compute(_buildMarkdown, {'inputPath': path, 'outputPath': out}));
  }

  /// Tables-aware conversion — no image rendering (runs in compute, testable).
  /// Tables in the PDF are detected from text-position alignment and emitted
  /// as proper Word [w:tbl] elements. Images are skipped.
  static Future<PdfResult> pdfToWordWithTables(String path) async {
    final sw = Stopwatch()..start();
    try {
      final inputSize = await File(path).length();
      final pdfBytes = File(path).readAsBytesSync();
      final sfDoc = PdfDocument(inputBytes: pdfBytes);
      final pageCount = sfDoc.pages.count;

      // Extract images from raw PDF bytes (no pdfrx — works in tests + on-device).
      final allImages = _extractPdfImages(pdfBytes);

      final pagesData = <Map<String, dynamic>>[];
      for (int i = 0; i < pageCount; i++) {
        final pageImgs = allImages.where((img) => img.pageIdx == i).toList();
        final model = await _analysePage(sfDoc, i, null, extractedImages: pageImgs);
        pagesData.add(_pageModelToMap(model));
      }
      sfDoc.dispose();
      final outPath = await _outPath(path, 'docx');
      final docxBytes = await compute(_buildDocxBytes, {
        'pages': pagesData,
        'title': p.basenameWithoutExtension(path),
      });
      await File(outPath).writeAsBytes(docxBytes);
      sw.stop();
      return PdfResult(
        success: true,
        outputPath: outPath,
        outputSize: docxBytes.length,
        pageCount: pageCount,
        inputSize: inputSize,
        processingTimeMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      return PdfResult.failure('$e');
    }
  }

  /// Full conversion: tables as Word tables, images rendered and embedded.
  /// Runs in the main isolate (pdfrx requires platform channels / Android only).
  static Future<PdfResult> pdfToWordRich(String path) async {
    final sw = Stopwatch()..start();
    try {
      final inputSize = await File(path).length();
      final sfDoc = PdfDocument(inputBytes: File(path).readAsBytesSync());
      final pageCount = sfDoc.pages.count;

      // Open same file with pdfrx for image rendering.
      final pdfrxDoc = await pdfrx.PdfDocument.openFile(path);

      final pagesData = <Map<String, dynamic>>[];
      for (int i = 0; i < pageCount; i++) {
        final model = await _analysePage(sfDoc, i, pdfrxDoc);
        pagesData.add(_pageModelToMap(model));
      }
      sfDoc.dispose();

      final outPath = await _outPath(path, 'docx');
      final docxBytes = await compute(_buildDocxBytes, {
        'pages': pagesData,
        'title': p.basenameWithoutExtension(path),
      });

      await File(outPath).writeAsBytes(docxBytes);
      sw.stop();

      return PdfResult(
        success: true,
        outputPath: outPath,
        outputSize: docxBytes.length,
        pageCount: pageCount,
        inputSize: inputSize,
        processingTimeMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      return PdfResult.failure('$e');
    }
  }

  static Map<String, dynamic> _pageModelToMap(_PageModel model) {
    final blocks = <Map<String, dynamic>>[];
    for (final b in model.blocks) {
      switch (b) {
        case _ParaBlock(:final text, :final isBold, :final fontSize):
          blocks.add({'type': 'para', 'text': text, 'bold': isBold, 'fontSize': fontSize});
        case _TableBlock(:final rows, :final hasHeaderRow):
          blocks.add({'type': 'table', 'rows': rows, 'hasHeader': hasHeaderRow});
        case _ImageBlock(:final imageIndex, :final widthPts, :final heightPts):
          blocks.add({
            'type': 'image',
            'imageIndex': imageIndex,
            'widthPts': widthPts,
            'heightPts': heightPts,
          });
      }
    }
    final images = model.images
        .map((bytes) => <String, dynamic>{'bytes': bytes})
        .toList();
    return {'blocks': blocks, 'images': images};
  }
}

// ─── Isolate functions (basic converters) ─────────────────────────────────────

Map<String, dynamic> _buildDocx(Map<String, dynamic> p_) {
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final pageCount = doc.pages.count;
    final bodyXml = StringBuffer();

    for (int i = 0; i < pageCount; i++) {
      if (i > 0) bodyXml.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      for (final line in lines) {
        final text = line.text.trim();
        if (text.isEmpty) { bodyXml.write('<w:p/>'); continue; }
        final isHeading = line.fontSize >= 14;
        final bold = isHeading || _isBold(line.fontStyle);
        final halfPts = (line.fontSize * 2).round().clamp(16, 72);
        bodyXml.write('<w:p>');
        if (isHeading) bodyXml.write('<w:pPr><w:pStyle w:val="Heading1"/></w:pPr>');
        bodyXml.write('<w:r><w:rPr>');
        if (bold) bodyXml.write('<w:b/>');
        bodyXml.write('<w:sz w:val="$halfPts"/><w:szCs w:val="$halfPts"/>');
        bodyXml.write('</w:rPr><w:t xml:space="preserve">${_xe(text)}</w:t></w:r></w:p>');
      }
    }
    doc.dispose();

    final archive = Archive();
    void add(String name, String content) {
      final data = utf8.encode(content);
      archive.addFile(ArchiveFile(name, data.length, data));
    }

    add('[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
        '</Types>');
    add('_rels/.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>');
    add('word/_rels/document.xml.rels',
        '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
        '</Relationships>');
    add('word/settings.xml',
        '<?xml version="1.0" encoding="UTF-8"?><w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:defaultTabStop w:val="720"/></w:settings>');
    add('word/styles.xml',
        '<?xml version="1.0" encoding="UTF-8"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
        '<w:pPr><w:outlineLvl w:val="0"/><w:spacing w:before="240" w:after="120"/></w:pPr>'
        '<w:rPr><w:b/><w:sz w:val="40"/><w:szCs w:val="40"/></w:rPr></w:style>'
        '</w:styles>');
    add('word/document.xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$bodyXml'
        '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>'
        '<w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080"/>'
        '</w:sectPr></w:body></w:document>');

    final zipBytes = ZipEncoder().encode(archive);
    File(outputPath).writeAsBytesSync(Uint8List.fromList(zipBytes));
    return {'success': true, 'outputPath': outputPath, 'outputSize': zipBytes.length, 'pageCount': pageCount, 'inputSize': bytes.length};
  } catch (e) {
    return {'success': false, 'error': '$e'};
  }
}

Map<String, dynamic> _buildXlsx(Map<String, dynamic> p_) {
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final pageCount = doc.pages.count;
    final sharedStrings = <String>[];
    final sheetXmls = <String>[];
    for (int pg = 0; pg < pageCount; pg++) {
      final text = extractor.extractText(startPageIndex: pg, endPageIndex: pg);
      final lines = text.split('\n').map((l) => l.trim()).toList();
      final rowsXml = StringBuffer();
      int rowNum = 1;
      for (final line in lines) {
        if (line.isEmpty) { rowNum++; continue; }
        final siIdx = sharedStrings.length;
        sharedStrings.add(line);
        rowsXml.write('<row r="$rowNum"><c r="A$rowNum" t="s"><v>$siIdx</v></c></row>');
        rowNum++;
      }
      sheetXmls.add('<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>$rowsXml</sheetData></worksheet>');
    }
    doc.dispose();
    final siXml = sharedStrings.map((s) => '<si><t>${_xe(s)}</t></si>').join();
    final sheetsAttr = List.generate(pageCount, (i) => '<sheet name="Page ${i + 1}" sheetId="${i + 1}" r:id="rId${i + 2}"/>').join();
    final sheetRels = List.generate(pageCount, (i) => '<Relationship Id="rId${i + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join();
    final overrides = List.generate(pageCount, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join();
    final archive = Archive();
    void add(String name, String content) {
      final data = utf8.encode(content);
      archive.addFile(ArchiveFile(name, data.length, data));
    }
    add('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>$overrides</Types>');
    add('_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    add('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>$sheetRels</Relationships>');
    add('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>$sheetsAttr</sheets></workbook>');
    add('xl/styles.xml', '<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts><font><sz val="11"/><name val="Calibri"/></font></fonts><fills><fill><patternFill patternType="none"/></fill></fills><borders><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs></styleSheet>');
    add('xl/sharedStrings.xml', '<?xml version="1.0" encoding="UTF-8"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="${sharedStrings.length}" uniqueCount="${sharedStrings.length}">$siXml</sst>');
    for (int i = 0; i < pageCount; i++) { add('xl/worksheets/sheet${i + 1}.xml', sheetXmls[i]); }
    final zipBytes = ZipEncoder().encode(archive);
    File(outputPath).writeAsBytesSync(Uint8List.fromList(zipBytes));
    return {'success': true, 'outputPath': outputPath, 'outputSize': zipBytes.length, 'pageCount': pageCount, 'inputSize': bytes.length};
  } catch (e) {
    return {'success': false, 'error': '$e'};
  }
}

Map<String, dynamic> _buildHtml(Map<String, dynamic> p_) {
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final pageCount = doc.pages.count;
    final html = StringBuffer();
    html.write('<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>${_xe(p.basenameWithoutExtension(inputPath))}</title>'
        '<style>body{font-family:Georgia,serif;max-width:800px;margin:40px auto;padding:0 20px;line-height:1.6;color:#111}'
        '.page{margin-bottom:60px;padding-bottom:40px;border-bottom:1px solid #ccc}'
        '.pg{color:#999;font-size:12px;margin-bottom:12px}p{margin:0 0 .8em}</style></head><body>');
    for (int i = 0; i < pageCount; i++) {
      final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      html.write('<div class="page"><div class="pg">— Page ${i + 1} —</div>');
      for (final line in lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;
        final tag = line.fontSize >= 18 ? 'h1' : line.fontSize >= 14 ? 'h2' : 'p';
        html.write('<$tag>${_xe(text)}</$tag>');
      }
      html.write('</div>');
    }
    html.write('</body></html>');
    doc.dispose();
    File(outputPath).writeAsStringSync(html.toString());
    return {'success': true, 'outputPath': outputPath, 'outputSize': File(outputPath).lengthSync(), 'pageCount': pageCount, 'inputSize': bytes.length};
  } catch (e) {
    return {'success': false, 'error': '$e'};
  }
}

Map<String, dynamic> _buildMarkdown(Map<String, dynamic> p_) {
  final inputPath = p_['inputPath'] as String;
  final outputPath = p_['outputPath'] as String;
  try {
    final bytes = File(inputPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(doc);
    final pageCount = doc.pages.count;
    final md = StringBuffer();
    md.writeln('# ${p.basenameWithoutExtension(inputPath)}\n');
    for (int i = 0; i < pageCount; i++) {
      if (i > 0) md.writeln('\n---\n');
      md.writeln('*Page ${i + 1}*\n');
      final lines = extractor.extractTextLines(startPageIndex: i, endPageIndex: i);
      for (final line in lines) {
        final text = line.text.trim();
        if (text.isEmpty) { md.writeln(); continue; }
        if (line.fontSize >= 18) { md.writeln('## $text\n'); }
        else if (line.fontSize >= 14) { md.writeln('### $text\n'); }
        else if (_isBold(line.fontStyle)) { md.writeln('**$text**\n'); }
        else { md.writeln('$text\n'); }
      }
    }
    doc.dispose();
    File(outputPath).writeAsStringSync(md.toString());
    return {'success': true, 'outputPath': outputPath, 'outputSize': File(outputPath).lengthSync(), 'pageCount': pageCount, 'inputSize': bytes.length};
  } catch (e) {
    return {'success': false, 'error': '$e'};
  }
}
