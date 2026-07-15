import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_text.dart';
import '../widgets/scanline_overlay.dart';
import '../services/hci_study_service.dart';
import 'student_problem_screen.dart';
import 'student_quest_screen.dart';

// ─────────────────────────────────────────────────────────────────────────
//  SUS Survey Screen
//
//  Shown identically to BOTH Condition A and Condition B right after the
//  quiz finishes, before quests are generated. This screen is deliberately
//  condition-blind (same layout/copy regardless of useGestalt) — it is a
//  measurement instrument, not part of either treatment, so it must not
//  itself introduce a confound between conditions.
//
//  Uses the standard 10-item System Usability Scale (Brooke, 1996), scored
//  0–100 via the standard formula:
//    odd items (1,3,5,7,9):  contribution = rating - 1
//    even items (2,4,6,8,10): contribution = 5 - rating
//    SUS score = sum(contributions) * 2.5
// ─────────────────────────────────────────────────────────────────────────
class SusSurveyScreen extends StatefulWidget {
  final String playerName;
  final String schedule;
  final StudentProblem problem;
  final List<String> selectedCauses;
  final List<String> quizAnswers;

  const SusSurveyScreen({
    super.key,
    required this.playerName,
    required this.schedule,
    required this.problem,
    required this.selectedCauses,
    required this.quizAnswers,
  });

  @override
  State<SusSurveyScreen> createState() => _SusSurveyScreenState();
}

class _SusSurveyScreenState extends State<SusSurveyScreen> {
  static const List<String> _items = [
    'I think that I would use this quiz screen frequently.',
    'I found the quiz unnecessarily complex.',
    'I thought the quiz was easy to use.',
    'I think I would need help to be able to use this quiz.',
    'I found the various parts of the quiz well integrated.',
    'I thought there was too much inconsistency in the quiz.',
    'I would imagine most people would learn to use this quiz quickly.',
    'I found the quiz very cumbersome to use.',
    'I felt very confident using the quiz.',
    'I needed to learn a lot of things before I could get going with the quiz.',
  ];

  final Map<int, int> _responses = {}; // item index (0-9) → rating (1-5)
  bool _submitting = false;

  bool get _allAnswered => _responses.length == _items.length;

  double _computeSusScore() {
    double total = 0;
    for (int i = 0; i < _items.length; i++) {
      final rating = _responses[i]!;
      final isOdd = i % 2 == 0; // items 1,3,5,7,9 → index 0,2,4,6,8
      total += isOdd ? (rating - 1) : (5 - rating);
    }
    return total * 2.5;
  }

  Future<void> _submit() async {
    if (!_allAnswered || _submitting) return;
    setState(() => _submitting = true);

    final score = _computeSusScore();
    final rawAnswers = List.generate(_items.length, (i) => _responses[i]!);

    try {
      await HciStudyService().submitSus(susScore: score, rawAnswers: rawAnswers);
    } catch (_) {
      // Non-fatal — study logging should never block the product flow.
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => StudentQuestScreen(
          playerName: widget.playerName,
          schedule: widget.schedule,
          problem: widget.problem,
          selectedCauses: widget.selectedCauses,
          quizAnswers: widget.quizAnswers,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg900,
      body: ScanlineOverlay(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '// POST-TASK USABILITY QUESTIONNAIRE',
                      style: AppTheme.monoFont(
                          size: 10, color: AppTheme.mana, letterSpacing: 2),
                    ),
                    const SizedBox(height: 10),
                    const GlitchText(
                      text: 'RATE THIS\nQUIZ SCREEN',
                      fontSize: 24,
                      useDisplay: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'For each statement below, give your immediate reaction. '
                      'There are no right or wrong answers — please respond '
                      'honestly, even if you are unsure.',
                      style:
                          AppTheme.monoFont(size: 12, color: AppTheme.text400),
                    ),
                    const SizedBox(height: 14),
                    _buildLegend(),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _buildItem(index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: GestureDetector(
                  onTap: _allAnswered && !_submitting ? _submit : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: _allAnswered ? AppTheme.copper : AppTheme.bg700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        _submitting
                            ? 'SAVING...'
                            : _allAnswered
                                ? 'CONTINUE  ›'
                                : 'ANSWER ALL ${_items.length} TO CONTINUE',
                        style: AppTheme.displayFont(
                          size: 12,
                          color: _allAnswered
                              ? AppTheme.bg900
                              : AppTheme.text400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    const labels = [
      '1 STRONGLY\nDISAGREE',
      '2 DISAGREE',
      '3 NEUTRAL',
      '4 AGREE',
      '5 STRONGLY\nAGREE',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderDim),
        color: AppTheme.bg800,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: labels
            .map((l) => Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: AppTheme.monoFont(size: 7, color: AppTheme.text600),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildItem(int index) {
    final selected = _responses[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderDim),
        color: AppTheme.bg800,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}. ${_items[index]}',
            style: AppTheme.monoFont(size: 12, color: AppTheme.text100),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (i) {
              final rating = i + 1;
              final isSelected = selected == rating;
              return GestureDetector(
                onTap: () => setState(() => _responses[index] = rating),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color:
                            isSelected ? AppTheme.copper : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.copper
                              : AppTheme.borderBright,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$rating',
                          style: AppTheme.monoFont(
                            size: 13,
                            color:
                                isSelected ? AppTheme.bg900 : AppTheme.text400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DISAGREE',
                  style: AppTheme.monoFont(size: 8, color: AppTheme.text600)),
              Text('AGREE',
                  style: AppTheme.monoFont(size: 8, color: AppTheme.text600)),
            ],
          ),
        ],
      ),
    );
  }
}
