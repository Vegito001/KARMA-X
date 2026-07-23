// ─────────────────────────────────────────────────────────────────────────────
//  Student State — global singleton
//
//  Holds the student's current lifestyle snapshot (sleep, study hours,
//  screen time, stress) captured once during onboarding (on the cause
//  selection screen) and read later by StudentQuestScreen when it saves
//  a user_state row and builds the Gemini prompt.
//
//  Mirrors the pattern used by HciMode — a simple in-memory singleton so
//  we don't have to thread new constructor parameters through every
//  screen in the onboarding chain (Cause → Quiz → SusSurvey → Quest).
// ─────────────────────────────────────────────────────────────────────────────
class StudentState {
  StudentState._();
  static final StudentState instance = StudentState._();

  double sleepHours = 7;
  double studyHours = 4;
  double screenTimeHours = 5;
  int stressLevel = 3; // 1 (low) – 5 (high)
  double physicalActivityHours = 1;
  double socialHours = 2;
  double gpa = 3.0; // 0.0 – 4.0 scale
  String emotion = 'Neutral';

  /// Reset to defaults — call at the start of a fresh onboarding attempt
  /// if you want to avoid carrying over a previous session's values.
  void reset() {
    sleepHours = 7;
    studyHours = 4;
    screenTimeHours = 5;
    stressLevel = 3;
    physicalActivityHours = 1;
    socialHours = 2;
    gpa = 3.0;
    emotion = 'Neutral';
  }
}