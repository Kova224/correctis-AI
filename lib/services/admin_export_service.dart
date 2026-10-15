import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/establishment.dart';
import '../screens/admin/admin_models.dart';

/// Service d'export pour la vue Admin Établissement.
///
/// Génère :
///   • Bulletin PDF d'un élève (toutes matières + moyenne pondérée)
///   • Excel global du casier (toutes notes de l'école sur une période)
///
/// Les fichiers sont sauvés dans le répertoire temporaire puis partagés
/// via le bottom sheet système (share_plus).
class AdminExportService {
  // ─────────────────────────────────────────────────────────────────────────
  // BULLETIN PDF
  // ─────────────────────────────────────────────────────────────────────────

  /// Génère le bulletin PDF d'un élève et déclenche le partage système.
  Future<File> exportStudentBulletin({
    required Establishment establishment,
    required String studentName,
    required String className,
    required List<AdminStudentNote> notes,
    AcademicTerm? term,
  }) async {
    final pdf = pw.Document();

    // Group by matière
    final groups = <String, List<AdminStudentNote>>{};
    for (final n in notes) {
      groups.putIfAbsent(n.matiere, () => []).add(n);
    }

    // Moyennes par matière + moyenne générale pondérée
    final subjectAverages = <_SubjAvg>[];
    double sumWeighted = 0;
    double sumCoefs = 0;
    groups.forEach((subject, ns) {
      final avg = ns.fold<double>(0, (acc, n) => acc + n.note) / ns.length;
      final coef = establishment.config.coefficientFor(subject);
      subjectAverages.add(_SubjAvg(
        subject: subject,
        average: avg,
        count: ns.length,
        coefficient: coef,
      ));
      sumWeighted += avg * coef;
      sumCoefs += coef;
    });
    subjectAverages.sort((a, b) => a.subject.compareTo(b.subject));
    final moyenneGen = sumCoefs > 0 ? sumWeighted / sumCoefs : 0.0;

    // Couleurs
    const purple = PdfColor.fromInt(0xFFA78BFA);
    const purpleDark = PdfColor.fromInt(0xFF6D28D9);
    const darkGray = PdfColor.fromInt(0xFF1E293B);
    const lightGray = PdfColor.fromInt(0xFFE2E8F0);
    const muted = PdfColor.fromInt(0xFF64748B);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                gradient: const pw.LinearGradient(
                  colors: [purpleDark, PdfColor.fromInt(0xFF3B82F6)],
                ),
                borderRadius: const pw.BorderRadius.all(
                  pw.Radius.circular(10),
                ),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'BULLETIN SCOLAIRE',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    establishment.name,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    [
                      if (establishment.city != null) establishment.city!,
                      establishment.planLabel,
                    ].join(' · '),
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Infos élève
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ÉLÈVE',
                        style: pw.TextStyle(
                          color: muted,
                          fontSize: 8,
                          letterSpacing: 1.5,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        studentName,
                        style: pw.TextStyle(
                          color: darkGray,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        className,
                        style: const pw.TextStyle(
                          color: muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFF3F0FF),
                    border: pw.Border.all(color: purple),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        moyenneGen.toStringAsFixed(2),
                        style: pw.TextStyle(
                          color: purpleDark,
                          fontSize: 26,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'MOYENNE / 20',
                        style: pw.TextStyle(
                          color: muted,
                          fontSize: 8,
                          letterSpacing: 1.2,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (term != null) ...[
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFF3F0FF),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(20),
                  ),
                ),
                child: pw.Text(
                  '${term.name.toUpperCase()} · '
                  '${_fmtDate(term.start)} - ${_fmtDate(term.end)}',
                  style: pw.TextStyle(
                    color: purpleDark,
                    fontSize: 9,
                    letterSpacing: 1,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],

            pw.SizedBox(height: 24),

            // Tableau matières
            pw.Table(
              border: pw.TableBorder.symmetric(
                inside: const pw.BorderSide(color: lightGray),
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1),
                3: pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFF8F8F8),
                  ),
                  children: [
                    _tableHeader('MATIÈRE'),
                    _tableHeader('COEF', center: true),
                    _tableHeader('NOTES', center: true),
                    _tableHeader('MOYENNE', center: true),
                  ],
                ),
                ...subjectAverages.map((s) => pw.TableRow(
                      children: [
                        _tableCell(s.subject, bold: true),
                        _tableCell(
                          s.coefficient.toStringAsFixed(
                              s.coefficient == s.coefficient.roundToDouble()
                                  ? 0
                                  : 1),
                          center: true,
                        ),
                        _tableCell('${s.count}', center: true),
                        _tableCell(
                          s.average.toStringAsFixed(2),
                          center: true,
                          color: _colorForGrade(s.average),
                          bold: true,
                        ),
                      ],
                    )),
              ],
            ),

