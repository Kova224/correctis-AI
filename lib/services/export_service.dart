import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/copy.dart';
import '../models/exam.dart';
import 'ranking_service.dart';

/// Génère un fichier Excel récapitulatif avec entête Correctis et présentation
/// adaptative selon le nombre d'élèves.
class ExportService {
  Future<File> exportToExcel({
    required Exam exam,
    required List<StudentCopy> copies,
  }) async {
    final excel = Excel.createExcel();
    const sheetName = 'Résultats';
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);
    if (excel.tables.containsKey('Sheet1') && sheetName != 'Sheet1') {
      excel.delete('Sheet1');
    }

    // Styles
    final titleStyle = CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#2E4BC7'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final subtitleStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: ExcelColor.fromHexString('#1A1F36'),
      backgroundColorHex: ExcelColor.fromHexString('#EEF1F8'),
    );
    final metaStyle = CellStyle(
      fontSize: 10,
      fontColorHex: ExcelColor.fromHexString('#6B7280'),
      italic: true,
    );
    final headerStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#2E4BC7'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );
    final cellStyle = CellStyle(
      fontSize: 10,
      verticalAlign: VerticalAlign.Center,
    );
    final scoreStyle = CellStyle(
      bold: true,
      fontSize: 11,
      horizontalAlign: HorizontalAlign.Center,
      fontColorHex: ExcelColor.fromHexString('#2E4BC7'),
    );

    // === LIGNE 1 — Bandeau titre Correctis ===
    sheet.appendRow(<CellValue>[TextCellValue('  📚  CORRECTIS  —  Correction IA des copies')]);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .cellStyle = titleStyle;
    sheet.setRowHeight(0, 30);

    // === LIGNE 2 — Titre de l'examen ===
    sheet.appendRow(<CellValue>[TextCellValue('  ${exam.title}')]);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .cellStyle = subtitleStyle;
    sheet.setRowHeight(1, 22);

    // === LIGNE 3 — Méta-infos (classe, date, candidats, total) ===
    final df = DateFormat('d MMMM yyyy', 'fr_FR');
    final metaParts = <String>[
      if (exam.className?.isNotEmpty == true) 'Classe : ${exam.className}',
      'Date : ${df.format(DateTime.now())}',
      '${copies.length} candidat${copies.length > 1 ? 's' : ''}',
      'Sur ${_fmt(exam.computedTotal == 0 ? exam.totalPoints : exam.computedTotal)} pts',
    ];
    sheet.appendRow(<CellValue>[TextCellValue('  ${metaParts.join('   •   ')}')]);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2))
        .cellStyle = metaStyle;

    // === LIGNE 4 — vide pour respirer ===
    sheet.appendRow(<CellValue>[]);

    // === LIGNE 5 — En-têtes colonnes ===
    // On génère une colonne par "leaf"
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
      TextCellValue('#'),
      TextCellValue('Nom'),
      TextCellValue('PV / Réf.'),
      TextCellValue('Note'),
      TextCellValue('Sur'),
      TextCellValue('%'),
      TextCellValue('Statut'),
      TextCellValue('Confiance IA'),
      ...leafHeaders.map((h) => TextCellValue(h.label)),
    ];
    sheet.appendRow(header);
    final headerRowIndex = sheet.maxRows - 1;
    for (int i = 0; i < header.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: headerRowIndex,
      )).cellStyle = headerStyle;
    }
    sheet.setRowHeight(headerRowIndex, 28);

    // === LIGNES suivantes — un élève par ligne ===
    final total =
        exam.computedTotal == 0 ? exam.totalPoints : exam.computedTotal;
    // Tri : corrigées par note descendante, puis non-corrigées
    final sorted = [...copies]..sort((a, b) {
        if (a.status == CopyStatus.graded && b.status != CopyStatus.graded) {
          return -1;
        }
        if (b.status == CopyStatus.graded && a.status != CopyStatus.graded) {
          return 1;
        }
        return b.totalScore.compareTo(a.totalScore);
      });

    for (int i = 0; i < sorted.length; i++) {
      final copy = sorted[i];
      final percent = total == 0 ? 0.0 : (copy.totalScore / total) * 100;

      final row = <CellValue>[
        IntCellValue(i + 1),
        TextCellValue(copy.studentName),
        TextCellValue(copy.studentRef ?? ''),
        DoubleCellValue(_round(copy.totalScore)),
        DoubleCellValue(_round(total)),
        DoubleCellValue(_round(percent)),
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

      final rowIdx = sheet.maxRows - 1;
      for (int col = 0; col < row.length; col++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx))
            .cellStyle = col == 3 ? scoreStyle : cellStyle;
      }
    }

    // === Pied de page : ligne vide + récap ===
    sheet.appendRow(<CellValue>[]);
    final gradedCount =
        copies.where((c) => c.status == CopyStatus.graded).length;
    final avgScore = gradedCount == 0
        ? 0.0
        : copies
                .where((c) => c.status == CopyStatus.graded)
                .fold<double>(0, (s, c) => s + c.totalScore) /
            gradedCount;
    final avgPercent = total == 0 ? 0.0 : (avgScore / total) * 100;
    sheet.appendRow(<CellValue>[
      TextCellValue('Moyenne de classe :'),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(_round(avgScore)),
      DoubleCellValue(_round(total)),
      DoubleCellValue(_round(avgPercent)),
    ]);
    final summaryRowIdx = sheet.maxRows - 1;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: summaryRowIdx))
        .cellStyle = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#EEF1F8'),
    );

    sheet.appendRow(<CellValue>[]);
    sheet.appendRow(<CellValue>[
      TextCellValue('Généré par Correctis — correctis.app — ${df.format(DateTime.now())}'),
    ]);
    final footerRowIdx = sheet.maxRows - 1;
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: footerRowIdx))
        .cellStyle = metaStyle;

    // Largeurs des colonnes
    sheet.setColumnWidth(0, 6);   // #
    sheet.setColumnWidth(1, 24);  // Nom
    sheet.setColumnWidth(2, 14);  // PV
    sheet.setColumnWidth(3, 10);  // Note
    sheet.setColumnWidth(4, 8);   // Sur
    sheet.setColumnWidth(5, 8);   // %
    sheet.setColumnWidth(6, 14);  // Statut
    sheet.setColumnWidth(7, 12);  // Confiance
    for (int i = 0; i < leafHeaders.length; i++) {
      sheet.setColumnWidth(8 + i, 16);
    }

    // Écriture du fichier
    final dir = await getApplicationDocumentsDirectory();
    final safeTitle = exam.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final file = File(
      '${dir.path}/Correctis_${safeTitle}_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
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

    final titleStyle = CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#2E4BC7'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final subtitleStyle = CellStyle(
      bold: true,
      fontSize: 11,
      backgroundColorHex: ExcelColor.fromHexString('#EEF1F8'),
    );
    final headerStyle = CellStyle(
      bold: true,
      fontSize: 11,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#2E4BC7'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final cellStyle = CellStyle(fontSize: 10);

    // En-tête Correctis
    sheet.appendRow(<CellValue>[TextCellValue('  🏆  CLASSEMENT CORRECTIS')]);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .cellStyle = titleStyle;
    sheet.setRowHeight(0, 30);

    sheet.appendRow(<CellValue>[TextCellValue('  ${exam.title}')]);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1))
        .cellStyle = subtitleStyle;

    final df = DateFormat('d MMMM yyyy', 'fr_FR');
    final metaParts = <String>[
      if (exam.className?.isNotEmpty == true) 'Classe : ${exam.className}',
      'Date : ${df.format(DateTime.now())}',
      '${ranking.where((e) => e.position > 0).length} classés',
    ];
    sheet.appendRow(<CellValue>[TextCellValue('  ${metaParts.join('   •   ')}')]);
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
    final headerRowIdx = sheet.maxRows - 1;
    for (int i = 0; i < header.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: headerRowIdx,
      )).cellStyle = headerStyle;
    }
    sheet.setRowHeight(headerRowIdx, 26);

    for (final e in ranking) {
      sheet.appendRow(<CellValue>[
        e.position == 0 ? TextCellValue('—') : IntCellValue(e.position),
        TextCellValue(e.studentName),
        TextCellValue(e.studentRef ?? ''),
        DoubleCellValue(_round(e.score)),
        DoubleCellValue(_round(e.maxScore)),
        DoubleCellValue(_round(e.percent)),
        TextCellValue(e.mention ?? ''),
        TextCellValue(e.status.label),
      ]);
      final rowIdx = sheet.maxRows - 1;
      for (int col = 0; col < 8; col++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx))
            .cellStyle = cellStyle;
      }
    }

    // Pied de page
    sheet.appendRow(<CellValue>[]);
    sheet.appendRow(<CellValue>[
      TextCellValue('Généré par Correctis — correctis.app — ${df.format(DateTime.now())}'),
    ]);

    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 26);
    sheet.setColumnWidth(2, 14);
    sheet.setColumnWidth(3, 10);
    sheet.setColumnWidth(4, 8);
    sheet.setColumnWidth(5, 8);
    sheet.setColumnWidth(6, 16);
    sheet.setColumnWidth(7, 14);

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
