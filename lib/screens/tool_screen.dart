import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/pdf_models.dart';
import '../models/tool_catalog.dart';
import '../models/tool_model.dart';
import '../providers/providers.dart';
import '../services/pdf_service.dart';
import '../theme/app_theme.dart';
import '../widgets/shared.dart';

class ToolScreen extends ConsumerStatefulWidget {
  final String toolId;
  const ToolScreen({super.key, required this.toolId});
  @override
  ConsumerState<ToolScreen> createState() => _ToolScreenState();
}

class _ToolScreenState extends ConsumerState<ToolScreen> {
  final List<String> _filePaths = [];
  String _quality = 'medium';
  String _rotation = '90';
  String _splitMode = 'individual';
  int _splitStart = 1;
  int _splitEnd = 1;
  int _splitEveryN = 2;
  String _stampType = 'draft';
  String _watermarkText = 'CONFIDENTIAL';
  String _passwordField = '';
  String _headerText = '';
  String _footerText = '';
  String _addText = '';
  String _imagePath = '';
  int _nupCols = 2;
  int _nupRows = 2;
  String _ownerPassword = '';
  String _findText = '';
  String _replaceText = '';
  bool _caseSensitive = false;
  String _qrContent = '';
  String _qrPosition = 'bottomRight';
  String _stampPosition = 'bottomRight';
  String _metaTitle = '';
  String _metaAuthor = '';
  String _metaSubject = '';
  String _metaKeywords = '';
  double _cropLeft = 20;
  double _cropTop = 20;
  double _cropRight = 20;
  double _cropBottom = 20;
  final List<Map<String, dynamic>> _bookmarkEntries = [];
  final _bookmarkTitleCtrl = TextEditingController();
  final _bookmarkPageCtrl = TextEditingController();

  // Signature (draw-sig / typed-sig / place-sig)
  final List<List<Offset>> _strokePoints = [];
  List<Offset>? _currentStroke;
  Uint8List? _signatureBytes;
  String _typedName = '';

  // Redact areas
  final List<Map<String, dynamic>> _redactAreas = [];
  final _redactPageCtrl = TextEditingController();
  final _redactXCtrl = TextEditingController();
  final _redactYCtrl = TextEditingController();
  final _redactWCtrl = TextEditingController();
  final _redactHCtrl = TextEditingController();
  bool _picking = false;
  String? _sizeInfo;
  int _pageCount = 0;
  List<int> _selectedPages = [];
  List<int> _pageOrder = [];

  // Draw tool (freehand on PDF page)
  final List<List<Offset>> _drawOnPdfStrokes = [];
  List<Offset>? _drawOnPdfCurrentStroke;
  double _drawOnPdfCanvasW = 0;
  double _drawOnPdfCanvasH = 220;
  int _drawOnPdfPageIdx = 0;

  // Add shapes
  String _shapeType = 'rect';
  double _shapeX = 50;
  double _shapeY = 50;
  double _shapeW = 200;
  double _shapeH = 100;
  int _shapePageIdx = 0;

  // Text markup (highlight / underline / strikethrough)
  String _markupText = '';
  int _markupPage = 0; // 0 = all pages

  // Sticky notes
  String _stickyText = '';
  int _stickyPage = 1;
  double _stickyX = 50;
  double _stickyY = 50;

  // Hyperlinks
  String _linkText = '';
  String _linkUrl = '';

  // Downsample DPI
  int _downsampleDpi = 96;

  // Fill Form
  Map<String, TextEditingController> _formFieldControllers = {};
  bool _loadingFormFields = false;

  // Watermark — stored so it isn't recreated on every rebuild
  late final TextEditingController _watermarkCtrl;

  // Protect — separate owner password
  String _protectOwnerPassword = '';
  late final TextEditingController _ownerPasswordCtrl;

  // Watermark controls
  double _watermarkOpacity = 0.3;
  double _watermarkFontSize = 60;
  double _watermarkRotation = -45;

  // Add Text placement
  double _addTextX = 50;
  double _addTextY = 50;
  double _addTextFontSize = 14;
  int _addTextPage = 0;

  // Add Image placement
  double _addImageX = 0;
  double _addImageY = 0;
  double _addImageW = 150;
  double _addImageH = 150;
  int _addImagePage = 0;

  // Signature placement (draw-sig / typed-sig / place-sig)
  double _sigX = 50;
  double _sigY = 700;
  double _sigW = 200;
  double _sigH = 60;
  int _sigPage = 0;