            pw.Spacer(),

            // Footer
            pw.Divider(color: lightGray),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Bulletin généré le ${_fmtDate(DateTime.now())}',
                  style: const pw.TextStyle(color: muted, fontSize: 8),
                ),
                pw.Text(
                  'CORRECTIS',
                  style: pw.TextStyle(
                    color: muted,
                    fontSize: 8,
                    letterSpacing: 1.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final safeName = studentName
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toLowerCase();
    final file = File('${dir.path}/bulletin_${safeName}_'
        '${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareFile(File file, {String? text}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      text: text,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXCEL GLOBAL CASIER
  // ─────────────────────────────────────────────────────────────────────────

  /// Génère l'Excel de toutes les notes filtrées (casier).
  Future<File> exportCasierExcel({
    required Establishment establishment,
    required List<AdminStudentNote> notes,
    AcademicTerm? term,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Casier'];
    excel.delete('Sheet1');

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#6D28D9'),
      horizontalAlign: HorizontalAlign.Center,
    );

    // Ligne 1 : titre
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .value = TextCellValue('Casier numérique · ${establishment.name}');
    if (term != null) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
          .value = TextCellValue(
        'Période : ${term.name} (${_fmtDate(term.start)} → ${_fmtDate(term.end)})',
      );
    }

    // Ligne 3 : en-têtes
    const startRow = 3;
    final headers = ['Élève', 'Classe', 'Matière', 'Enseignant', 'Note /20', 'Date'];
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: startRow));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // Données
    for (int r = 0; r < notes.length; r++) {
      final n = notes[r];
      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: startRow + 1 + r))
          .value = TextCellValue(n.student);
      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: 1, rowIndex: startRow + 1 + r))
          .value = TextCellValue(n.className);
      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: 2, rowIndex: startRow + 1 + r))
          .value = TextCellValue(n.matiere);
      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: 3, rowIndex: startRow + 1 + r))
          .value = TextCellValue(n.teacher);
      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: 4, rowIndex: startRow + 1 + r))
          .value = DoubleCellValue(n.note);
      sheet
          .cell(CellIndex.indexByColumnRow(
              columnIndex: 5, rowIndex: startRow + 1 + r))
          .value = TextCellValue(_fmtDate(n.date));
    }

    // Largeurs de colonnes
    sheet.setColumnWidth(0, 24);
    sheet.setColumnWidth(1, 12);
    sheet.setColumnWidth(2, 18);
    sheet.setColumnWidth(3, 22);
    sheet.setColumnWidth(4, 10);
    sheet.setColumnWidth(5, 14);

    final bytes = excel.save();
    if (bytes == null) throw 'Erreur génération Excel';

    final dir = await getTemporaryDirectory();
    final safeName = establishment.name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
        .toLowerCase();
    final file = File('${dir.path}/casier_${safeName}_'
        '${DateTime.now().millisecondsSinceEpoch}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}';

  static PdfColor _colorForGrade(double note) {
    if (note >= 14) return const PdfColor.fromInt(0xFF059669); // vert
    if (note >= 10) return const PdfColor.fromInt(0xFF3B82F6); // bleu
    return const PdfColor.fromInt(0xFFD97706); // amber
  }

  static pw.Widget _tableHeader(String text, {bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          letterSpacing: 1.2,
          fontWeight: pw.FontWeight.bold,
          color: const PdfColor.fromInt(0xFF64748B),
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  static pw.Widget _tableCell(
    String text, {
    bool center = false,
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? const PdfColor.fromInt(0xFF1E293B),
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }
}

class _SubjAvg {
  final String subject;
  final double average;
  final int count;
  final double coefficient;
  const _SubjAvg({
    required this.subject,
    required this.average,
    required this.count,
    required this.coefficient,
  });
}
