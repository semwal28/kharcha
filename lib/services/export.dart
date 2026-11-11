import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/brand.dart';
import '../core/money.dart';
import '../data/models.dart';
import '../domain/analysis.dart';

/// CSV and PDF exports, and sharing files or images from the app.
abstract final class Exporter {
  static String _csvCell(String v) => '"${v.replaceAll('"', '""')}"';

  /// Every loaded expense (this month and last), one row each.
  static String csv(AppData data) {
    final b = StringBuffer('Date,Time,Description,Category,Amount,Currency,Paid by,Repeats monthly\n');
    for (final t in data.txns) {
      final c = data.cat(t.categoryId);
      final d = t.spentAt;
      b.writeln(
        [
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
          hhmm(d),
          _csvCell(t.titleOr(c.name)),
          _csvCell(c.name),
          (t.amountPaise / 100).toStringAsFixed(2),
          Money.currency.code,
          t.pay.label,
          t.isRecurring ? 'yes' : 'no',
        ].join(','),
      );
    }
    return b.toString();
  }

  /// Amount for the PDF. Uses the currency code (e.g. "INR 1,250") because
  /// the built-in PDF font has no ₹ or other currency symbols.
  static String _pdfMoney(num minor) => '${Money.currency.code} ${Money.grouped((minor / 100).round())}';

  static Future<Uint8List> pdf(AppData data, MonthSummary s) async {
    final doc = pw.Document(title: '$kAppName report ${s.monthName} ${s.now.year}', author: kAppName);
    final teal = PdfColor.fromInt(0xFF0D5C70);
    final cats = s.cats.values.where((c) => c.spent > 0).toList()..sort((a, b) => b.spent.compareTo(a.spent));
    final month = s.cur.toList()..sort((a, b) => a.spentAt.compareTo(b.spentAt));
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              kAppName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: teal, fontSize: 16),
            ),
            pw.Text('${s.monthName} ${s.now.year}', style: const pw.TextStyle(fontSize: 11)),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.SizedBox(height: 12),
          pw.Text('Spent so far: ${_pdfMoney(s.spent)}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Budget ${_pdfMoney(s.totalBudget)}  ·  Month-end forecast ${_pdfMoney(s.projected)}  ·  ${month.length} expenses',
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          if (s.leaks.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('Ways to save (about ${_pdfMoney(s.monthlySavings)} a month)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
            pw.SizedBox(height: 6),
            for (final l in s.leaks) pw.Bullet(text: '${l.title}: ${l.action}', style: const pw.TextStyle(fontSize: 10)),
          ],
          pw.SizedBox(height: 16),
          pw.Text('By category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Category', 'Spent', 'Budget', 'Last month'],
            data: [
              for (final c in cats) [c.category.name, _pdfMoney(c.spent), c.budget > 0 ? _pdfMoney(c.budget) : '-', _pdfMoney(c.prev)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: teal),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 16),
          pw.Text('Expenses', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Description', 'Category', 'Amount'],
            data: [
              for (final t in month) [fmtDay(t.spentAt), t.titleOr(data.cat(t.categoryId).name), data.cat(t.categoryId).name, _pdfMoney(t.amountPaise)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {3: pw.Alignment.centerRight},
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Shares a file through the phone's share sheet; on the web it downloads.
  static Future<void> shareFile(Uint8List bytes, {required String name, required String mimeType, String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: name)],
        fileNameOverrides: [name],
        text: text,
        subject: text,
        downloadFallbackEnabled: true,
      ),
    );
  }

  static Future<void> shareCsv(AppData data) =>
      shareFile(Uint8List.fromList(utf8.encode(csv(data))), name: '${kAppName.toLowerCase()}-expenses.csv', mimeType: 'text/csv');

  static Future<void> sharePdf(AppData data, MonthSummary s) async =>
      shareFile(await pdf(data, s), name: '${kAppName.toLowerCase()}-${s.monthName.toLowerCase()}-${s.now.year}.pdf', mimeType: 'application/pdf');
}
