import 'tool_model.dart';

// Builds the flat TOOLS list with sequential numbers and category back-pointers.
List<PdfTool> _buildToolList(List<ToolCategory> categories) {
  final out = <PdfTool>[];
  var n = 1;
  for (final cat in categories) {
    for (final t in cat.tools) {
      out.add(PdfTool(
        id: t.id,
        label: t.label,
        desc: t.desc,
        num: n.toString().padLeft(2, '0'),
        category: cat.label,
        categoryId: cat.id,
      ));
      n++;
    }
  }
  return out;
}

final kCategories = <ToolCategory>[
  ToolCategory(id: 'core', label: 'Core', tools: [
    PdfTool(id: 'merge', label: 'Merge', desc: 'Join multiple PDFs', num: '', category: '', categoryId: ''),
    PdfTool(id: 'split', label: 'Split', desc: 'Extract pages or ranges', num: '', category: '', categoryId: ''),
    PdfTool(id: 'extract-pages', label: 'Extract Pages', desc: 'Pull out a page set', num: '', category: '', categoryId: ''),
    PdfTool(id: 'delete-pages', label: 'Delete Pages', desc: 'Remove unwanted pages', num: '', category: '', categoryId: ''),
    PdfTool(id: 'reorder-pages', label: 'Reorder Pages', desc: 'Drag pages to new order', num: '', category: '', categoryId: ''),
    PdfTool(id: 'rotate', label: 'Rotate', desc: 'Reorient pages', num: '', category: '', categoryId: ''),
    PdfTool(id: 'crop', label: 'Crop', desc: 'Trim margins', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'compress', label: 'Compress & Optimize', tools: [
    PdfTool(id: 'compress', label: 'Compress', desc: 'Shrink file size', num: '', category: '', categoryId: ''),
    PdfTool(id: 'optimize-web', label: 'Optimize for Web', desc: 'Linearize for streaming', num: '', category: '', categoryId: ''),
    PdfTool(id: 'downsample', label: 'Downsample Images', desc: 'Reduce image DPI', num: '', category: '', categoryId: ''),
    PdfTool(id: 'remove-duplicates', label: 'Remove Duplicates', desc: 'Strip identical pages', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'security', label: 'Security', tools: [
    PdfTool(id: 'protect', label: 'Add Password', desc: 'Encrypt with password', num: '', category: '', categoryId: ''),
    PdfTool(id: 'unlock', label: 'Remove Password', desc: 'Decrypt PDF', num: '', category: '', categoryId: ''),
    PdfTool(id: 'add-perms', label: 'Add Permissions', desc: 'Restrict print/copy', num: '', category: '', categoryId: ''),
    PdfTool(id: 'remove-perms', label: 'Remove Permissions', desc: 'Strip restrictions', num: '', category: '', categoryId: ''),
    PdfTool(id: 'redact', label: 'Redact', desc: 'Permanently black out', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'annotate', label: 'Annotate & Edit', tools: [
    PdfTool(id: 'add-text', label: 'Add Text', desc: 'Type onto pages', num: '', category: '', categoryId: ''),
    PdfTool(id: 'add-image', label: 'Add Image', desc: 'Place an image', num: '', category: '', categoryId: ''),
    PdfTool(id: 'draw', label: 'Draw', desc: 'Freehand pen', num: '', category: '', categoryId: ''),
    PdfTool(id: 'add-shapes', label: 'Add Shapes', desc: 'Rect, circle, line, arrow', num: '', category: '', categoryId: ''),
    PdfTool(id: 'highlight', label: 'Highlight', desc: 'Mark text', num: '', category: '', categoryId: ''),
    PdfTool(id: 'underline', label: 'Underline', desc: 'Underline text', num: '', category: '', categoryId: ''),
    PdfTool(id: 'strikethrough', label: 'Strikethrough', desc: 'Cross out text', num: '', category: '', categoryId: ''),
    PdfTool(id: 'sticky-notes', label: 'Sticky Notes', desc: 'Anchored notes', num: '', category: '', categoryId: ''),
    PdfTool(id: 'hyperlinks', label: 'Hyperlinks', desc: 'Add links', num: '', category: '', categoryId: ''),
    PdfTool(id: 'bookmarks', label: 'Bookmarks', desc: 'Outline anchors', num: '', category: '', categoryId: ''),
    PdfTool(id: 'page-numbers', label: 'Page Numbers', desc: 'Add numbering', num: '', category: '', categoryId: ''),
    PdfTool(id: 'header-footer', label: 'Header & Footer', desc: 'Repeating margins', num: '', category: '', categoryId: ''),
    PdfTool(id: 'watermark', label: 'Watermark', desc: 'Stamp text or image', num: '', category: '', categoryId: ''),
    PdfTool(id: 'remove-watermark', label: 'Remove Watermark', desc: 'Strip watermark', num: '', category: '', categoryId: ''),
    PdfTool(id: 'stamp', label: 'Stamp', desc: 'DRAFT, APPROVED, etc.', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'pdf-to', label: 'Convert — PDF To', tools: [
    PdfTool(id: 'pdf-to-images', label: 'PDF → Images', desc: 'Pages as PNG images', num: '', category: '', categoryId: ''),
    PdfTool(id: 'pdf-to-text', label: 'PDF → Text', desc: 'Plain text export', num: '', category: '', categoryId: ''),
    PdfTool(id: 'pdf-to-html', label: 'PDF → HTML', desc: 'Markup export', num: '', category: '', categoryId: ''),
    PdfTool(id: 'pdf-to-word', label: 'PDF → Word', desc: 'DOCX export', num: '', category: '', categoryId: ''),
    PdfTool(id: 'pdf-to-excel', label: 'PDF → Excel', desc: 'XLSX export', num: '', category: '', categoryId: ''),
    PdfTool(id: 'pdf-to-markdown', label: 'PDF → Markdown', desc: 'MD export', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'to-pdf', label: 'Convert — To PDF', tools: [
    PdfTool(id: 'images-to-pdf', label: 'Image → PDF', desc: 'Bundle images', num: '', category: '', categoryId: ''),
    PdfTool(id: 'word-to-pdf', label: 'Word → PDF', desc: 'DOCX to PDF', num: '', category: '', categoryId: ''),
    PdfTool(id: 'excel-to-pdf', label: 'Excel → PDF', desc: 'XLSX to PDF', num: '', category: '', categoryId: ''),
    PdfTool(id: 'html-to-pdf', label: 'HTML → PDF', desc: 'Render HTML', num: '', category: '', categoryId: ''),
    PdfTool(id: 'text-to-pdf', label: 'Text → PDF', desc: 'Plain text to PDF', num: '', category: '', categoryId: ''),
    PdfTool(id: 'md-to-pdf', label: 'Markdown → PDF', desc: 'MD to PDF', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'ocr', label: 'OCR', tools: [
    PdfTool(id: 'ocr', label: 'Scan to Searchable PDF', desc: 'OCR a scan', num: '', category: '', categoryId: ''),
    PdfTool(id: 'ocr-extract', label: 'Extract Text from Scan', desc: 'Text from images', num: '', category: '', categoryId: ''),
    PdfTool(id: 'ocr-selectable', label: 'Make Scanned PDF Selectable', desc: 'Add text layer', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'sign', label: 'Sign & Fill', tools: [
    PdfTool(id: 'draw-sig', label: 'Draw Signature', desc: 'Draw on canvas', num: '', category: '', categoryId: ''),
    PdfTool(id: 'typed-sig', label: 'Typed Signature', desc: 'Type your name', num: '', category: '', categoryId: ''),
    PdfTool(id: 'place-sig', label: 'Place Signature', desc: 'Drop saved signature', num: '', category: '', categoryId: ''),
    PdfTool(id: 'date-stamp', label: 'Date Stamp', desc: "Add today's date", num: '', category: '', categoryId: ''),
    PdfTool(id: 'fill-form', label: 'Fill Form', desc: 'Type into form fields', num: '', category: '', categoryId: ''),
    PdfTool(id: 'flatten', label: 'Flatten Form', desc: 'Lock fields permanently', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'analyze', label: 'Analyze', tools: [
    PdfTool(id: 'thumbnails', label: 'Page Thumbnails', desc: 'Visual overview', num: '', category: '', categoryId: ''),
    PdfTool(id: 'extract-images', label: 'Extract All Images', desc: 'Pull all images', num: '', category: '', categoryId: ''),
    PdfTool(id: 'extract-text', label: 'Extract All Text', desc: 'Dump all text', num: '', category: '', categoryId: ''),
    PdfTool(id: 'view-meta', label: 'View Metadata', desc: 'Inspect properties', num: '', category: '', categoryId: ''),
    PdfTool(id: 'edit-meta', label: 'Edit Metadata', desc: 'Update title, author', num: '', category: '', categoryId: ''),
    PdfTool(id: 'find-replace', label: 'Find & Replace', desc: 'Bulk text changes', num: '', category: '', categoryId: ''),
    PdfTool(id: 'word-count', label: 'Word Count', desc: 'Count words & chars', num: '', category: '', categoryId: ''),
    PdfTool(id: 'file-stats', label: 'File Stats', desc: 'Size, fonts, dimensions', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'qr', label: 'QR & Barcodes', tools: [
    PdfTool(id: 'add-qr', label: 'Add QR Code', desc: 'Embed a QR', num: '', category: '', categoryId: ''),
    PdfTool(id: 'read-qr', label: 'Read QR from PDF', desc: 'Scan codes', num: '', category: '', categoryId: ''),
  ]),
  ToolCategory(id: 'utilities', label: 'Utilities', tools: [
    PdfTool(id: 'duplicate', label: 'Duplicate', desc: 'Copy the file', num: '', category: '', categoryId: ''),
    PdfTool(id: 'reverse', label: 'Reverse Pages', desc: 'Flip page order', num: '', category: '', categoryId: ''),
    PdfTool(id: 'interleave', label: 'Interleave PDFs', desc: 'Zip two PDFs', num: '', category: '', categoryId: ''),
    PdfTool(id: 'repair', label: 'Repair PDF', desc: 'Fix damaged file', num: '', category: '', categoryId: ''),
    PdfTool(id: 'compare', label: 'Compare PDFs', desc: 'Diff two files', num: '', category: '', categoryId: ''),
    PdfTool(id: 'booklet', label: 'Booklet Layout', desc: 'Print as booklet', num: '', category: '', categoryId: ''),
    PdfTool(id: 'nup', label: 'N-up Layout', desc: 'Pages per sheet', num: '', category: '', categoryId: ''),
  ]),
];

final kTools = _buildToolList(kCategories);

PdfTool? findTool(String id) {
  try {
    return kTools.firstWhere((t) => t.id == id);
  } catch (_) {
    return kTools.isNotEmpty ? kTools.first : null;
  }
}
