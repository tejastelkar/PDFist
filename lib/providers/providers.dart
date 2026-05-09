import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// StateProvider lives in legacy.dart in Riverpod 3.x.
import 'package:flutter_riverpod/legacy.dart';
import '../models/history_entry.dart';
import '../models/pdf_models.dart';
import '../services/conversion_service.dart';
import '../services/history_service.dart';
import '../services/pdf_service.dart';

// ─── Auth ─────────────────────────────────────────────────────────────────────

/// True once the user has chosen any auth path (Google, email, or anonymous).
final isAuthenticatedProvider = StateProvider<bool>((ref) => false);

/// Whether the session is anonymous (no Firebase account).
final isAnonymousProvider = StateProvider<bool>((ref) => true);

/// Triggers a re-fetch of history whenever it changes.
final historyRefreshProvider = StateProvider<int>((ref) => 0);

/// Loads the full history list for the current session.
final historyProvider =
    FutureProvider.family<List<HistoryEntry>, int>((ref, _) async {
  return HistoryService.instance.getHistory();
});

// ─── Current operation ────────────────────────────────────────────────────────

/// Params written by ToolScreen before navigating to ProcessingScreen.
final currentOperationProvider = StateProvider<OperationParams?>((ref) => null);

/// The last successful PdfResult, read by ResultScreen.
final lastResultProvider = StateProvider<PdfResult?>((ref) => null);

// ─── PDF Processing ───────────────────────────────────────────────────────────

enum ProcessingStatus { idle, processing, success, failed }

class ProcessingState {
  final ProcessingStatus status;
  final double progress;
  final String message;
  final PdfResult? result;
  final String? error;

  const ProcessingState({
    this.status = ProcessingStatus.idle,
    this.progress = 0,
    this.message = '',
    this.result,
    this.error,
  });

  ProcessingState copyWith({
    ProcessingStatus? status,
    double? progress,
    String? message,
    PdfResult? result,
    String? error,
  }) =>
      ProcessingState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        message: message ?? this.message,
        result: result ?? this.result,
        error: error ?? this.error,
      );
}

class PdfProcessingNotifier extends Notifier<ProcessingState> {
  @override
  ProcessingState build() => const ProcessingState();

  Future<void> process(OperationParams params) async {
    state = const ProcessingState(
        status: ProcessingStatus.processing, progress: 0.05, message: 'Starting…');

    PdfResult? result;
    try {
      final path = params.inputPaths.first;
      final opts = params.options;

      state = state.copyWith(progress: 0.15, message: 'Reading file…');

      result = await _dispatch(params.toolId, path, opts, params.inputPaths);

      if (result.success) {
        // Ensure inputSize is always real even if service forgot to set it.
        final logInputSize = result.inputSize > 0
            ? result.inputSize
            : (params.inputPaths.isNotEmpty
                ? (() { try { return File(params.inputPaths.first).lengthSync(); } catch (_) { return 0; } })()
                : 0);
        final entry = HistoryEntry(
          id: HistoryService.instance.newId(),
          fileName: _basename(path),
          action: _toolLabel(params.toolId),
          timestamp: DateTime.now(),
          fileSize: logInputSize,
          outputSize: result.outputSize,
          pageCount: result.pageCount,
          status: 'success',
        );
        await HistoryService.instance.addEntry(entry);

        state = ProcessingState(
          status: ProcessingStatus.success,
          progress: 1,
          message: 'Done',
          result: result,
        );
      } else {
        _fail(result.error ?? 'Unknown error', result);
      }
    } catch (e) {
      _fail('$e', result);
    }
  }

  void reset() => state = const ProcessingState();

  void _fail(String error, PdfResult? partial) {
    state = ProcessingState(
        status: ProcessingStatus.failed,
        progress: 0,
        message: error,
        result: partial,
        error: error);
  }

