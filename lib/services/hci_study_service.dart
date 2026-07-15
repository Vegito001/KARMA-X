import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/hci_mode.dart';

/// Handles all Supabase reads/writes for the HCI A/B study:
/// - `hci_sessions`        — one row per quiz attempt (condition, SUS score, quest rating)
/// - `hci_question_events` — one row per (session, question): timing, the
///                           actual answer chosen, revisions, and backtracks
///
/// Every method here is deliberately fire-and-forget-safe: a failure to log
/// study data (e.g. offline, RLS misconfigured) should never block or crash
/// the actual product flow. Errors are caught and printed, not rethrown.
///
/// ── Formulas this data supports (for the paper's Methods/Results) ──────────
///   decision latency (question i)  = answered_at_i  − shown_at_i   (seconds)
///   active time on question (i)    = last_modified_at_i − shown_at_i (seconds)
///   revision rate (session)        = Σ revision_count  / n_questions
///   backtrack rate (session)       = Σ backtrack_count / n_questions
///   quiz duration (session)        = quiz_finished_at − started_at (seconds)
///   SUS score                      = see sus_survey_screen.dart (Brooke 1996 formula)
/// All of the above are also pre-computed in the `hci_session_summary` SQL
/// view (see HCI_STUDY_SETUP.sql) so they can be pulled directly for tables/plots.
class HciStudyService {
  final _db = Supabase.instance.client;

  /// Starts a new session row for the current quiz attempt. Call this right
  /// after `HciMode.instance.startNewSession()`. Returns the session id on
  /// success (also stored in `HciMode.instance.currentSessionId`), or null
  /// if logging failed — callers should treat null as "logging unavailable"
  /// and continue the app flow normally.
  Future<String?> startSession({required String problemTitle}) async {
    final sessionId = HciMode.instance.currentSessionId;
    if (sessionId == null) return null;

    try {
      final userId = _db.auth.currentUser?.id;
      await _db.from('hci_sessions').insert({
        'id': sessionId,
        'user_id': userId,
        'condition': HciMode.instance.conditionLabel,
        'problem_title': problemTitle,
      });
      return sessionId;
    } catch (e) {
      debugPrint('HciStudyService.startSession failed: $e');
      return null;
    }
  }

  /// Upserts a per-question event: timing, the answer currently selected,
  /// how many times it's been revised, and how many times the participant
  /// has backtracked TO this question from a later one. Safe to call
  /// repeatedly for the same question — it updates the same row thanks to
  /// the (session_id, question_index) unique constraint, so every call
  /// simply reflects the latest known state for that question.
  Future<void> logQuestionEvent({
    required int questionIndex,
    required DateTime shownAt,
    DateTime? answeredAt,
    DateTime? lastModifiedAt,
    required int revisionCount,
    int backtrackCount = 0,
    int? selectedOptionIndex,
    String? answerText,
  }) async {
    final sessionId = HciMode.instance.currentSessionId;
    if (sessionId == null) return;

    try {
      await _db.from('hci_question_events').upsert(
        {
          'session_id': sessionId,
          'question_index': questionIndex,
          'shown_at': shownAt.toIso8601String(),
          'answered_at': answeredAt?.toIso8601String(),
          'last_modified_at': lastModifiedAt?.toIso8601String(),
          'revision_count': revisionCount,
          'backtrack_count': backtrackCount,
          'selected_option_index': selectedOptionIndex,
          'answer_text': answerText,
        },
        onConflict: 'session_id,question_index',
      );
    } catch (e) {
      debugPrint('HciStudyService.logQuestionEvent failed: $e');
    }
  }

  /// Marks the moment the quiz portion of the attempt finished (last
  /// question answered, before the SUS survey). Used to compute
  /// `quiz_duration_seconds` = quiz_finished_at − started_at.
  Future<void> markQuizFinished() async {
    final sessionId = HciMode.instance.currentSessionId;
    if (sessionId == null) return;

    try {
      await _db.from('hci_sessions').update({
        'quiz_finished_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);
    } catch (e) {
      debugPrint('HciStudyService.markQuizFinished failed: $e');
    }
  }

  /// Records the SUS survey result for the current session.
  /// `rawAnswers` should be the 10 raw 1–5 Likert responses, in question
  /// order, so the score is fully re-derivable/auditable later.
  Future<void> submitSus({
    required double susScore,
    required List<int> rawAnswers,
  }) async {
    final sessionId = HciMode.instance.currentSessionId;
    if (sessionId == null) return;

    try {
      await _db.from('hci_sessions').update({
        'sus_score': susScore,
        'sus_raw_answers': rawAnswers,
      }).eq('id', sessionId);
    } catch (e) {
      debugPrint('HciStudyService.submitSus failed: $e');
    }
  }

  /// Records the 1–5 "do these quests match my real life?" rating and
  /// marks the session complete. Always unlocks the HCI condition toggle
  /// afterwards (even if the write failed) — a logging hiccup should never
  /// leave the app stuck unable to start the next attempt.
  Future<void> submitQuestRating(int rating) async {
    final sessionId = HciMode.instance.currentSessionId;
    try {
      if (sessionId != null) {
        await _db.from('hci_sessions').update({
          'quest_rating': rating,
          'completed_at': DateTime.now().toIso8601String(),
        }).eq('id', sessionId);
      }
    } catch (e) {
      debugPrint('HciStudyService.submitQuestRating failed: $e');
    } finally {
      HciMode.instance.endSession();
    }
  }
}
