import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/copy.dart';
import '../models/exam.dart';
import 'ranking_service.dart';

/// Génère un fichier Excel récapitulatif et propose le partage natif
/// (cahier §3.6 — bouton Export Excel).
class ExportService {
  Future<File> exportToExcel({
    required Exam exam,
    required List<StudentCopy> copies,
  }) async {
    final excel = Excel.createExcel();
    const sheetName = 'Résultats';
    final sheet = excel[sheetName];
    // Définit notre feuille comme active et supprime "Sheet1" auto-créée
    excel.setDefaultSheet(sheetName);
    if (excel.tables.containsKey('Sheet1') && sheetName != 'Sheet1') {
      excel.delete('Sheet1');
    }

    // En-tête : on génère une colonne par "leaf" (question simple ou sous-question)
    final leafHeaders = <_LeafHeader>[];
    for (final q in exam.questions) {
      if (q.isLeaf) {
        leafHeaders.add(_LeafHeader(
          id: q.id,
          label: '${_shortLabel(q.label)} (/${_fmt(q.points)})',
          maxPoints: q.points,
        ));
      } else {
        for (final sub in q.subQuestions) {
          leafHeaders.add(_LeafHeader(
            id: sub.id,
            label:
                '${_shortLabel(q.label)} — ${sub.label} (/${_fmt(sub.points)})',
            maxPoints: sub.points,
          ));
        }
      }
    }

    final header = <CellValue>[
      TextCellValue('Nom'),
      TextCellValue('PV / Réf.'),
      TextCellValue('Note finale'),
      TextCellValue('Sur'),
      TextCellValue('Statut'),
      TextCellValue('Confiance IA'),
      ...leafHeaders.map((h) => TextCellValue(h.label)),
    ];
    sheet.appendRow(header);

    final total = exam.computedTotal == 0 ? exam.totalPoints : exam.computedTotal;
    for (final copy in copies) {
      final row = <CellValue>[
        TextCellValue(copy.studentName),
        TextCellValue(copy.studentRef ?? ''),
        DoubleCellValue(_round(copy.totalScore)),
        DoubleCellValue(_round(total)),
        TextCellValue(copy.status.label),
        DoubleCellValue(_round(copy.confidence * 100)),
        ...leafHeaders.map((h) {
          final grade = copy.grades.firstWhere(
            (g) => g.questionId == h.id,
            orElse: () => QuestionGrade(questionId: h.id, score: 0),
          );
          return DoubleCellValue(_round(grade.score));
        }),
      ];
      sheet.appendRow(row);
    }

    // Style bold sur la 1ère ligne
    for (int i = 0; i < header.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.cellStyle = CellStyle(bold: true);
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = exam.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final file = File('${dir.path}/Correctis_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    final bytes = excel.encode();
    if (bytes == null) {
      throw 'Impossible de générer le fichier Excel.';
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> shareFile(File file, {String? subject}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject ?? 'Résultats Correctis',
    );
  }

  /// Export Excel du classement d'un examen (avec position, mention, etc.)
  Future<File> exportRankingToExcel({
    required Exam exam,
    required List<RankingEntry> ranking,
  }) async {
    final excel = Excel.createExcel();
    const sheetName = 'Classement';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.tables.containsKey('Sheet1') && sheetName != 'Sheet1') {
      excel.delete('Sheet1');
    }

    // Méta-info en haut
    sheet.appendRow(<CellValue>[TextCellValue('Examen :'), TextCellValue(exam.title)]);
    if (exam.className?.isNotEmpty == true) {
      sheet.appendRow(<CellValue>[TextCellValue('Classe :'), TextCellValue(exam.className!)]);
    }
    sheet.appendRow(<CellValue>[TextCellValue('Date :'), TextCellValue(DateTime.now().toString().split('.').first)]);
    sheet.appendRow(<CellValue>[]);

    // En-tête tableau
    final header = <CellValue>[
      TextCellValue('Rang'),
      TextCellValue('Nom'),
      TextCellValue('PV / Réf.'),
      TextCellValue('Note'),
      TextCellValue('Sur'),
      TextCellValue('%'),
      TextCellValue('Mention'),
      TextCellValue('Statut'),
    ];
    sheet.appendRow(header);
    final headerRowIndex = sheet.maxRows - 1;
    for (int i = 0; i < header.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: headerRowIndex,
      )).cellStyle = CellStyle(bold: true);
    }

    for (final e in ranking) {
      sheet.appendRow(<CellValue>[
        e.position == 0
            ? TextCellValue('—')
            : IntCellValue(e.position),
        TextCellValue(e.studentName),
        TextCellValue(e.studentRef ?? ''),
        DoubleCellValue(_round(e.score)),
        DoubleCellValue(_round(e.maxScore)),
        DoubleCellValue(_round(e.percent)),
        TextCellValue(e.mention ?? ''),
        TextCellValue(e.status.label),
      ]);
    }

    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = exam.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final file = File(
      '${dir.path}/Classement_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    final bytes = excel.encode();
    if (bytes == null) {
      throw 'Impossible de générer le fichier Excel.';
    }
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _shortLabel(String label) {
    if (label.length <= 18) return label;
    final dot = label.indexOf('.');
    if (dot > 0 && dot < 6) return label.substring(0, dot + 1);
    return '${label.substring(0, 16)}…';
  }

  double _round(double v) => (v * 100).roundToDouble() / 100;

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }
}

class _LeafHeader {
  final String id;
  final String label;
  final double maxPoints;
  const _LeafHeader({
    required this.id,
    required this.label,
    required this.maxPoints,
  });
}