  String _basename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.last;
  }

  String _toolLabel(String toolId) {
    const labels = {
      'merge': 'Merge', 'split': 'Split', 'compress': 'Compress',
      'rotate': 'Rotate', 'extract-pages': 'Extract Pages',
      'delete-pages': 'Delete Pages', 'reorder-pages': 'Reorder',
      'watermark': 'Watermark', 'protect': 'Protect', 'unlock': 'Unlock',
      'add-text': 'Add Text', 'add-image': 'Add Image',
      'stamp': 'Stamp', 'page-numbers': 'Page Numbers',
      'header-footer': 'Header/Footer', 'images-to-pdf': 'Images→PDF',
      'text-to-pdf': 'Text→PDF', 'pdf-to-text': 'PDF→Text',
      'pdf-to-word': 'PDF→Word', 'pdf-to-excel': 'PDF→Excel',
      'pdf-to-html': 'PDF→HTML', 'pdf-to-markdown': 'PDF→Markdown',
      'pdf-to-images': 'PDF→Images', 'ocr': 'OCR', 'reverse': 'Reverse',
      'interleave': 'Interleave', 'nup': 'N-Up', 'booklet': 'Booklet',
      'duplicate': 'Duplicate', 'flatten': 'Flatten',
      'optimize-web': 'Optimize for Web', 'downsample': 'Downsample',
      'remove-duplicates': 'Remove Duplicates', 'repair': 'Repair',
      'add-perms': 'Add Permissions', 'remove-perms': 'Remove Permissions',
      'redact': 'Redact', 'crop': 'Crop', 'date-stamp': 'Date Stamp',
      'add-qr': 'Add QR Code',
      'md-to-pdf': 'MD→PDF', 'find-replace': 'Find & Replace',
      'bookmarks': 'Bookmarks', 'fill-form': 'Fill Form',
      'extract-images': 'Extract Images', 'extract-text': 'Extract Text',
      'view-meta': 'View Metadata', 'edit-meta': 'Edit Metadata',
      'word-count': 'Word Count', 'file-stats': 'File Stats',
      'thumbnails': 'Thumbnails', 'compare': 'Compare',
      'ocr-extract': 'OCR Extract', 'ocr-selectable': 'Make Selectable',
      'draw-sig': 'Draw Signature', 'typed-sig': 'Typed Signature',
      'place-sig': 'Place Signature',
      'word-to-pdf': 'Word→PDF', 'excel-to-pdf': 'Excel→PDF',
      'html-to-pdf': 'HTML→PDF', 'draw': 'Draw', 'add-shapes': 'Add Shapes',
      'highlight': 'Highlight', 'underline': 'Underline',
      'strikethrough': 'Strikethrough', 'sticky-notes': 'Sticky Notes',
      'hyperlinks': 'Hyperlinks',
    };
    return labels[toolId] ?? toolId;
  }

  Future<PdfResult> _dispatch(
      String toolId, String path, Map<String, dynamic> opts,
      List<String> allPaths) async {
    state = state.copyWith(progress: 0.3, message: 'Processing…');

    switch (toolId) {
      case 'merge':
        return PdfService.mergePdfs(allPaths);
      case 'split':
        return PdfService.splitPdf(path,
            mode: opts['mode'] as String? ?? 'individual',
            start: opts['start'] as int? ?? 1,
            end: opts['end'] as int? ?? -1,
            n: opts['n'] as int? ?? 1);
      case 'compress':
        return PdfService.compressPdf(
            path, opts['level'] as String? ?? 'medium');
      case 'rotate':
        return PdfService.rotatePdf(path, opts['degrees'] as int? ?? 90,
            pages: opts['pages'] as List<int>?);
      case 'extract-pages':
        return PdfService.extractPages(
            path, List<int>.from(opts['pages'] as List? ?? []));
      case 'delete-pages':
        return PdfService.deletePages(
            path, List<int>.from(opts['pages'] as List? ?? []));
      case 'reorder-pages':
        return PdfService.reorderPages(
            path, List<int>.from(opts['order'] as List? ?? []));
      case 'add-text':
        return PdfService.addTextToPdf(path, TextAnnotation(
          text: opts['text'] as String? ?? '',
          x: (opts['x'] as num?)?.toDouble() ?? 50,
          y: (opts['y'] as num?)?.toDouble() ?? 50,
          fontSize: (opts['fontSize'] as num?)?.toDouble() ?? 14,
          pageIndex: opts['pageIndex'] as int? ?? 0,
        ));
      case 'add-image':
        final imgPath = opts['imagePath'] as String? ?? '';
        if (imgPath.isEmpty) return PdfResult.failure('No image selected');
        return PdfService.addImageToPdf(path, imgPath,
          x: (opts['x'] as num?)?.toDouble() ?? 0,
          y: (opts['y'] as num?)?.toDouble() ?? 0,
          w: (opts['width'] as num?)?.toDouble() ?? 150,
          h: (opts['height'] as num?)?.toDouble() ?? 150,
          page: opts['pageIndex'] as int? ?? 0,
        );
      case 'watermark':
        return PdfService.addWatermark(
            path,
            WatermarkConfig(
              text: opts['text'] as String? ?? 'CONFIDENTIAL',
              opacity: (opts['opacity'] as num?)?.toDouble() ?? 0.3,
              fontSize: (opts['fontSize'] as num?)?.toDouble() ?? 60,
              rotation: (opts['rotation'] as num?)?.toDouble() ?? -45,
            ));
      case 'protect':
        return PdfService.addPassword(path,
            opts['userPassword'] as String? ?? '',
            opts['ownerPassword'] as String? ?? '');
      case 'unlock':
        return PdfService.removePassword(
            path, opts['password'] as String? ?? '');
      case 'stamp':
        final stampStr = opts['stamp'] as String? ?? 'draft';
        final stamp = StampType.values.firstWhere(
            (s) => s.name == stampStr, orElse: () => StampType.draft);
        return PdfService.addStamp(
            path, stamp, opts['position'] as String? ?? 'center');
      case 'page-numbers':
        return PdfService.addPageNumbers(
            path, PageNumberConfig(format: opts['format'] as String? ?? '{page} of {total}'));
      case 'header-footer':
        return PdfService.addHeaderFooter(
            path,
            HeaderFooterConfig(
              headerText: opts['header'] as String?,
              footerText: opts['footer'] as String?,
            ));
      case 'images-to-pdf':
        return PdfService.imagesToPdf(allPaths);
      case 'text-to-pdf':
        return PdfService.textToPdf(path);
      case 'pdf-to-text':
        return PdfService.pdfToText(path);
      case 'pdf-to-word':
        return ConversionService.pdfToWordWithTables(path);
      case 'pdf-to-excel':
        return ConversionService.pdfToExcel(path);
      case 'pdf-to-html':
        return ConversionService.pdfToHtml(path);
      case 'pdf-to-markdown':
        return ConversionService.pdfToMarkdown(path);
      case 'pdf-to-images':
        final imgPaths = await PdfService.pdfToImages(path);
        var totalOut = 0;
        for (final ip in imgPaths) {
          try { totalOut += (await File(ip).length()).toInt(); } catch (_) {}
        }
        final inSize = (await File(path).length()).toInt();
        return PdfResult(
            success: imgPaths.isNotEmpty,
            outputPath: imgPaths.isNotEmpty ? imgPaths.first : null,
            outputSize: totalOut,
            pageCount: imgPaths.length,
            inputSize: inSize,
            error: imgPaths.isEmpty ? 'No pages rendered' : null);
      case 'ocr':
        state = state.copyWith(progress: 0.4, message: 'Running OCR…');
        final r = await PdfService.makeSearchable(path,
            onProgress: (pct) =>
                state = state.copyWith(progress: 0.4 + pct * 0.5));
        return PdfResult(
            success: r.success,
            outputPath: r.outputPath,
            error: r.error);
      case 'reverse':
        return PdfService.reversePages(path);
      case 'interleave':
        if (allPaths.length < 2) {
          return PdfResult.failure('Need two PDFs for interleave');
        }
        return PdfService.interleavePdfs(allPaths[0], allPaths[1]);
      case 'nup':
        final cols = opts['cols'] as int? ?? 2;
        final rows = opts['rows'] as int? ?? 2;
        return PdfService.nUpLayout(path, cols, rows);
      case 'booklet':
        return PdfService.bookletLayout(path);
      case 'duplicate':
        return PdfService.duplicatePdf(path);
      case 'flatten':
        return PdfService.flattenFormFields(path);

      // ── Phase 4 tools ──────────────────────────────────────────────────────
      case 'optimize-web':
        return PdfService.optimizeForWeb(path);

      case 'downsample':
        final dpi = opts['dpi'] as int? ?? 96;
        state = state.copyWith(progress: 0.3, message: 'Rendering pages…');
        return await PdfService.downsamplePdf(path, dpi);

      case 'remove-duplicates':
        return PdfService.removeDuplicatePages(path);

      case 'repair':
        return PdfService.repairPdf(path);

      case 'add-perms':
        return PdfService.addPermissions(
            path, opts['ownerPassword'] as String? ?? 'owner');

      case 'remove-perms':
        return PdfService.removePermissions(
            path, opts['ownerPassword'] as String? ?? '');

      case 'date-stamp':
        final now = DateTime.now();
        final fmt = opts['format'] as String? ?? 'DD/MM/YYYY';
        final dateStr = fmt
            .replaceAll('DD', now.day.toString().padLeft(2, '0'))
            .replaceAll('MM', now.month.toString().padLeft(2, '0'))
            .replaceAll('YYYY', now.year.toString());
        return PdfService.addDateStamp(
            path, dateStr, opts['position'] as String? ?? 'bottomRight');

      case 'add-qr':
        return PdfService.addQrCode(
            path,
            opts['content'] as String? ?? 'https://example.com',
            opts['position'] as String? ?? 'bottomRight',
            (opts['size'] as num?)?.toDouble() ?? 80);

      case 'md-to-pdf':
        return PdfService.markdownToPdf(path);

      case 'find-replace':
        return PdfService.findAndReplace(
            path,
            opts['find'] as String? ?? '',
            opts['replace'] as String? ?? '',
            caseSensitive: opts['caseSensitive'] as bool? ?? false);

      case 'bookmarks':
        final entries = (opts['entries'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        return PdfService.addBookmarks(path, entries);

      case 'fill-form':
        final fields = Map<String, dynamic>.from(opts['fields'] as Map? ?? {});
        return PdfService.fillFormFields(path, fields);

      case 'redact':
        final areas = (opts['areas'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [{'page': 0, 'x': 50.0, 'y': 50.0, 'w': 200.0, 'h': 30.0}];
        return PdfService.redactAreas(path, areas);

      case 'crop':
        return PdfService.cropPdf(
            path,
            (opts['left'] as num?)?.toDouble() ?? 20,
            (opts['top'] as num?)?.toDouble() ?? 20,
            (opts['right'] as num?)?.toDouble() ?? 20,
            (opts['bottom'] as num?)?.toDouble() ?? 20);

      case 'extract-images':
        return PdfService.extractImagesToFiles(path);

      case 'extract-text':
        return PdfService.pdfToText(path);

      case 'compare':
        if (allPaths.length < 2) {
          return PdfResult.failure('Need two PDFs to compare');
        }
        return PdfService.comparePdfsText(allPaths[0], allPaths[1]);

      case 'view-meta': {
        final m = await PdfService.getMetadata(path);
        return PdfResult(
          success: m['success'] as bool? ?? false,
          outputPath: null,
          outputSize: 0,
          pageCount: m['pageCount'] as int? ?? 0,
          inputSize: (await File(path).length()).toInt(),
          extras: {
            'Title': (m['title'] as String?)?.isNotEmpty == true ? m['title'] as String : '—',
            'Author': (m['author'] as String?)?.isNotEmpty == true ? m['author'] as String : '—',
            'Subject': (m['subject'] as String?)?.isNotEmpty == true ? m['subject'] as String : '—',
            'Keywords': (m['keywords'] as String?)?.isNotEmpty == true ? m['keywords'] as String : '—',
            'Creator': (m['creator'] as String?)?.isNotEmpty == true ? m['creator'] as String : '—',
            'Producer': (m['producer'] as String?)?.isNotEmpty == true ? m['producer'] as String : '—',
          },
        );
      }

      case 'edit-meta':
        return PdfService.updateMetadata(
            path,
            PdfMetadata(
              title: opts['title'] as String?,
              author: opts['author'] as String?,
              subject: opts['subject'] as String?,
              keywords: opts['keywords'] as String?,
            ));

      case 'word-count': {
        final r = await PdfService.getWordCount(path);
        return PdfResult(
            success: true,
            outputPath: null,
            outputSize: 0,
            pageCount: r.pages,
            inputSize: (await File(path).length()).toInt(),
            extras: {
              'Pages': '${r.pages}',
              'Words': '${r.words}',
              'Characters': '${r.characters}',
              'Chars (no spaces)': '${r.charsNoSpaces}',
            });
      }

      case 'file-stats': {
        final r = await PdfService.getFullStats(path);
        final sz = r['fileSize'] as int? ?? 0;
        String fmtSz(int b) {
          if (b < 1024) return '$b B';
          if (b < 1048576) return '${(b / 1024).toStringAsFixed(0)} KB';
          return '${(b / 1048576).toStringAsFixed(1)} MB';
        }
        return PdfResult(
            success: r['success'] as bool? ?? false,
            outputPath: null,
            outputSize: 0,
            pageCount: r['pageCount'] as int? ?? 0,
            inputSize: sz,
            extras: {
              'File size': fmtSz(sz),
              'Pages': '${r['pageCount'] ?? 0}',
              'Form fields': '${r['formFields'] ?? 0}',
              'Bookmarks': '${r['bookmarks'] ?? 0}',
            });
      }

      case 'thumbnails': {
        state = state.copyWith(progress: 0.4, message: 'Rendering thumbnails…');
        final thumbs = await PdfService.getPageThumbnails(path, dpi: 72);
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final outDir = Directory(p.join(dir.path, 'PDFist', 'Output', 'thumbs_$ts'));
        await outDir.create(recursive: true);
        var totalSize = 0;
        for (int i = 0; i < thumbs.length; i++) {
          final imgPath = p.join(outDir.path, 'page_${(i + 1).toString().padLeft(3, '0')}.png');
          await File(imgPath).writeAsBytes(thumbs[i]);
          totalSize += thumbs[i].length;
        }
        return PdfResult(
            success: true,
            outputPath: outDir.path,
            outputSize: totalSize,
            pageCount: thumbs.length,
            inputSize: (await File(path).length()).toInt(),
            extras: {'Saved to': outDir.path, 'Count': '${thumbs.length} PNG files'});
      }

      case 'ocr-extract': {
        state = state.copyWith(progress: 0.4, message: 'Running OCR…');
        final text = await PdfService.extractTextFromScan(path,
            onProgress: (pct) =>
                state = state.copyWith(progress: 0.4 + pct * 0.5));
        if (text.isEmpty) return PdfResult.failure('No text found in scan');
        final dir = await getApplicationDocumentsDirectory();
        final outDir = Directory(p.join(dir.path, 'PDFist', 'Output'));
        await outDir.create(recursive: true);
        final base = p.basenameWithoutExtension(path);
        final outPath = p.join(outDir.path,
            '${base}_ocr_${DateTime.now().millisecondsSinceEpoch}.txt');
        await File(outPath).writeAsString(text);
        final outSize = await File(outPath).length();
        return PdfResult(
            success: true,
            outputPath: outPath,
            outputSize: outSize.toInt(),
            pageCount: null,
            inputSize: (await File(path).length()).toInt());
      }

      case 'ocr-selectable': {
        state = state.copyWith(progress: 0.4, message: 'Running OCR…');
        final r = await PdfService.makeSearchable(path,
            onProgress: (pct) =>
                state = state.copyWith(progress: 0.4 + pct * 0.5));
        return PdfResult(
            success: r.success,
            outputPath: r.outputPath,
            outputSize: r.outputPath != null
                ? (await File(r.outputPath!).length()).toInt()
                : 0,
            inputSize: (await File(path).length()).toInt(),
            error: r.error);
      }

      case 'draw-sig':
      case 'typed-sig':
      case 'place-sig': {
        // Signature bytes passed as list of ints via opts if canvas was used
        final sigBytesRaw = opts['signatureBytes'] as List?;
        if (sigBytesRaw == null) {
          return PdfResult.failure('No signature data. Draw a signature first.');
        }
        final sigBytes = Uint8List.fromList(sigBytesRaw.cast<int>());
        return PdfService.addDrawnSignature(
            path, sigBytes,
            SignaturePosition(
              x: (opts['x'] as num?)?.toDouble() ?? 50,
              y: (opts['y'] as num?)?.toDouble() ?? 700,
              width: (opts['width'] as num?)?.toDouble() ?? 200,
              height: (opts['height'] as num?)?.toDouble() ?? 60,
              pageIndex: opts['pageIndex'] as int? ?? 0,
            ));
      }


      case 'word-to-pdf':
        return PdfService.wordToPdf(path);

      case 'excel-to-pdf':
        return PdfService.excelToPdf(path);

      case 'html-to-pdf':
        return PdfService.htmlToPdf(path);

      case 'draw': {
        final strokesRaw = opts['strokes'] as List? ?? [];
        final strokes = strokesRaw
            .map((s) => (s as List)
                .map((pt) => (pt as List).map((v) => (v as num).toDouble()).toList())
                .toList())
            .toList();
        final canvasW = (opts['canvasW'] as num?)?.toDouble() ?? 320;
        final canvasH = (opts['canvasH'] as num?)?.toDouble() ?? 220;
        final pageIdx = opts['pageIndex'] as int? ?? 0;
        if (strokes.isEmpty) return PdfResult.failure('No strokes to draw');
        return PdfService.drawOnPdf(path, strokes, canvasW, canvasH, pageIdx);
      }

      case 'add-shapes':
        return PdfService.addShapeToPdf(
            path,
            opts['shapeType'] as String? ?? 'rect',
            (opts['x'] as num?)?.toDouble() ?? 50,
            (opts['y'] as num?)?.toDouble() ?? 50,
            (opts['w'] as num?)?.toDouble() ?? 200,
            (opts['h'] as num?)?.toDouble() ?? 100,
            opts['pageIndex'] as int? ?? 0);

      case 'highlight':
      case 'underline':
      case 'strikethrough':
        final searchText = opts['searchText'] as String? ?? '';
        if (searchText.isEmpty) return PdfResult.failure('No text to mark up');
        return PdfService.addTextMarkup(
            path,
            searchText,
            opts['markupType'] as String? ?? toolId,
            opts['pageNum'] as int? ?? 0);

      case 'sticky-notes':
        final noteText = opts['text'] as String? ?? '';
        if (noteText.isEmpty) return PdfResult.failure('Note text is empty');
        return PdfService.addStickyNote(
            path,
            noteText,
            opts['page'] as int? ?? 1,
            (opts['x'] as num?)?.toDouble() ?? 50,
            (opts['y'] as num?)?.toDouble() ?? 50);

      case 'hyperlinks':
        final linkText = opts['text'] as String? ?? '';
        final url = opts['url'] as String? ?? '';
        if (linkText.isEmpty || url.isEmpty) {
          return PdfResult.failure('Text and URL are both required');
        }
        return PdfService.addHyperlink(path, linkText, url);

      default:
        return PdfResult.failure('Coming soon');
    }
  }
}

final pdfProcessingProvider =
    NotifierProvider<PdfProcessingNotifier, ProcessingState>(
        PdfProcessingNotifier.new);
