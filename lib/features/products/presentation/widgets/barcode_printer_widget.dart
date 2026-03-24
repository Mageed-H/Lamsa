import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:lamsa/core/theme/app_theme.dart';

/// يعرض معاينة باركود المنتج مع إمكانية الطباعة
class BarcodePrinterWidget {
  BarcodePrinterWidget._();

  /// يفتح نافذة معاينة + طباعة الباركود
  static void show(BuildContext context, {
    required String barcode,
    required String productName,
    int copies = 1,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _BarcodePrintDialog(
        barcode: barcode,
        productName: productName,
        initialCopies: copies,
      ),
    );
  }
}

class _BarcodePrintDialog extends StatefulWidget {
  final String barcode;
  final String productName;
  final int initialCopies;

  const _BarcodePrintDialog({
    required this.barcode,
    required this.productName,
    required this.initialCopies,
  });

  @override
  State<_BarcodePrintDialog> createState() => _BarcodePrintDialogState();
}

class _BarcodePrintDialogState extends State<_BarcodePrintDialog> {
  late int _copies;

  @override
  void initState() {
    super.initState();
    _copies = widget.initialCopies;
  }

  // تحديد نوع الباركود بناءً على المحتوى
  Barcode _detectBarcodeType() {
    final code = widget.barcode;
    // الباركودات المحلية (LOC-) أو التي تحتوي حروف → Code128
    if (code.contains(RegExp(r'[a-zA-Z\-]'))) {
      return Barcode.code128();
    }
    // EAN-13
    if (code.length == 13 && RegExp(r'^\d+$').hasMatch(code)) {
      return Barcode.ean13();
    }
    // EAN-8
    if (code.length == 8 && RegExp(r'^\d+$').hasMatch(code)) {
      return Barcode.ean8();
    }
    // UPC-A
    if (code.length == 12 && RegExp(r'^\d+$').hasMatch(code)) {
      return Barcode.upcA();
    }
    // افتراضي
    return Barcode.code128();
  }

  pw.Barcode _detectPdfBarcodeType() {
    final code = widget.barcode;
    if (code.contains(RegExp(r'[a-zA-Z\-]'))) {
      return pw.Barcode.code128();
    }
    if (code.length == 13 && RegExp(r'^\d+$').hasMatch(code)) {
      return pw.Barcode.ean13();
    }
    if (code.length == 8 && RegExp(r'^\d+$').hasMatch(code)) {
      return pw.Barcode.ean8();
    }
    if (code.length == 12 && RegExp(r'^\d+$').hasMatch(code)) {
      return pw.Barcode.upcA();
    }
    return pw.Barcode.code128();
  }

  Future<void> _printBarcode() async {
    final pdfBarcodeType = _detectPdfBarcodeType();
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_copies, (_) => pw.Container(
              width: 180,
              height: 100,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.5),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    widget.productName,
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                  ),
                  pw.SizedBox(height: 4),
                  pw.BarcodeWidget(
                    barcode: pdfBarcodeType,
                    data: widget.barcode,
                    width: 160,
                    height: 50,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(widget.barcode, style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            )),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('طباعة باركود', style: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // اسم المنتج
            Text(widget.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            // معاينة الباركود
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.neutralColor),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: BarcodeWidget(
                barcode: _detectBarcodeType(),
                data: widget.barcode,
                width: 250,
                height: 80,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            Text(widget.barcode, style: const TextStyle(fontFamily: 'monospace', color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            // عدد النسخ
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('عدد النسخ:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primaryColor),
                  onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.primaryColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$_copies', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                  onPressed: _copies < 100 ? () => setState(() => _copies++) : null,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
          icon: const Icon(Icons.print),
          label: const Text('طباعة'),
          onPressed: _printBarcode,
        ),
      ],
    );
  }
}
