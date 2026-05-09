// ─── Result ───────────────────────────────────────────────────────────────────

class PdfResult {
  final bool success;
  final String? outputPath;
  final int inputSize;
  final int outputSize;
  final int? pageCount;
  final String? error;
  final int processingTimeMs;
  final Map<String, String>? extras;

  const PdfResult({
    required this.success,
    this.outputPath,
    this.inputSize = 0,
    this.outputSize = 0,
    this.pageCount,
    this.error,
    this.processingTimeMs = 0,
    this.extras,
  });

  factory PdfResult.failure(String error, {int inputSize = 0}) =>
      PdfResult(success: false, error: error, inputSize: inputSize);

  String get sizeBeforeFormatted => _formatBytes(inputSize);
  String get sizeAfterFormatted => _formatBytes(outputSize);

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ─── Operation params ─────────────────────────────────────────────────────────

class OperationParams {
  final String toolId;
  final List<String> inputPaths;
  final Map<String, dynamic> options;

  const OperationParams({
    required this.toolId,
    required this.inputPaths,
    this.options = const {},
  });
}

// ─── Mode/config enums ────────────────────────────────────────────────────────

enum CompressionLevel { low, medium, high }

enum SplitMode { byPageRange, everyNPages, individualPages }

enum ImageFormat { png, jpg }

enum StampType { draft, approved, confidential, final_, rejected }

enum NUpLayout { twoUp, fourUp, sixUp }

// ─── Annotation / config types ────────────────────────────────────────────────

class TextAnnotation {
  final String text;
  final double x;
  final double y;
  final double fontSize;
  final int pageIndex;
  TextAnnotation({
    required this.text,
    required this.x,
    required this.y,
    this.fontSize = 12,
    this.pageIndex = 0,
  });
}

class WatermarkConfig {
  final String text;
  final double opacity;
  final double fontSize;
  final double rotation;
  WatermarkConfig({
    required this.text,
    this.opacity = 0.3,
    this.fontSize = 60,
    this.rotation = -45,
  });
}

class PageNumberConfig {
  final String position; // 'bottom-center' | 'bottom-right' | 'top-center'
  final String format; // '{page}' | '{page} of {total}'
  final double fontSize;
  PageNumberConfig({
    this.position = 'bottom-center',
    this.format = '{page} of {total}',
    this.fontSize = 10,
  });
}

class HeaderFooterConfig {
  final String? headerText;
  final String? footerText;
  final double fontSize;
  HeaderFooterConfig({this.headerText, this.footerText, this.fontSize = 10});
}

class SignaturePosition {
  final double x;
  final double y;
  final double width;
  final double height;
  final int pageIndex;
  SignaturePosition({
    required this.x,
    required this.y,
    this.width = 150,
    this.height = 50,
    this.pageIndex = 0,
  });
}

class QrConfig {
  final String data;
  final double x;
  final double y;
  final double size;
  final int pageIndex;
  QrConfig({
    required this.data,
    required this.x,
    required this.y,
    this.size = 100,
    this.pageIndex = 0,
  });
}

class PdfMetadata {
  final String? title;
  final String? author;
  final String? subject;
  final String? keywords;
  final String? creator;
  PdfMetadata({
    this.title,
    this.author,
    this.subject,
    this.keywords,
    this.creator,
  });
}

class WordCountResult {
  final int words;
  final int characters;
  final int pages;
  const WordCountResult({
    required this.words,
    required this.characters,
    required this.pages,
  });
}

class FileStats {
  final int fileSize;
  final int pageCount;
  final String? title;
  final String? author;
  final bool isEncrypted;
  final DateTime? createdDate;
  const FileStats({
    required this.fileSize,
    required this.pageCount,
    this.title,
    this.author,
    this.isEncrypted = false,
    this.createdDate,
  });
}

class CompareResult {
  final bool identical;
  final int differentPages;
  final List<int> changedPageIndices;
  const CompareResult({
    required this.identical,
    required this.differentPages,
    required this.changedPageIndices,
  });
}

// ─── OCR result ───────────────────────────────────────────────────────────────

class OcrResult {
  final bool success;
  final String? outputPath;
  final String extractedText;
  final String? error;
  const OcrResult({
    required this.success,
    this.outputPath,
    this.extractedText = '',
    this.error,
  });
}