  // Page 1 thumbnail preview
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    _watermarkCtrl = TextEditingController(text: _watermarkText);
    _ownerPasswordCtrl = TextEditingController();
  }

  PdfTool get tool => findTool(widget.toolId) ?? kTools.first;
  bool get _hasFile => _filePaths.isNotEmpty;
  bool get _needsTwoFiles =>
      ['interleave', 'compare'].contains(widget.toolId);

  String get _primaryPath => _hasFile ? _filePaths.first : '';
  String get _displayName => _hasFile
      ? _primaryPath.split('/').last
      : 'No file selected';

  static const _outputExt = {
    'split': 'zip',
    'pdf-to-word': 'docx',
    'pdf-to-excel': 'xlsx',
    'pdf-to-html': 'html',
    'pdf-to-markdown': 'md',
    'pdf-to-text': 'txt',
    'ocr-extract': 'txt',
    'pdf-to-images': 'png',
    'extract-images': 'jpg',
  };

  // Tools that analyse the PDF but produce no output file.
  static const _analysisOnlyTools = {
    'view-meta', 'word-count', 'file-stats', 'compare',
    'thumbnails', 'extract-images', 'extract-text',
  };

  String get _outputFilename {
    final base = _displayName.split('.').first;
    final ext = _outputExt[widget.toolId] ?? 'pdf';
    return '${widget.toolId}_$base.$ext';
  }

  String get _dropzoneFileLabel => switch (widget.toolId) {
    'word-to-pdf' => 'Drop a DOCX here',
    'excel-to-pdf' => 'Drop an XLSX here',
    'html-to-pdf' => 'Drop an HTML file here',
    'md-to-pdf' => 'Drop a Markdown file here',
    'text-to-pdf' => 'Drop a TXT file here',
    'images-to-pdf' => 'Drop images here',
    _ => 'Drop a PDF here',
  };

  Future<void> _pickFile({bool multi = false, bool append = false}) async {
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
        allowMultiple: multi || widget.toolId == 'merge',
      );
      if (result != null) {
        final paths = result.paths.whereType<String>().toList();
        int pc = 0;
        final isPdf = _allowedExtensions.contains('pdf');
        if (isPdf && paths.isNotEmpty && !append) {
          try {
            final bytes = File(paths.first).readAsBytesSync();
            final doc = PdfDocument(inputBytes: bytes);
            pc = doc.pages.count;
            doc.dispose();
          } catch (_) {}
        }
        setState(() {
          if (!append) _filePaths.clear();
          _filePaths.addAll(paths);
          _sizeInfo = _formatSize(result.files.fold<int>(0, (sum, f) => sum + f.size));
          if (pc > 0) {
            _pageCount = pc;
            _selectedPages = [];
            _pageOrder = List.generate(pc, (i) => i);
          }
        });
        if (widget.toolId == 'fill-form' && paths.isNotEmpty && !append) {
          _loadFormFields(paths.first);
        }
        if (isPdf && paths.isNotEmpty && !append) {
          _loadThumbnail(paths.first);
        }
      }
    } finally {
      setState(() => _picking = false);
    }
  }

  Future<void> _loadFormFields(String path) async {
    setState(() => _loadingFormFields = true);
    try {
      final bytes = await File(path).readAsBytes();
      final doc = PdfDocument(inputBytes: bytes);
      final names = <String>[];
      for (int i = 0; i < doc.form.fields.count; i++) {
        final name = doc.form.fields[i].name;
        if (name != null && name.isNotEmpty) { names.add(name); }
      }
      doc.dispose();
      for (final c in _formFieldControllers.values) { c.dispose(); }
      setState(() {
        _formFieldControllers = {for (final n in names) n: TextEditingController()};
      });
    } catch (_) {
    } finally {
      setState(() => _loadingFormFields = false);
    }
  }

  Future<void> _loadThumbnail(String path) async {
    try {
      final thumbs = await PdfService.getPageThumbnails(path, dpi: 72);
      if (thumbs.isNotEmpty && mounted) {
        setState(() => _thumbnailBytes = thumbs.first);
      }
    } catch (_) {}
  }

  Future<void> _pickImageFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result != null && result.paths.isNotEmpty) {
      setState(() => _imagePath = result.paths.first ?? '');
    }
  }

  // Returns the allowed file extensions for this tool's primary file picker.
  List<String> get _allowedExtensions => switch (widget.toolId) {
        'images-to-pdf' => ['jpg', 'jpeg', 'png', 'webp'],
        'word-to-pdf' => ['docx'],
        'excel-to-pdf' => ['xlsx'],
        'html-to-pdf' => ['html', 'htm'],
        'md-to-pdf' => ['md', 'markdown'],
        'text-to-pdf' => ['txt'],
        _ => ['pdf'],
      };

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _process() {
    if (!_hasFile) return;
    final opts = _collectOptions();
    ref.read(currentOperationProvider.notifier).state = OperationParams(
      toolId: widget.toolId,
      inputPaths: List.from(_filePaths),
      options: opts,
    );
    ref.read(pdfProcessingProvider.notifier).reset();
    context.go(
        '/processing/${widget.toolId}/${Uri.encodeComponent(_displayName)}');
  }

  Map<String, dynamic> _collectOptions() {
    return switch (widget.toolId) {
      'compress' => {'level': _quality},
      'rotate' => {'degrees': int.tryParse(_rotation) ?? 90},
      'split' => {
          'mode': _splitMode,
          'start': _splitStart,
          'end': _splitEnd,
          'n': _splitEveryN,
        },
      'protect' => {
          'userPassword': _passwordField,
          'ownerPassword': _protectOwnerPassword.isEmpty ? _passwordField : _protectOwnerPassword,
        },
      'unlock' => {'password': _passwordField},
      'watermark' => {
          'text': _watermarkText,
          'opacity': _watermarkOpacity,
          'fontSize': _watermarkFontSize,
          'rotation': _watermarkRotation,
        },
      'stamp' => {'stamp': _stampType, 'position': _stampPosition},
      'header-footer' => {'header': _headerText, 'footer': _footerText},
      'add-text' => {
          'text': _addText,
          'x': _addTextX,
          'y': _addTextY,
          'fontSize': _addTextFontSize,
          'pageIndex': _addTextPage,
        },
      'add-image' => {
          'imagePath': _imagePath,
          'x': _addImageX,
          'y': _addImageY,
          'width': _addImageW,
          'height': _addImageH,
          'pageIndex': _addImagePage,
        },
      'extract-pages' => {'pages': _selectedPages},
      'delete-pages' => {'pages': _selectedPages},
      'reorder-pages' => {'order': _pageOrder},
      'nup' => {'cols': _nupCols, 'rows': _nupRows},
      'add-perms' => {'ownerPassword': _ownerPassword},
      'remove-perms' => {'ownerPassword': _ownerPassword},
      'find-replace' => {
          'find': _findText,
          'replace': _replaceText,
          'caseSensitive': _caseSensitive,
        },
      'add-qr' => {'content': _qrContent, 'position': _qrPosition, 'size': 80.0},
      'date-stamp' => {'position': _stampPosition, 'format': 'DD/MM/YYYY'},
      'bookmarks' => {'entries': _bookmarkEntries},
      'edit-meta' => {
          'title': _metaTitle,
          'author': _metaAuthor,
          'subject': _metaSubject,
          'keywords': _metaKeywords,
        },
      'crop' => {
          'left': _cropLeft,
          'top': _cropTop,
          'right': _cropRight,
          'bottom': _cropBottom,
        },
      'draw-sig' || 'typed-sig' || 'place-sig' => {
          'signatureBytes': _signatureBytes?.toList(),
          'x': _sigX,
          'y': _sigY,
          'width': _sigW,
          'height': _sigH,
          'pageIndex': _sigPage,
        },
      'redact' => {'areas': _redactAreas},
      'draw' => {
          'strokes': _drawOnPdfStrokes
              .map((s) => s.map((o) => [o.dx, o.dy]).toList())
              .toList(),
          'canvasW': _drawOnPdfCanvasW,
          'canvasH': _drawOnPdfCanvasH,
          'pageIndex': _drawOnPdfPageIdx,
        },
      'add-shapes' => {
          'shapeType': _shapeType,
          'x': _shapeX,
          'y': _shapeY,
          'w': _shapeW,
          'h': _shapeH,
          'pageIndex': _shapePageIdx,
        },
      'highlight' => {'searchText': _markupText, 'markupType': 'highlight', 'pageNum': _markupPage},
      'underline' => {'searchText': _markupText, 'markupType': 'underline', 'pageNum': _markupPage},
      'strikethrough' => {'searchText': _markupText, 'markupType': 'strikethrough', 'pageNum': _markupPage},
      'sticky-notes' => {
          'text': _stickyText,
          'page': _stickyPage,
          'x': _stickyX,
          'y': _stickyY,
        },
      'hyperlinks' => {'text': _linkText, 'url': _linkUrl},
      'downsample' => {'dpi': _downsampleDpi},
      'fill-form' => {
          'fields': {
            for (final e in _formFieldControllers.entries)
              if (e.value.text.isNotEmpty) e.key: e.value.text,
          }
        },
      _ => {},
    };
  }

  @override
  void dispose() {
    _bookmarkTitleCtrl.dispose();
    _bookmarkPageCtrl.dispose();
    _redactPageCtrl.dispose();
    _redactXCtrl.dispose();
    _redactYCtrl.dispose();
    _redactWCtrl.dispose();
    _redactHCtrl.dispose();
    for (final c in _formFieldControllers.values) { c.dispose(); }
    _watermarkCtrl.dispose();
    _ownerPasswordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top nav
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.line),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(Icons.arrow_back,
                              color: AppColors.text, size: 18),
                        ),
                      ),
                      const Spacer(),
                      Text(tool.num,
                          style: AppTextStyles.mono(10, color: AppColors.muted)),
                    ],
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow('Tool / ${tool.num}'),
                      const SizedBox(height: 8),
                      Text('${tool.label}.',
                          style: AppTextStyles.display(44,
                              weight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(
                        '${tool.desc}. Everything stays on your device.',
                        style: AppTextStyles.body(14, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // File drop zone
                        if (!_hasFile)
                          _buildDropzone()
                        else
                          _buildFileRow(),
                        // Second file slot for interleave/compare
                        if (_needsTwoFiles && _filePaths.length < 2) ...[
                          const SizedBox(height: 12),
                          _buildDropzone(label: 'ADD SECOND PDF', append: true),
                        ],
                        // Options
                        if (_hasFile) ...[
                          const SizedBox(height: 28),
                          const Eyebrow('Options'),
                          const SizedBox(height: 14),
                          _buildOptions(context),
                          if (!_analysisOnlyTools.contains(widget.toolId)) ...[
                            Container(
                                height: 1,
                                color: AppColors.lineStrong,
                                margin: const EdgeInsets.symmetric(vertical: 24)),
                            const Eyebrow('Output'),
                            const SizedBox(height: 14),
                            _buildOutputRow('Filename', _outputFilename),
                            _buildOutputRow('Save location', '/PDFist/Output'),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sticky CTA
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [AppColors.bg, Colors.transparent],
                  stops: [0.7, 1.0],
                ),
              ),
              child: FillButton(
                label: _picking ? 'Selecting…' : tool.label,
                icon: const Icon(Icons.arrow_forward, color: AppColors.bg, size: 18),
                enabled: _canRun && !_picking,
                onTap: _canRun ? _process : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropzone({String label = 'OR TAP TO BROWSE', bool append = false}) {
    return GestureDetector(
      onTap: _picking ? null : () => _pickFile(append: append),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.text),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            _picking
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        color: AppColors.text, strokeWidth: 2))
                : const Icon(Icons.upload, color: AppColors.text, size: 32),
            const SizedBox(height: 14),
            Text(_dropzoneFileLabel,
                style: AppTextStyles.body(15, weight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.mono(10, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.text),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (_thumbnailBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(_thumbnailBytes!,
                  width: 36, height: 48, fit: BoxFit.cover),
            )
          else
            const PdfFileThumbnail(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _filePaths.length > 1
                      ? '${_filePaths.length} files selected'
                      : _displayName,
                  style: AppTextStyles.body(14, weight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _sizeInfo ?? '',
                  style: AppTextStyles.mono(11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _filePaths.clear()),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.close,
                  color: AppColors.text.withValues(alpha: 0.6), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  bool get _canRun {
    if (!_hasFile) return false;
    if (_needsTwoFiles && _filePaths.length < 2) return false;
    if (widget.toolId == 'extract-pages' && _selectedPages.isEmpty) return false;
    if (widget.toolId == 'delete-pages' && _selectedPages.isEmpty) return false;
    if (widget.toolId == 'delete-pages' && _pageCount > 0 && _selectedPages.length >= _pageCount) return false;
    if (widget.toolId == 'add-image' && _imagePath.isEmpty) return false;
    if (widget.toolId == 'split' && _splitMode == 'byPageRange' && _splitEnd < _splitStart) return false;
    if (widget.toolId == 'split' && _splitMode == 'everyN' && _splitEveryN < 1) return false;
    if (const {'draw-sig', 'typed-sig', 'place-sig'}.contains(widget.toolId) && _signatureBytes == null) {
      return false;
    }
    if (widget.toolId == 'redact' && _redactAreas.isEmpty) return false;
    if (widget.toolId == 'draw' && _drawOnPdfStrokes.isEmpty) return false;
    if (const {'highlight', 'underline', 'strikethrough'}.contains(widget.toolId) && _markupText.isEmpty) return false;
    if (widget.toolId == 'sticky-notes' && _stickyText.isEmpty) return false;
    if (widget.toolId == 'hyperlinks' && (_linkText.isEmpty || _linkUrl.isEmpty)) return false;
    return true;
  }

  Widget _buildOptions(BuildContext context) {
    final id = widget.toolId;
    if (id == 'compress') return _compressOpts();
    if (id == 'rotate') return _rotateOpts();
    if (id == 'split') return _splitOpts();
    if (id == 'protect' || id == 'unlock') return _passwordOpts();
    if (id == 'watermark') return _watermarkOpts();
    if (id == 'stamp') return _stampOpts(context);
    if (id == 'header-footer') return _headerFooterOpts();
    if (id == 'add-text') return _addTextOpts();
    if (id == 'add-image') return _addImageOpts();
    if (id == 'extract-pages') return _pageSelectOpts(canSelectAll: true);
    if (id == 'delete-pages') return _pageSelectOpts(canSelectAll: false);
    if (id == 'reorder-pages') return _reorderOpts();
    if (id == 'nup') return _nupOpts();
    if (id == 'merge') return _mergeListOpts(context);
    if (id == 'add-perms' || id == 'remove-perms') return _permissionsOpts();
    if (id == 'find-replace') return _findReplaceOpts();
    if (id == 'add-qr') return _addQrOpts();
    if (id == 'date-stamp') return _dateStampOpts();
    if (id == 'bookmarks') return _bookmarksOpts();
    if (id == 'edit-meta') return _editMetaOpts();
    if (id == 'crop') return _cropOpts();
    if (id == 'draw-sig' || id == 'place-sig') return _drawSigOpts();
    if (id == 'typed-sig') return _typedSigOpts();
    if (id == 'redact') return _redactOpts();
    if (id == 'draw') return _drawOnPdfOpts();
    if (id == 'add-shapes') return _addShapesOpts();
    if (id == 'highlight' || id == 'underline' || id == 'strikethrough') return _textMarkupOpts();
    if (id == 'sticky-notes') return _stickyNotesOpts();
    if (id == 'hyperlinks') return _hyperlinksOpts();
    if (id == 'downsample') return _downsampleOpts();
    if (id == 'fill-form') return _fillFormOpts();
    return Text(
      'Ready to ${tool.label.toLowerCase()}. Tap the button below.',
      style: AppTextStyles.body(13, color: AppColors.muted),
    );
  }

  Widget _compressOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quality', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          Row(
            children: [
              {'id': 'low', 'label': 'Low', 'sub': '~80% smaller'},
              {'id': 'medium', 'label': 'Medium', 'sub': '~50% smaller'},
              {'id': 'high', 'label': 'High', 'sub': '~25% smaller'},
            ].map((q) {
              final active = _quality == q['id'];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _quality = q['id']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(right: q['id'] != 'high' ? 8 : 0),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active ? AppColors.text : AppColors.bg,
                      border: Border.all(
                          color: active ? AppColors.text : AppColors.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q['label']!,
                            style: AppTextStyles.display(14,
                                    weight: FontWeight.w600)
                                .copyWith(
                                    color: active
                                        ? AppColors.bg
                                        : AppColors.text)),
                        const SizedBox(height: 4),
                        Text(q['sub']!,
                            style: AppTextStyles.mono(9,
                                color: active
                                    ? AppColors.bg.withValues(alpha: 0.7)
                                    : AppColors.faint)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );

  Widget _rotateOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rotation', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          Row(
            children: ['0', '90', '180', '270'].map((r) {
              final active = _rotation == r;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _rotation = r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(right: r != '270' ? 8 : 0),
                    height: 64,
                    decoration: BoxDecoration(
                      color: active ? AppColors.text : AppColors.bg,
                      border: Border.all(
                          color: active ? AppColors.text : AppColors.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text('$r°',
                        style: AppTextStyles.display(16,
                                weight: FontWeight.w600)
                            .copyWith(
                                color:
                                    active ? AppColors.bg : AppColors.text)),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      );

  Widget _splitOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Split mode', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          ...['individual', 'byPageRange', 'everyN'].map((m) {
            final label = switch (m) {
              'individual' => 'Every page as a separate file',
              'byPageRange' => 'By page range',
              _ => 'Every N pages',
            };
            return GestureDetector(
              onTap: () => setState(() => _splitMode = m),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(
                  children: [
                    Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.text),
                      ),
                      child: _splitMode == m
                          ? Center(child: Container(
                              width: 10, height: 10,
                              decoration: const BoxDecoration(
                                  color: AppColors.text, shape: BoxShape.circle)))
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Text(label, style: AppTextStyles.body(14)),
                  ],
                ),
              ),
            );
          }),
          if (_splitMode == 'byPageRange') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('From page', style: AppTextStyles.body(12, color: AppColors.muted)),
                      const SizedBox(height: 6),
                      TextField(
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: AppTextStyles.body(14),
                        cursorColor: AppColors.text,
                        onChanged: (v) => setState(() => _splitStart = int.tryParse(v) ?? 1),
                        decoration: _numInputDecoration('1'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('To page', style: AppTextStyles.body(12, color: AppColors.muted)),
                      const SizedBox(height: 6),
                      TextField(
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: AppTextStyles.body(14),
                        cursorColor: AppColors.text,
                        onChanged: (v) => setState(() => _splitEnd = int.tryParse(v) ?? 1),
                        decoration: _numInputDecoration('e.g. 5'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (_splitMode == 'everyN') ...[
            const SizedBox(height: 16),
            Text('Every N pages', style: AppTextStyles.body(12, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppTextStyles.body(14),
              cursorColor: AppColors.text,
              onChanged: (v) => setState(() => _splitEveryN = int.tryParse(v) ?? 1),
              decoration: _numInputDecoration('e.g. 3'),
            ),
          ],
        ],
      );

  InputDecoration _numInputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.body(14, color: AppColors.faint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.text)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.text, width: 2)),
      );

  InputDecoration _pwDecoration() => InputDecoration(
        hintText: '••••••••',
        hintStyle: AppTextStyles.body(15, color: AppColors.faint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.text)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.text, width: 2)),
      );

  Widget _passwordOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.toolId == 'protect' ? 'Open password' : 'Enter current password',
            style: AppTextStyles.body(13, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          TextField(
            obscureText: true,
            onChanged: (v) => setState(() => _passwordField = v),
            style: AppTextStyles.body(15),
            cursorColor: AppColors.text,
            decoration: _pwDecoration(),
          ),
          if (widget.toolId == 'protect') ...[
            const SizedBox(height: 16),
            Text('Owner password (controls editing)',
                style: AppTextStyles.body(13, color: AppColors.muted)),
            const SizedBox(height: 6),
            Text('Leave blank to reuse the open password.',
                style: AppTextStyles.mono(10, color: AppColors.muted)),
            const SizedBox(height: 10),
            TextField(
              obscureText: true,
              controller: _ownerPasswordCtrl,
              onChanged: (v) => _protectOwnerPassword = v,
              style: AppTextStyles.body(15),
              cursorColor: AppColors.text,
              decoration: _pwDecoration(),
            ),
          ],
        ],
      );

  Widget _watermarkOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Watermark text',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          TextField(
            controller: _watermarkCtrl,
            onChanged: (v) => _watermarkText = v,
            style: AppTextStyles.body(15),
            cursorColor: AppColors.text,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.text)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.text, width: 2)),
            ),
          ),
          const SizedBox(height: 20),
          _sliderRow(label: 'Opacity', value: _watermarkOpacity,
              display: '${(_watermarkOpacity * 100).round()}%',
              min: 0.05, max: 1.0, divisions: 19,
              onChanged: (v) => setState(() => _watermarkOpacity = v)),
          const SizedBox(height: 14),
          _sliderRow(label: 'Font size', value: _watermarkFontSize,
              display: '${_watermarkFontSize.round()}pt',
              min: 20, max: 120, divisions: 20,
              onChanged: (v) => setState(() => _watermarkFontSize = v)),
          const SizedBox(height: 14),
          _sliderRow(label: 'Rotation', value: _watermarkRotation,
              display: '${_watermarkRotation.round()}°',
              min: -90, max: 0, divisions: 18,
              onChanged: (v) => setState(() => _watermarkRotation = v)),
        ],
      );

  Widget _stampOpts(BuildContext ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Choose stamp',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ['draft', 'approved', 'confidential', 'final_', 'rejected']
                .map((s) {
              final label = s.replaceAll('_', '').toUpperCase();
              final active = _stampType == s;
              return GestureDetector(
                onTap: () => setState(() => _stampType = s),
                child: Container(
                  width: (MediaQuery.of(ctx).size.width - 70) / 2,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: active ? AppColors.text : AppColors.bg,
                    border: Border.all(color: AppColors.text),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(label,
                      style: AppTextStyles.display(14, weight: FontWeight.w700)
                          .copyWith(
                              color: active ? AppColors.bg : AppColors.text,
                              letterSpacing: 0.1 * 14)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Position', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: {
              'topLeft': 'Top Left', 'topRight': 'Top Right',
              'center': 'Center',
              'bottomLeft': 'Bottom Left', 'bottomRight': 'Bottom Right',
            }.entries.map((e) {
              final active = _stampPosition == e.key;
              return GestureDetector(
                onTap: () => setState(() => _stampPosition = e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.text : AppColors.bg,
                    border: Border.all(color: active ? AppColors.text : AppColors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(e.value,
                      style: AppTextStyles.mono(11,
                          color: active ? AppColors.bg : AppColors.text)),
                ),
              );
            }).toList(),
          ),
        ],
      );

  Widget _headerFooterOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Header text',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(
              hint: 'e.g. My Company', onChanged: (v) => _headerText = v),
          const SizedBox(height: 16),
          Text('Footer text',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'e.g. Page {page}', onChanged: (v) => _footerText = v),
        ],
      );

  Widget _addTextOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Text to add',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'Type something…', onChanged: (v) => _addText = v),
          const SizedBox(height: 20),
          Text('Position & size (pts)', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 10),
          Row(children: [
            _cropInput('X', _addTextX, (v) => setState(() => _addTextX = v)),
            const SizedBox(width: 10),
            _cropInput('Y', _addTextY, (v) => setState(() => _addTextY = v)),
            const SizedBox(width: 10),
            _cropInput('Size', _addTextFontSize, (v) => setState(() => _addTextFontSize = v)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _cropInput('Page', _addTextPage.toDouble(), (v) => setState(() => _addTextPage = v.round().clamp(0, (_pageCount - 1).clamp(0, 9999)))),
            const Expanded(child: SizedBox()),
            const Expanded(child: SizedBox()),
          ]),
        ],
      );

  Widget _nupOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pages per sheet',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          ...[
            {'label': '2-up', 'cols': 2, 'rows': 1},
            {'label': '4-up', 'cols': 2, 'rows': 2},
            {'label': '6-up', 'cols': 3, 'rows': 2},
          ].map((o) {
            final active = _nupCols == o['cols'] && _nupRows == o['rows'];
            return GestureDetector(
              onTap: () => setState(() {
                _nupCols = o['cols'] as int;
                _nupRows = o['rows'] as int;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(
                  children: [
                    Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.text)),
                      child: active
                          ? Center(
                              child: Container(
                                  width: 10, height: 10,
                                  decoration: const BoxDecoration(
                                      color: AppColors.text,
                                      shape: BoxShape.circle)))
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Text(o['label'] as String, style: AppTextStyles.body(14)),
                  ],
                ),
              ),
            );
          }),
        ],
      );

  Widget _mergeListOpts(BuildContext ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Files to merge (${_filePaths.length})',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 10),
          ..._filePaths.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Text((e.key + 1).toString().padLeft(2, '0'),
                        style: AppTextStyles.mono(11, color: AppColors.muted)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(e.value.split('/').last,
                            style: AppTextStyles.body(13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    GestureDetector(
                      onTap: () =>
                          setState(() => _filePaths.removeAt(e.key)),
                      child: Icon(Icons.close,
                          size: 16,
                          color: AppColors.text.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              )),
          GestureDetector(
            onTap: () => _pickFile(multi: true),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.text.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text('+ ADD FILES',
                  style: AppTextStyles.mono(12, color: AppColors.muted)),
            ),
          ),
        ],
      );

  Widget _permissionsOpts() {
    final isAdd = widget.toolId == 'add-perms';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isAdd ? 'Owner password (required to set permissions)' : 'Owner password',
            style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 8),
        TextField(
          obscureText: true,
          onChanged: (v) => setState(() => _ownerPassword = v),
          style: AppTextStyles.body(15),
          cursorColor: AppColors.text,
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: AppTextStyles.body(15, color: AppColors.faint),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.text)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.text, width: 2)),
          ),
        ),
        if (isAdd) ...[
          const SizedBox(height: 12),
          Text('Permissions are locked with this password. Anyone who opens the PDF can still read it.',
              style: AppTextStyles.body(12, color: AppColors.muted)),
        ],
      ],
    );
  }

  Widget _findReplaceOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Find', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'Text to find…', onChanged: (v) => setState(() => _findText = v)),
          const SizedBox(height: 16),
          Text('Replace with', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'Replacement text…', onChanged: (v) => setState(() => _replaceText = v)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _caseSensitive = !_caseSensitive),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: _caseSensitive ? AppColors.text : AppColors.bg,
                    border: Border.all(color: AppColors.text),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _caseSensitive
                      ? const Icon(Icons.check, color: AppColors.bg, size: 14)
                      : null,
                ),
                const SizedBox(width: 10),
                Text('Case sensitive', style: AppTextStyles.body(13)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('Works on text-based PDFs only.',
              style: AppTextStyles.mono(10, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text('Output font will be Helvetica — original font family is not preserved.',
              style: AppTextStyles.mono(10, color: AppColors.muted)),
        ],
      );

  Widget _addQrOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('QR content (URL, text…)',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'https://…', onChanged: (v) => setState(() => _qrContent = v)),
          const SizedBox(height: 16),
          Text('Position', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: {
              'topLeft': 'Top Left',
              'topRight': 'Top Right',
              'bottomLeft': 'Bottom Left',
              'bottomRight': 'Bottom Right',
            }.entries.map((e) {
              final active = _qrPosition == e.key;
              return GestureDetector(
                onTap: () => setState(() => _qrPosition = e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.text : AppColors.bg,
                    border: Border.all(color: AppColors.text),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(e.value,
                      style: AppTextStyles.body(12)
                          .copyWith(color: active ? AppColors.bg : AppColors.text)),
                ),
              );
            }).toList(),
          ),
        ],
      );

  Widget _dateStampOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Stamp position', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: {
              'topLeft': 'Top Left',
              'topRight': 'Top Right',
              'bottomLeft': 'Bottom Left',
              'bottomRight': 'Bottom Right',
            }.entries.map((e) {
              final active = _stampPosition == e.key;
              return GestureDetector(
                onTap: () => setState(() => _stampPosition = e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.text : AppColors.bg,
                    border: Border.all(color: AppColors.text),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(e.value,
                      style: AppTextStyles.body(12)
                          .copyWith(color: active ? AppColors.bg : AppColors.text)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text("Stamps today's date (DD/MM/YYYY) on every page.",
              style: AppTextStyles.mono(10, color: AppColors.muted)),
        ],
      );

  Widget _bookmarksOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add bookmarks', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          if (_bookmarkEntries.isNotEmpty) ...[
            ..._bookmarkEntries.asMap().entries.map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(child: Text(
                          'p.${e.value['page']} — ${e.value['title']}',
                          style: AppTextStyles.body(13),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      GestureDetector(
                        onTap: () => setState(() => _bookmarkEntries.removeAt(e.key)),
                        child: const Icon(Icons.close, size: 16, color: AppColors.muted),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _bookmarkPageCtrl,
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.body(13),
                  cursorColor: AppColors.text,
                  decoration: _numInputDecoration('Page'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _bookmarkTitleCtrl,
                  style: AppTextStyles.body(13),
                  cursorColor: AppColors.text,
                  decoration: _numInputDecoration('Bookmark title'),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () {
                  final page = int.tryParse(_bookmarkPageCtrl.text);
                  final title = _bookmarkTitleCtrl.text.trim();
                  if (page != null && title.isNotEmpty) {
                    setState(() {
                      _bookmarkEntries.add({'page': page, 'title': title});
                      _bookmarkTitleCtrl.clear();
                      _bookmarkPageCtrl.clear();
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.text, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add, color: AppColors.bg, size: 18),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _editMetaOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Title', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'Document title', onChanged: (v) => setState(() => _metaTitle = v)),
          const SizedBox(height: 14),
          Text('Author', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'Author name', onChanged: (v) => setState(() => _metaAuthor = v)),
          const SizedBox(height: 14),
          Text('Subject', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'Subject', onChanged: (v) => setState(() => _metaSubject = v)),
          const SizedBox(height: 14),
          Text('Keywords', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 8),
          _textField(hint: 'comma, separated', onChanged: (v) => setState(() => _metaKeywords = v)),
        ],
      );

  Widget _cropOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Crop margins (points, applied to all pages)',
              style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 14),
          Row(
            children: [
              _cropInput('Top', _cropTop, (v) => _cropTop = v),
              const SizedBox(width: 10),
              _cropInput('Bottom', _cropBottom, (v) => _cropBottom = v),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _cropInput('Left', _cropLeft, (v) => _cropLeft = v),
              const SizedBox(width: 10),
              _cropInput('Right', _cropRight, (v) => _cropRight = v),
            ],
          ),
          const SizedBox(height: 12),
          Text('1 point ≈ 0.35 mm. A4 page is 595 × 842 pts.',
              style: AppTextStyles.mono(10, color: AppColors.muted)),
        ],
      );

  // ── Signature capture ──────────────────────────────────────────────────────

  Future<void> _captureDrawnSignature() async {
    const w = 400.0, h = 160.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF000000));
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in _strokePoints) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bd != null && mounted) {
      setState(() => _signatureBytes = bd.buffer.asUint8List());
    }
  }

  Future<void> _captureTypedSignature() async {
    if (_typedName.trim().isEmpty) return;
    const w = 400.0, h = 100.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, w, h),
        Paint()..color = const Color(0xFF000000));
    final tp = TextPainter(
      text: TextSpan(
        text: _typedName,
        style: const TextStyle(
          color: Color(0xFFFFFFFF),
          fontSize: 52,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 20);
    tp.paint(canvas, Offset(10, (h - tp.height) / 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bd != null && mounted) {
      setState(() => _signatureBytes = bd.buffer.asUint8List());
    }
  }

  Widget _drawSigOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Draw your signature',
                style: AppTextStyles.body(13, color: AppColors.muted)),
            if (_strokePoints.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() {
                  _strokePoints.clear();
                  _signatureBytes = null;
                }),
                child: Text('Clear',
                    style: AppTextStyles.mono(11, color: AppColors.muted)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (ctx, constraints) {
          final cw = constraints.maxWidth;
          const ch = 160.0;
          return GestureDetector(
            onPanStart: (d) {
              setState(() {
                _currentStroke = [d.localPosition];
                _strokePoints.add(_currentStroke!);
                _signatureBytes = null;
              });
            },
            onPanUpdate: (d) {
              setState(() => _currentStroke?.add(d.localPosition));
            },
            onPanEnd: (_) => _captureDrawnSignature(),
            child: Container(
              width: cw,
              height: ch,
              decoration: BoxDecoration(
                color: AppColors.text,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _SignaturePainter(_strokePoints),
                  size: Size(cw, ch),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        if (_signatureBytes != null)
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.text, size: 14),
              const SizedBox(width: 6),
              Text('Signature captured — tap Run to place it.',
                  style: AppTextStyles.mono(10, color: AppColors.muted)),
            ],
          )
        else if (_strokePoints.isNotEmpty)
          Text('Lift your finger to confirm.',
              style: AppTextStyles.mono(10, color: AppColors.muted))
        else
          Text('Draw inside the black area above.',
              style: AppTextStyles.mono(10, color: AppColors.muted)),
        const SizedBox(height: 20),
        ..._sigPlacementInputs(),
      ],
    );
  }

  List<Widget> _sigPlacementInputs() => [
        Text('Placement (pts)', style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 10),
        Row(children: [
          _cropInput('X', _sigX, (v) => setState(() => _sigX = v)),
          const SizedBox(width: 10),
          _cropInput('Y', _sigY, (v) => setState(() => _sigY = v)),
          const SizedBox(width: 10),
          _cropInput('Page', _sigPage.toDouble(), (v) => setState(() => _sigPage = v.round().clamp(0, (_pageCount - 1).clamp(0, 9999)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _cropInput('W', _sigW, (v) => setState(() => _sigW = v)),
          const SizedBox(width: 10),
          _cropInput('H', _sigH, (v) => setState(() => _sigH = v)),
          const Expanded(child: SizedBox()),
        ]),
      ];

  Widget _typedSigOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type your name', style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 8),
        _textField(
          hint: 'Your name…',
          onChanged: (v) => setState(() {
            _typedName = v;
            _signatureBytes = null;
          }),
        ),
        const SizedBox(height: 14),
        FillButton(
          label: 'Generate Signature',
          icon: const Icon(Icons.draw, color: AppColors.bg, size: 16),
          enabled: _typedName.trim().isNotEmpty,
          onTap: _typedName.trim().isNotEmpty ? _captureTypedSignature : null,
        ),
        if (_signatureBytes != null) ...[
          const SizedBox(height: 14),
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.text,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(_signatureBytes!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
          Text('Signature ready — tap Run to place it.',
              style: AppTextStyles.mono(10, color: AppColors.muted)),
        ],
        const SizedBox(height: 20),
        ..._sigPlacementInputs(),
      ],
    );
  }

  Widget _redactOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add redaction areas (page, X, Y, width, height in pts)',
            style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 12),
        if (_redactAreas.isNotEmpty) ...[
          ..._redactAreas.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'p${e.value['page']}  X${e.value['x']}  Y${e.value['y']}  ${e.value['w']}×${e.value['h']}',
                        style: AppTextStyles.mono(11),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _redactAreas.removeAt(e.key)),
                      child: const Icon(Icons.close, size: 16, color: AppColors.muted),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 12),
        ],
        // Input row: page | X | Y
        Row(children: [
          _redactField('Page', _redactPageCtrl),
          const SizedBox(width: 8),
          _redactField('X', _redactXCtrl),
          const SizedBox(width: 8),
          _redactField('Y', _redactYCtrl),
        ]),
        const SizedBox(height: 8),
        // Input row: W | H | Add button
        Row(children: [
          _redactField('Width', _redactWCtrl),
          const SizedBox(width: 8),
          _redactField('Height', _redactHCtrl),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final page = (int.tryParse(_redactPageCtrl.text) ?? 1).clamp(1, _pageCount > 0 ? _pageCount : 9999);
              final x = double.tryParse(_redactXCtrl.text) ?? 0;
              final y = double.tryParse(_redactYCtrl.text) ?? 0;
              final w = double.tryParse(_redactWCtrl.text) ?? 0;
              final h = double.tryParse(_redactHCtrl.text) ?? 0;
              if (w > 0 && h > 0) {
                setState(() => _redactAreas.add(
                    {'page': page - 1, 'x': x, 'y': y, 'w': w, 'h': h}));
                for (final c in [_redactPageCtrl, _redactXCtrl, _redactYCtrl, _redactWCtrl, _redactHCtrl]) {
                  c.clear();
                }
              }
            },
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                  color: AppColors.text, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: const Icon(Icons.add, color: AppColors.bg, size: 20),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text('Coordinates in PDF points. A4 page = 595 × 842 pts.',
            style: AppTextStyles.mono(10, color: AppColors.muted)),
        if (_redactAreas.isEmpty) ...[
          const SizedBox(height: 6),
          Text('Add at least one area to enable Run.',
              style: AppTextStyles.mono(10, color: AppColors.muted)),
        ],
      ],
    );
  }

  Widget _redactField(String label, TextEditingController ctrl) => Expanded(
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTextStyles.mono(12),
          cursorColor: AppColors.text,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: AppTextStyles.mono(10, color: AppColors.muted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.text)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.text, width: 2)),
          ),
        ),
      );

  Widget _cropInput(String label, double value, void Function(double) onSet) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.body(12, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.body(14),
              cursorColor: AppColors.text,
              onChanged: (v) => setState(() => onSet(double.tryParse(v) ?? 20)),
              decoration: _numInputDecoration(value.toStringAsFixed(0)),
            ),
          ],
        ),
      );

  Widget _addImageOpts() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Image to place', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _pickImageFile,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: _imagePath.isEmpty ? AppColors.text : AppColors.text),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.image_outlined, color: AppColors.text, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _imagePath.isEmpty ? 'Tap to select image' : _imagePath.split('/').last,
                      style: AppTextStyles.body(13, color: _imagePath.isEmpty ? AppColors.muted : AppColors.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_imagePath.isEmpty) ...[
            const SizedBox(height: 8),
            Text('Select an image to continue', style: AppTextStyles.mono(10, color: AppColors.muted)),
          ],
          const SizedBox(height: 20),
          Text('Position & size (pts)', style: AppTextStyles.body(13, color: AppColors.muted)),
          const SizedBox(height: 10),
          Row(children: [
            _cropInput('X', _addImageX, (v) => setState(() => _addImageX = v)),
            const SizedBox(width: 10),
            _cropInput('Y', _addImageY, (v) => setState(() => _addImageY = v)),
            const SizedBox(width: 10),
            _cropInput('Page', _addImagePage.toDouble(), (v) => setState(() => _addImagePage = v.round().clamp(0, (_pageCount - 1).clamp(0, 9999)))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _cropInput('W', _addImageW, (v) => setState(() => _addImageW = v)),
            const SizedBox(width: 10),
            _cropInput('H', _addImageH, (v) => setState(() => _addImageH = v)),
            const Expanded(child: SizedBox()),
          ]),
        ],
      );

  Widget _pageSelectOpts({required bool canSelectAll}) {
    if (_pageCount == 0) {
      return Text('Loading page info…', style: AppTextStyles.body(13, color: AppColors.muted));
    }
    final label = canSelectAll ? 'Select pages to extract' : 'Select pages to delete';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.body(13, color: AppColors.muted)),
            Text('${_selectedPages.length} / $_pageCount selected',
                style: AppTextStyles.mono(10, color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(_pageCount, (i) {
            final selected = _selectedPages.contains(i);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) {
                  _selectedPages.remove(i);
                } else {
                  _selectedPages.add(i);
                  _selectedPages.sort();
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected ? AppColors.text : AppColors.bg,
                  border: Border.all(color: AppColors.text),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text('${i + 1}',
                    style: AppTextStyles.mono(13, weight: FontWeight.w600)
                        .copyWith(color: selected ? AppColors.bg : AppColors.text)),
              ),
            );
          }),
        ),
        if (!canSelectAll && _selectedPages.length >= _pageCount) ...[
          const SizedBox(height: 8),
          Text('Cannot delete all pages', style: AppTextStyles.mono(10, color: AppColors.muted)),
        ],
        if (_selectedPages.isEmpty) ...[
          const SizedBox(height: 8),
          Text('Select at least 1 page', style: AppTextStyles.mono(10, color: AppColors.muted)),
        ],
      ],
    );
  }

  Widget _reorderOpts() {
    if (_pageCount == 0) {
      return Text('Loading page info…', style: AppTextStyles.body(13, color: AppColors.muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Drag to reorder pages', style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 12),
        SizedBox(
          height: (_pageCount * 56.0).clamp(0, 320),
          child: ReorderableListView.builder(
            itemCount: _pageOrder.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _pageOrder.removeAt(oldIndex);
                _pageOrder.insert(newIndex, item);
              });
            },
            itemBuilder: (ctx, i) => Container(
              key: ValueKey(_pageOrder[i]),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text('${i + 1}', style: AppTextStyles.mono(11, color: AppColors.muted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Page ${_pageOrder[i] + 1}', style: AppTextStyles.body(13)),
                  ),
                  const Icon(Icons.drag_handle, color: AppColors.muted, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Draw on PDF ────────────────────────────────────────────────────────────

  Widget _drawOnPdfOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Draw on page',
                style: AppTextStyles.body(13, color: AppColors.muted)),
            if (_drawOnPdfStrokes.isNotEmpty)
              GestureDetector(
                onTap: () => setState(() {
                  _drawOnPdfStrokes.clear();
                  _drawOnPdfCurrentStroke = null;
                }),
                child: Text('Clear',
                    style: AppTextStyles.mono(11, color: AppColors.muted)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (ctx, constraints) {
          final cw = constraints.maxWidth;
          const ch = 220.0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _drawOnPdfCanvasW != cw) {
              setState(() {
                _drawOnPdfCanvasW = cw;
                _drawOnPdfCanvasH = ch;
              });
            }
          });
          return GestureDetector(
            onPanStart: (d) => setState(() {
              _drawOnPdfCurrentStroke = [d.localPosition];
              _drawOnPdfStrokes.add(_drawOnPdfCurrentStroke!);
            }),
            onPanUpdate: (d) =>
                setState(() => _drawOnPdfCurrentStroke?.add(d.localPosition)),
            onPanEnd: (_) =>
                setState(() => _drawOnPdfCurrentStroke = null),
            child: Container(
              width: cw,
              height: ch,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.text),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _StrokePainter(_drawOnPdfStrokes),
                  size: Size(cw, ch),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('Apply to page',
                style: AppTextStyles.body(13, color: AppColors.muted)),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: TextField(
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(13),
                cursorColor: AppColors.text,
                onChanged: (v) => setState(
                    () => _drawOnPdfPageIdx = (int.tryParse(v) ?? 1) - 1),
                decoration: _numInputDecoration('1'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _drawOnPdfStrokes.isNotEmpty
              ? '${_drawOnPdfStrokes.length} stroke(s) — tap Run to apply.'
              : 'Draw above. The strokes are scaled to the PDF page.',
          style: AppTextStyles.mono(10, color: AppColors.muted),
        ),
      ],
    );
  }

  // ── Add shapes ─────────────────────────────────────────────────────────────

  Widget _addShapesOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Shape', style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final entry in [
              ('rect', 'Rectangle'),
              ('circle', 'Circle'),
              ('line', 'Line'),
              ('arrow', 'Arrow'),
            ]) ...[
              if (entry != ('rect', 'Rectangle')) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _shapeType = entry.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _shapeType == entry.$1
                          ? AppColors.text
                          : AppColors.bg,
                      border: Border.all(color: AppColors.text),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      entry.$2,
                      style: AppTextStyles.body(12).copyWith(
                          color: _shapeType == entry.$1
                              ? AppColors.bg
                              : AppColors.text),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text('Position & size (PDF points)',
            style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 10),
        Row(children: [
          _shapeCoordField('X', _shapeX, (v) => _shapeX = v),
          const SizedBox(width: 8),
          _shapeCoordField('Y', _shapeY, (v) => _shapeY = v),
          const SizedBox(width: 8),
          _shapeCoordField('W', _shapeW, (v) => _shapeW = v),
          const SizedBox(width: 8),
          _shapeCoordField('H', _shapeH, (v) => _shapeH = v),
        ]),
        const SizedBox(height: 12),
        Row(
          children: [
            Text('Page', style: AppTextStyles.body(13, color: AppColors.muted)),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: TextField(
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(13),
                cursorColor: AppColors.text,
                onChanged: (v) =>
                    setState(() => _shapePageIdx = (int.tryParse(v) ?? 1) - 1),
                decoration: _numInputDecoration('1'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('A4 page = 595 × 842 pts. Origin (0,0) is top-left.',
            style: AppTextStyles.mono(10, color: AppColors.muted)),
      ],
    );
  }

  Widget _shapeCoordField(
          String label, double value, void Function(double) onSet) =>
      Expanded(
        child: TextField(
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: AppTextStyles.mono(12),
          cursorColor: AppColors.text,
          onChanged: (v) => setState(() => onSet(double.tryParse(v) ?? value)),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: AppTextStyles.mono(10, color: AppColors.muted),
            hintText: value.toStringAsFixed(0),
            hintStyle: AppTextStyles.mono(12, color: AppColors.faint),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.text)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.text, width: 2)),
          ),
        ),
      );

  // ── Text markup ────────────────────────────────────────────────────────────

  Widget _textMarkupOpts() {
    final typeLabel = switch (widget.toolId) {
      'underline' => 'Underline',
      'strikethrough' => 'Strikethrough',
      _ => 'Highlight',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Text to $typeLabel'.toLowerCase(),
            style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 8),
        _textField(
            hint: 'Text to find…',
            onChanged: (v) => setState(() => _markupText = v)),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Page (0 = all)',
                style: AppTextStyles.body(13, color: AppColors.muted)),
            const SizedBox(width: 12),
            SizedBox(
              width: 72,
              child: TextField(
                keyboardType: TextInputType.number,
                style: AppTextStyles.body(13),
                cursorColor: AppColors.text,
                onChanged: (v) =>
                    setState(() => _markupPage = int.tryParse(v) ?? 0),
                decoration: _numInputDecoration('0'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Works on text-based PDFs only.',
            style: AppTextStyles.mono(10, color: AppColors.muted)),
      ],
    );
  }

  // ── Sticky notes ───────────────────────────────────────────────────────────

  Widget _stickyNotesOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Note text',
            style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 8),
        TextField(
          maxLines: 3,
          onChanged: (v) => setState(() => _stickyText = v),
          style: AppTextStyles.body(13),
          cursorColor: AppColors.text,
          decoration: InputDecoration(
            hintText: 'Type your note…',
            hintStyle: AppTextStyles.body(13, color: AppColors.faint),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.text)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.text, width: 2)),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          _shapeCoordField('X', _stickyX, (v) => _stickyX = v),
          const SizedBox(width: 8),
          _shapeCoordField('Y', _stickyY, (v) => _stickyY = v),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Page',
                    style: AppTextStyles.mono(10, color: AppColors.muted)),
                const SizedBox(height: 6),
                TextField(
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.mono(12),
                  cursorColor: AppColors.text,
                  onChanged: (v) =>
                      setState(() => _stickyPage = int.tryParse(v) ?? 1),
                  decoration: InputDecoration(
                    hintText: '1',
                    hintStyle: AppTextStyles.mono(12, color: AppColors.faint),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide:
                            const BorderSide(color: AppColors.text)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(
                            color: AppColors.text, width: 2)),
                  ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Position in PDF points. A4 = 595 × 842 pts.',
            style: AppTextStyles.mono(10, color: AppColors.muted)),
      ],
    );
  }

  // ── Hyperlinks ─────────────────────────────────────────────────────────────

  Widget _hyperlinksOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Text to link',
            style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 8),
        _textField(
            hint: 'e.g. "click here"',
            onChanged: (v) => setState(() => _linkText = v)),
        const SizedBox(height: 16),
        Text('URL', style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 8),
        _textField(
            hint: 'https://…',
            onChanged: (v) => setState(() => _linkUrl = v)),
        const SizedBox(height: 8),
        Text(
            'Finds the text in the PDF and attaches the URL as a clickable link.',
            style: AppTextStyles.mono(10, color: AppColors.muted)),
      ],
    );
  }

  // ── Downsample ─────────────────────────────────────────────────────────────

  Widget _downsampleOpts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Target resolution',
            style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final entry in [
              (72, 'Screen', '72 DPI'),
              (96, 'Web', '96 DPI'),
              (150, 'Print', '150 DPI'),
            ]) ...[
              if (entry.$1 != 72) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _downsampleDpi = entry.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _downsampleDpi == entry.$1
                          ? AppColors.text
                          : AppColors.bg,
                      border: Border.all(
                          color: _downsampleDpi == entry.$1
                              ? AppColors.text
                              : AppColors.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.$2,
                          style: AppTextStyles.display(13,
                                  weight: FontWeight.w600)
                              .copyWith(
                                  color: _downsampleDpi == entry.$1
                                      ? AppColors.bg
                                      : AppColors.text),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.$3,
                          style: AppTextStyles.mono(9,
                              color: _downsampleDpi == entry.$1
                                  ? AppColors.bg.withValues(alpha: 0.7)
                                  : AppColors.faint),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
            'Re-renders pages as JPEG images at the selected DPI. Text layers are not preserved.',
            style: AppTextStyles.mono(10, color: AppColors.muted)),
      ],
    );
  }

  Widget _fillFormOpts() {
    if (_loadingFormFields) {
      return const Center(child: CircularProgressIndicator(color: AppColors.text, strokeWidth: 2));
    }
    if (_formFieldControllers.isEmpty) {
      return Text(
        'No fillable fields detected in this PDF.',
        style: AppTextStyles.body(13, color: AppColors.muted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Form fields', style: AppTextStyles.body(13, color: AppColors.muted)),
        const SizedBox(height: 12),
        for (final entry in _formFieldControllers.entries) ...[
          Text(entry.key, style: AppTextStyles.mono(11, color: AppColors.muted)),
          const SizedBox(height: 6),
          TextField(
            controller: entry.value,
            style: AppTextStyles.body(14),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required String display,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTextStyles.body(13, color: AppColors.muted)),
              Text(display, style: AppTextStyles.mono(11)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.text,
              inactiveTrackColor: AppColors.line,
              thumbColor: AppColors.text,
              overlayColor: AppColors.text.withValues(alpha: 0.1),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      );

  Widget _textField(
          {required String hint, required ValueChanged<String> onChanged}) =>
      TextField(
        onChanged: onChanged,
        style: AppTextStyles.body(14),
        cursorColor: AppColors.text,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.body(14, color: AppColors.faint),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.text)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.text, width: 2)),
        ),
      );

  Widget _buildOutputRow(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppTextStyles.body(13, color: AppColors.muted)),
            Flexible(
                child: Text(value,
                    style: AppTextStyles.mono(12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

}

// Black strokes on white/transparent background (for the Draw tool).
class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  const _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

// White strokes on black background (for the Signature tools).
class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  const _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => old.strokes != strokes;
}
