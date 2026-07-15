import 'dart:math';
import 'package:uuid/uuid.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  HCI Study Mode — global singleton
//  Condition A = baseline (current UI)
//  Condition B = Gestalt redesign
//
//  Two independent concepts:
//
//   1. `lockCondition` — sticky manual override. When a person manually
//      flips the toggle (demo/testing), this is set so the NEXT
//      `startNewSession()` doesn't immediately overwrite their choice with
//      a random draw. Real study participants never touch the toggle, so
//      this stays false for them and every attempt is randomized.
//
//   2. `sessionActive` — hard lock for data integrity. From the moment
//      `startNewSession()` fires (participant lands on the quiz) until
//      `endSession()` fires (SUS + quest rating both logged), the toggle
//      is INERT — tapping it does nothing. This is what stops someone
//      switching conditions mid-attempt and producing a session that
//      belongs to neither A nor B. See `toggle()`.
// ─────────────────────────────────────────────────────────────────────────────
class HciMode {
  HciMode._();
  static final HciMode instance = HciMode._();

  final Random _random = Random();
  final Uuid _uuid = const Uuid();

  /// true  → Condition B (Gestalt)
  /// false → Condition A (baseline)
  bool useGestalt = false;

  /// When true, `startNewSession()` will not randomize `useGestalt` —
  /// it keeps whatever was last set (e.g. via the manual demo toggle).
  bool lockCondition = false;

  /// True from `startNewSession()` until `endSession()`. While true,
  /// `toggle()` is a no-op — the condition cannot change mid-attempt.
  bool sessionActive = false;

  /// Id of the current quiz attempt. Null until `startNewSession()` has
  /// been called at least once (i.e. before the very first quiz screen
  /// visit in this app run).
  String? currentSessionId;

  DateTime? sessionStartedAt;

  /// Manual dev/demo toggle. Returns true if the flip actually happened,
  /// false if it was ignored because a session is currently locked — the
  /// UI can use the return value to show a "locked" cue if it wants.
  bool toggle() {
    if (sessionActive) return false;
    useGestalt = !useGestalt;
    lockCondition = true;
    return true;
  }

  /// Call this once per quiz attempt (StudentQuizScreen.initState).
  /// Randomly assigns A/B (unless locked) and starts a fresh session id,
  /// then locks the toggle for the duration of the attempt.
  void startNewSession() {
    if (!lockCondition) {
      useGestalt = _random.nextBool();
    }
    currentSessionId = _uuid.v4();
    sessionStartedAt = DateTime.now();
    sessionActive = true;
  }

  /// Call this once the attempt's data is fully logged (SUS score AND
  /// quest rating both saved). Unlocks the toggle for the next attempt.
  void endSession() {
    sessionActive = false;
  }

  /// 'A' or 'B', matching the `condition` column in `hci_sessions`.
  String get conditionLabel => useGestalt ? 'B' : 'A';
}
