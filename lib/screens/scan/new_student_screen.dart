import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import 'scan_session_screen.dart';

/// Étape 1 — Saisie du nom/PV de l'élève (§3.4 étape 1).
class NewStudentScreen extends StatefulWidget {
  final String examId;
  const NewStudentScreen({super.key, required this.examId});

  @override
  State<NewStudentScreen> createState() => _NewStudentScreenState();
}

class _NewStudentScreenState extends State<NewStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ref = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final copy = await context.read<ExamService>().createCopy(
            examId: widget.examId,
            studentName: _name.text.trim(),
            studentRef:
                _ref.text.trim().isEmpty ? null : _ref.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScanSessionScreen(copyId: copy.id),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                  const Icon(Icons.person_add_alt_1,
                      color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'NOUVEL ÉLÈVE',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1 élève = 1 session de scan',
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
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Identification',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          label: 'Nom et prénom *',
                          hint: 'Ex : Dupont Jean',
                          controller: _name,
                          textInputAction: TextInputAction.next,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Nom requis'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        CustomTextField(
                          label: 'PV / Matricule (optionnel)',
                          hint: 'Ex : PV-2026-0042',
                          controller: _ref,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _start(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Démarrer le scan',
                    icon: Icons.qr_code_scanner,
                    loading: _saving,
                    onPressed: _start,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
