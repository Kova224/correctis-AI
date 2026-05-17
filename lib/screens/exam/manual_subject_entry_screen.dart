import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';

/// Saisie manuelle du sujet : le prof colle/tape le sujet exact
/// avec sa structure (Exercice → sous-questions), et le parser produit
/// la structure de questions correspondante.
///
/// Format attendu (souple) :
///
///   Exercice 1 (5 pts)
///   Énoncé sur plusieurs lignes…
///   a) Énoncé sous-question  /1.5
///   b) Énoncé sous-question  /2
///   c) Énoncé sous-question  /1.5
///
///   Exercice 2 (4 pts)
///   ...
///
///   Question 3 (3 pts)
///   Énoncé d'une question simple sans sous-question.
class ManualSubjectEntryScreen extends StatefulWidget {
  final List<Question> initial;
  const ManualSubjectEntryScreen({super.key, required this.initial});

  @override
  State<ManualSubjectEntryScreen> createState() =>
      _ManualSubjectEntryScreenState();
}

class _ManualSubjectEntryScreenState extends State<ManualSubjectEntryScreen> {
  late final TextEditingController _ctrl;
  String _preview = '';
  int _exoCount = 0;
  int _subCount = 0;
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _toText(widget.initial));
    _ctrl.addListener(_recompute);
    _recompute();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _recompute() {
    final qs = parseManualSubject(_ctrl.text);
    int subs = 0;
    double tot = 0;
    for (final q in qs) {
      tot += q.totalPoints;
      subs += q.subQuestions.length;
    }
    setState(() {
      _exoCount = qs.length;
      _subCount = subs;
      _total = tot;
      _preview = '${qs.length} exercice(s)/question(s) • $subs sous-question(s) • ${_fmt(tot)} pts';
    });
  }

  String _toText(List<Question> qs) {
    final buffer = StringBuffer();
    for (final q in qs) {
      final pts = q.totalPoints;
      buffer.writeln('${q.label}${pts > 0 ? " (${_fmt(pts)} pts)" : ""}');
      if (q.statement.isNotEmpty) buffer.writeln(q.statement);
      for (final s in q.subQuestions) {
        buffer.writeln('${s.label} ${s.statement}  /${_fmt(s.points)}');
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  void _validate() {
    final qs = parseManualSubject(_ctrl.text);
    Navigator.of(context).pop(qs);
  }

  void _insertExample() {
    _ctrl.text = '''Exercice 1 (5 pts)
On considère la fonction f définie sur ℝ par f(x) = x² − 4x + 3.
a) Calculer f'(x) et étudier son signe.   /1.5
b) Dresser le tableau de variations de f.   /1.5
c) Tracer la courbe représentative de f.    /2

Exercice 2 (4 pts)
Résoudre dans ℝ l'équation : ln(x + 2) = 2·ln(x).
a) Donner l'ensemble de définition.   /1
b) Résoudre l'équation.               /3

Question 3 (3 pts)
Démontrer par récurrence que pour tout n ∈ ℕ, 2ⁿ ≥ n + 1.
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RoundedHeader(
            height: 200,
            showBackButton: true,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.edit_note, color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'SAISIE MANUELLE',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recopier exactement le sujet, avec ses sous-questions',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                // Aide
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Format attendu',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• Une ligne avec le titre : "Exercice 1 (5 pts)" ou "Question 1 (3 pts)"\n'
                        '• Les lignes suivantes : énoncé complet\n'
                        '• Sous-questions : "a) Énoncé /1.5" (la note après le slash)\n'
                        '• Une ligne vide sépare les exercices\n'
                        '• Les symboles, équations et formules sont conservés tels quels',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _insertExample,
                        icon: const Icon(Icons.lightbulb_outline, size: 18),
                        label: const Text('Voir un exemple'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Champ de saisie
                SectionCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    minLines: 14,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13.5,
                      height: 1.5,
                    ),
                    decoration: const InputDecoration(
                      hintText:
                          'Exercice 1 (5 pts)\nÉnoncé complet de l\'exercice ici…\na) Première sous-question  /2\nb) Seconde sous-question  /3',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Preview / résumé
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Détecté',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                  fontSize: 12,
                                )),
                            const SizedBox(height: 2),
                            Text(
                              _preview,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
            label: _exoCount == 0
                ? 'Aucun élément détecté'
                : 'Utiliser cette structure',
            icon: Icons.check,
            onPressed: _exoCount == 0 ? null : _validate,
          ),
        ),
      ),
    );
  }
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

// =============================================================================
// PARSER — convertit le texte saisi en List<Question>
// =============================================================================

/// Regex pour détecter un titre d'exercice/question :
///   "Exercice 1 (5 pts)", "Exercise 2 — 4pts", "Question 3 / 3", "Q1 (2)"
final _titleRegex = RegExp(
  r'^\s*(?:'
  r'(?:Exercice|Exercise|Ejercicio|Esercizio|Exercício|Aufgabe|Ex\.?|Exo\.?|تمرين)\s*\d+'
  r'|(?:Question|Pregunta|Domanda|Frage|Pergunta|سؤال|Q)\s*\.?\s*\d+'
  r'|\d+\s*[\)\.]'
  r')\s*[\.\:\-—]?',
  caseSensitive: false,
);

/// Détecte les points dans une ligne de titre : "(5 pts)", " /5", " — 4pts".
final _titlePointsRegex = RegExp(
  r'(?:\(|—|-|/)\s*(\d+(?:[.,]\d+)?)\s*(?:pts?|points?|نقاط)?\s*\)?',
  caseSensitive: false,
);

/// Détecte une sous-question : "a) ...", "b. ...", "1) ...", "ii) ..."
/// (lettre minuscule, chiffre, ou romain), puis énoncé.
final _subQuestionRegex = RegExp(
  r'^\s*([a-zA-Z]|[ivx]+|\d+)\s*[\)\.]\s*(.+)$',
);

/// Détecte les points en fin de ligne : "...énoncé /1.5" ou "...énoncé (2 pts)"
final _trailingPointsRegex = RegExp(
  r'(?:/|\s—\s|\s-\s|\()\s*(\d+(?:[.,]\d+)?)\s*(?:pts?|points?)?\s*\)?\s*$',
  caseSensitive: false,
);

List<Question> parseManualSubject(String text) {
  final lines = text.split('\n');
  final questions = <Question>[];
  Question? current;
  final statementLines = <String>[];

  void flushStatement() {
    if (current == null) return;
    if (statementLines.isEmpty) return;
    final base = current!.statement;
    final addition = statementLines.join('\n').trim();
    if (addition.isEmpty) {
      statementLines.clear();
      return;
    }
    current!.statement = base.isEmpty ? addition : '$base\n$addition';
    statementLines.clear();
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      flushStatement();
      continue;
    }

    // Titre d'exercice/question ?
    if (_titleRegex.hasMatch(line)) {
      flushStatement();
      // points éventuels
      double pts = 0;
      final m = _titlePointsRegex.firstMatch(line);
      if (m != null) {
        pts = double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
      }
      // titre nettoyé
      var label = line;
      if (m != null) {
        label = label.substring(0, m.start);
      }
      label = label.replaceAll(RegExp(r'[\s\-—\.\:]+$'), '').trim();
      if (label.isEmpty) {
        label = pts > 0 ? 'Question' : 'Question';
      }
      current = Question(label: label, statement: '', points: pts);
      questions.add(current);
      continue;
    }

    if (current == null) {
      // Pas encore de titre — on crée un exercice par défaut
      current = Question(label: 'Exercice 1', statement: '');
      questions.add(current);
    }

    // Sous-question ?
    final subMatch = _subQuestionRegex.firstMatch(line);
    if (subMatch != null) {
      flushStatement();
      var subLabel = subMatch.group(1)!;
      // Normalise : a) au lieu de a.
      if (!subLabel.contains(')')) subLabel = '$subLabel)';
      var subText = subMatch.group(2)!.trim();
      double subPts = 0;
      final pm = _trailingPointsRegex.firstMatch(subText);
      if (pm != null) {
        subPts = double.tryParse(pm.group(1)!.replaceAll(',', '.')) ?? 0;
        subText = subText.substring(0, pm.start).trim();
      }
      current!.subQuestions.add(SubQuestion(
        label: subLabel,
        statement: subText,
        points: subPts,
      ));
      // Si on a des sub-questions, on remet les points propres à 0.
      current!.points = 0;
      continue;
    }

    // Sinon → ligne d'énoncé pour la question courante (ou sa dernière sous-question)
    if (current!.subQuestions.isEmpty) {
      statementLines.add(line);
    } else {
      final lastSub = current!.subQuestions.last;
      lastSub.statement = lastSub.statement.isEmpty
          ? line.trim()
          : '${lastSub.statement}\n${line.trim()}';
    }
  }

  flushStatement();
  return questions;
}
