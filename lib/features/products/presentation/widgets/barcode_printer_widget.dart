import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    required int price,
    int copies = 1,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _BarcodePrintDialog(
        barcode: barcode,
        productName: productName,
        price: price,
        initialCopies: copies,
      ),
    );
  }
}

class _BarcodePrintDialog extends StatefulWidget {
  final String barcode;
  final String productName;
  final int price;
  final int initialCopies;

  const _BarcodePrintDialog({
    required this.barcode,
    required this.productName,
    required this.price,
    required this.initialCopies,
  });

  @override
  State<_BarcodePrintDialog> createState() => _BarcodePrintDialogState();
}

class _BarcodePrintDialogState extends State<_BarcodePrintDialog> {
  late int _copies;
  late TextEditingController _copiesController;

  @override
  void initState() {
    super.initState();
    _copies = widget.initialCopies;
    _copiesController = TextEditingController(text: '$_copies');
  }

  @override
  void dispose() {
    _copiesController.dispose();
    super.dispose();
  }

  // تحديد نوع الباركود بناءً على المحتوى
  Barcode _detectBarcodeType() {
    final code = widget.barcode;
    if (code.contains(RegExp(r'[a-zA-Z\-]'))) {
      return Barcode.code128();
    }
    if (code.length == 13 && RegExp(r'^\d+$').hasMatch(code)) {
      return Barcode.ean13();
    }
    if (code.length == 8 && RegExp(r'^\d+$').hasMatch(code)) {
      return Barcode.ean8();
    }
    if (code.length == 12 && RegExp(r'^\d+$').hasMatch(code)) {
      return Barcode.upcA();
    }
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

    // تحميل خط عربي محلي (لا يحتاج إنترنت)
    final fontData = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
    final arabicFont = pw.Font.ttf(fontData);
    final arabicFontBold = arabicFont;

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_copies, (_) => pw.Container(
              width: 180,
              height: 110,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(width: 0.5),
              ),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    widget.productName,
                    style: pw.TextStyle(fontSize: 9, font: arabicFontBold),
                    maxLines: 1,
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 3),
                  pw.BarcodeWidget(
                    barcode: pdfBarcodeType,
                    data: widget.barcode,
                    width: 160,
                    height: 45,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(widget.barcode, style: pw.TextStyle(fontSize: 7, font: arabicFont)),
                      pw.Text(
                        '${widget.price} د',
                        style: pw.TextStyle(fontSize: 10, font: arabicFontBold),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
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
            // اسم المنتج + السعر
            Text(widget.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('${widget.price} دينار', style: const TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            // معاينة الباركود
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.neutralColor),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: Column(
                children: [
                  BarcodeWidget(
                    barcode: _detectBarcodeType(),
                    data: widget.barcode,
                    width: 250,
                    height: 80,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.barcode, style: const TextStyle(fontFamily: 'monospace', color: AppTheme.textSecondary, fontSize: 11)),
                      Text('${widget.price} د', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // عدد النسخ
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('عدد النسخ:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: AppTheme.primaryColor),
                  onPressed: _copies > 1 ? () {
                    setState(() {
                      _copies--;
                      _copiesController.text = '$_copies';
                    });
                  } : null,
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _copiesController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primaryColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.primaryColor)),
                    ),
                    onChanged: (val) {
                      final n = int.tryParse(val);
                      if (n != null && n >= 1 && n <= 999) {
                        setState(() => _copies = n);
                      }
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                  onPressed: _copies < 999 ? () {
                    setState(() {
                      _copies++;
                      _copiesController.text = '$_copies';
                    });
                  } : null,
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
