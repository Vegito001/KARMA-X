import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/xp_bar.dart';
import '../widgets/quest_card.dart';
import '../widgets/scanline_overlay.dart';
import '../widgets/level_up_overlay.dart';
import '../widgets/avatar_display.dart';
import '../models/avatar.dart';
import '../models/avatar_composition.dart';
import '../models/user_avatar_progress.dart';
import '../services/avatar_service.dart';
import '../services/ai_service.dart';
// Countdown display is temporarily disabled (see TEMP comments in
// _buildQuestView) — this import is kept so it's a one-line change to
// bring it back later.
// ignore: unused_import
import '../widgets/countdown_chip.dart';
import 'profile_screen.dart';
import 'student_problem_screen.dart';
import 'student_quest_screen.dart' show GeneratedQuest;
import '../widgets/hci_condition_toggle.dart';
import '../utils/hci_mode.dart';

// Your app has no AuthGate/onAuthStateChange listener at the root (main.dart
// just does `home: const SplashScreen()`), so after logout we route back to
// the splash screen, which is the natural place to re-check auth state and
// send the user to login/onboarding.
import 'splash_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String playerName;
  final String goal;
  final String profession;
  // Optional: student quest overrides from AI generation
  final List<Map<String, dynamic>>? dailyQuestsOverride;
  final List<Map<String, dynamic>>? weeklyQuestsOverride;

  const DashboardScreen({
    super.key,
    required this.playerName,
    required this.goal,
    required this.profession,
    this.dailyQuestsOverride,
    this.weeklyQuestsOverride,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // All of these start at sensible fresh-player defaults and are
  // overwritten by the real values from Supabase (user_avatar_progress)
  // as soon as _loadAvatarData() resolves — see below. Previously XP
  // defaulted to a hardcoded 340 and level to a hardcoded 7 regardless of
  // the actual player.
  int _currentXP = 0;
  final int _maxXP = 200;
  int _level = 1;
  int _completedQuests = 0;
  bool _showLevelUp = false;
  int _selectedTab = 0;
  bool _loggingOut = false;

  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  // Avatar system state
  Avatar? _currentAvatar;
  UserAvatarProgress? _avatarProgress;
  bool _avatarLoading = true;
  AvatarAnimationState _avatarAnimationState = AvatarAnimationState.idle;

  // Computed stats — start every new player at 0; real values are restored
  // from Supabase (user_avatar_progress) in _loadAvatarData() once that
  // resolves, so progress follows the account rather than the device.
  final Map<String, int> _stats = {
    'health': 0,
    'knowledge': 0,
    'discipline': 0,
    'social': 0,
  };

  // Real streak + "ghost mode" (pre-6AM completion) tracking, all sourced
  // from Supabase (streak_count / last_active_date / ghost_mode_unlocked
  // on user_avatar_progress) rather than hardcoded or device-local values.
  int _streak = 0;
  bool _everCompletedBeforeSixAM = false;
  DateTime? _lastActiveDate;

  List<Map<String, dynamic>> _dailyQuests = [];
  List<Map<String, dynamic>> _weeklyQuests = [];
  // Whether the "Completed" sub-section is expanded, per quest type.
  // Collapsed by default so a busy day doesn't bury the active quests.
  bool _dailyCompletedExpanded = false;
  bool _weeklyCompletedExpanded = false;
  // True once a batch's countdown has hit zero — quests lock (no more
  // completing) and a small refresh button replaces the countdown chip.
  bool _dailyExpired = false;
  bool _weeklyExpired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Safety net: the dashboard is the "between attempts" home screen, so
    // if a previous quiz attempt was abandoned (closed without finishing
    // the SUS survey / quest rating) and left the toggle locked, free it
    // up again here. A genuinely in-progress attempt never reaches this
    // screen, so this can never unlock a session that's actually live.
    HciMode.instance.endSession();

    _headerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic));
    _headerCtrl.forward();

    // Apply AI-generated student quests if provided
    if (widget.dailyQuestsOverride != null) {
      _dailyQuests =
          List<Map<String, dynamic>>.from(widget.dailyQuestsOverride!);
    }
    if (widget.weeklyQuestsOverride != null) {
      _weeklyQuests =
          List<Map<String, dynamic>>.from(widget.weeklyQuestsOverride!);
    }

    // If we weren't handed fresh quests from the generation flow (e.g. a
    // returning user who just logged back in), pull whatever's already
    // saved for them in Supabase instead of leaving the lists empty.
    if (widget.dailyQuestsOverride == null &&
        widget.weeklyQuestsOverride == null) {
      _loadQuestsFromSupabase();
    }

    // Load avatar data — this also restores growth stats, XP, completed
    // quests, and streak from Supabase (see _loadAvatarData below), so
    // returning players see their real saved progress instead of defaults.
    _loadAvatarData();
  }

  // ── Load previously-generated, unexpired quests from Supabase ──────────
  Map<String, dynamic> _mapQuestRow(Map<String, dynamic> row) => {
        'id': row['id'],
        'title': row['title'] as String,
        'xp': (row['xp_reward'] ?? 10).toString(),
        'category': row['category'] as String,
        'completed': row['completed'] as bool? ?? false,
        'why': row['why'] as String?,
        'expires_at': row['expires_at'],
      };

  Future<void> _loadQuestsFromSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('quests')
          .select()
          .eq('user_id', user.id)
          .order('created_at');

      // _saveFreshQuests deletes the previous batch before inserting the
      // new one, but that delete silently no-ops if there's no DELETE RLS
      // policy on `quests` — so old, already-completed rows from earlier
      // refreshes can still be sitting in the table. Rather than trust the
      // delete to have worked, only keep the newest batch per quest_type
      // here. generation_id is NOT NULL on every row (FK to
      // ai_generations, always resolved/created before insert — see
      // _generateFreshQuests/_createGenerationRow), so it's an exact batch
      // id: every row from one refresh shares the same generation_id, and
      // no two refreshes ever share one. Group on that and keep only the
      // most recent generation per quest_type, which reliably filters out
      // stale rows regardless of what happened in the DB.
      final byType = <String, Map<String, List<Map<String, dynamic>>>>{
        'daily': {},
        'weekly': {},
      };
      // Track each generation's most recent created_at so we can pick the
      // newest generation even though rows within it may not be sorted.
      final generationCreatedAt = <String, String>{};
      for (final row in (rows as List<dynamic>)) {
        final map = row as Map<String, dynamic>;
        final type = map['quest_type'];
        if (type != 'daily' && type != 'weekly') continue;
        final batchKey = map['generation_id']?.toString() ?? '';
        byType[type]!.putIfAbsent(batchKey, () => []).add(map);
        final createdAt = map['created_at']?.toString() ?? '';
        final existing = generationCreatedAt[batchKey];
        if (existing == null || createdAt.compareTo(existing) > 0) {
          generationCreatedAt[batchKey] = createdAt;
        }
      }

      List<Map<String, dynamic>> latestBatch(String type) {
        final batches = byType[type]!;
        if (batches.isEmpty) return [];
        final latestKey = batches.keys.reduce((a, b) {
          final aTime = generationCreatedAt[a] ?? '';
          final bTime = generationCreatedAt[b] ?? '';
          return aTime.compareTo(bTime) >= 0 ? a : b;
        });
        return batches[latestKey]!.map(_mapQuestRow).toList();
      }

      final daily = latestBatch('daily');
      final weekly = latestBatch('weekly');

      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _dailyQuests = daily;
        _weeklyQuests = weekly;
        // Quests stay visible (locked) past expiry — the countdown chip
        // just gets swapped for a small "Refresh quests" button; nothing
        // regenerates automatically anymore.
        _dailyExpired = _questSetExpiry(daily)?.isBefore(now) ?? false;
        _weeklyExpired = _questSetExpiry(weekly)?.isBefore(now) ?? false;
      });
    } catch (e) {
      debugPrint('Error loading quests from Supabase: $e');
    }
  }

  // ── Quest refresh (daily & weekly, triggered manually by the user) ─────
  //
  // The countdown only counts down — it never regenerates anything on its
  // own. Once it hits zero, quests lock (see QuestCard's `enabled` flag)
  // and a small refresh button takes the countdown chip's place. Tapping
  // it goes through the exact same generation call onboarding uses —
  // AiService().generateQuests(), which itself routes to your Modal model
  // (or Gemini, depending on ModelMode) — using the problem/root-cause
  // + lifestyle context that produced the expiring batch. If that call
  // fails for any reason (network, API down, no prior context to work
  // from), it falls back to the same static fallback quest set onboarding
  // already uses when its own generation call fails — never a "just reset
  // completed on the old quests" shortcut.
  bool _refreshingDaily = false;
  bool _refreshingWeekly = false;
  // Set by _generateFreshQuests/_saveFreshQuests on failure, read and
  // cleared by _refreshQuestSet right after, to show a SnackBar instead of
  // failures only ever going to debugPrint (invisible outside a dev console).
  String? _lastRefreshError;

  Future<void> _refreshDailyQuests() => _refreshQuestSet(isWeekly: false);
  Future<void> _refreshWeeklyQuests() => _refreshQuestSet(isWeekly: true);

  Future<void> _refreshQuestSet({required bool isWeekly}) async {
    if (isWeekly ? _refreshingWeekly : _refreshingDaily) return;
    final current = isWeekly ? _weeklyQuests : _dailyQuests;
    if (current.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return; // can't attribute/save a regeneration

    _lastRefreshError = null;

    if (mounted) {
      setState(() {
        if (isWeekly) {
          _refreshingWeekly = true;
        } else {
          _refreshingDaily = true;
        }
      });
    }

    try {
      final now = DateTime.now();
      final newExpiry = isWeekly
          ? now.add(const Duration(days: 7))
          : DateTime(now.year, now.month, now.day + 1);

      final generated = await _generateFreshQuests(
        userId: user.id,
        currentQuests: current,
        isWeekly: isWeekly,
      );

      final newRows = await _saveFreshQuests(
        userId: user.id,
        quests: generated.quests,
        isWeekly: isWeekly,
        expiresAt: newExpiry,
        generationId: generated.generationId,
      );

      if (!mounted) {
        // The generation + save already completed and (barring a DB
        // error, which is separately recorded in _lastRefreshError) is
        // persisted in Supabase — so even though this specific widget
        // instance can no longer update itself, the next time the
        // dashboard loads it'll pick up the fresh quests from
        // _loadQuestsFromSupabase. See didChangeAppLifecycleState too,
        // which reloads on app resume for exactly this kind of long wait.
        debugPrint('Quest refresh finished after the dashboard was unmounted — '
            'saved to Supabase, will show next time it loads.');
        return;
      }
      setState(() {
        if (isWeekly) {
          _weeklyQuests = newRows;
          _weeklyExpired = false;
        } else {
          _dailyQuests = newRows;
          _dailyExpired = false;
        }
      });
    } catch (e) {
      debugPrint(
          'Error refreshing ${isWeekly ? 'weekly' : 'daily'} quests: $e');
      _lastRefreshError = 'Refreshing quests failed: '
          '${e.toString().replaceFirst('Exception: ', '')}';
    } finally {
      if (mounted) {
        setState(() {
          if (isWeekly) {
            _refreshingWeekly = false;
          } else {
            _refreshingDaily = false;
          }
        });
        if (_lastRefreshError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_lastRefreshError!),
              backgroundColor: AppTheme.bg700,
              duration: const Duration(seconds: 6),
            ),
          );
          _lastRefreshError = null;
        }
      } else {
        if (isWeekly) {
          _refreshingWeekly = false;
        } else {
          _refreshingDaily = false;
        }
      }
    }
  }

  /// Looks up the AI generation (and lifestyle snapshot) behind the
  /// expiring quests and asks for a new batch through the same
  /// AiService().generateQuests() call onboarding uses. On any failure,
  /// returns the same static fallback quests onboarding falls back to —
  /// so a "reset" always produces a real quest set, generated the same way.
  ///
  /// Also returns the generation_id it found (if any) so the caller can
  /// attach it to the new quest rows — without this, inserting a batch
  /// with no generation_id could silently fail against your schema (if
  /// that column is required) and previously showed nothing on screen
  /// with no error at all.
  Future<({List<GeneratedQuest> quests, dynamic generationId})>
      _generateFreshQuests({
    required String userId,
    required List<Map<String, dynamic>> currentQuests,
    required bool isWeekly,
  }) async {
    // Only used to look up CONTEXT (the problem/root-cause/lifestyle behind
    // the expiring batch) for the AI prompt below. Deliberately never
    // reused as the generation_id for the new rows we insert — doing that
    // used to make new quests share a generation_id with the old
    // (possibly-completed) batch they're replacing, which made the old
    // rows get grouped in as part of "the current batch" everywhere batch
    // identity is keyed off generation_id (dashboard load, cleanup
    // queries, etc). Every refresh now always gets its own fresh
    // generation_id — see the unconditional _createGenerationRow calls
    // below instead of the old `foundGenerationId ??= ...` pattern.
    dynamic contextGenerationId;
    try {
      final anyId = currentQuests
          .map((q) => q['id'])
          .firstWhere((id) => id != null, orElse: () => null);

      Map<String, dynamic>? generationRow;
      Map<String, dynamic>? stateRow;
      if (anyId != null) {
        final questRow = await Supabase.instance.client
            .from('quests')
            .select('generation_id')
            .eq('id', anyId)
            .maybeSingle();
        contextGenerationId = questRow?['generation_id'];
        if (contextGenerationId != null) {
          generationRow = await Supabase.instance.client
              .from('ai_generations')
              .select()
              .eq('id', contextGenerationId)
              .maybeSingle();
          final stateId = generationRow?['user_state_id'];
          if (stateId != null) {
            stateRow = await Supabase.instance.client
                .from('user_state')
                .select()
                .eq('id', stateId)
                .maybeSingle();
          }
        }
      }

      final parsed = await AiService().generateQuests(
        playerName: widget.playerName,
        schedule: widget.profession,
        problemTitle:
            generationRow?['primary_problem'] as String? ?? widget.goal,
        problemSubtitle: widget.goal,
        selectedCauses: [
          if (generationRow?['root_cause'] != null)
            generationRow!['root_cause'] as String,
        ],
        quizAnswers: const [],
        sleepHours: (stateRow?['sleep_hours'] as num?)?.toDouble() ?? 7.0,
        studyHours: (stateRow?['study_hours'] as num?)?.toDouble() ?? 4.0,
        screenTimeHours:
            (stateRow?['screen_time_hours'] as num?)?.toDouble() ?? 4.0,
        stressLevel: (stateRow?['stress_level'] as num?)?.toInt() ?? 3,
        physicalActivityHours:
            (stateRow?['physical_activity_hours'] as num?)?.toDouble() ?? 1.0,
        socialHours: (stateRow?['social_hours'] as num?)?.toDouble() ?? 2.0,
        gpa: (stateRow?['gpa'] as num?)?.toDouble() ?? 3.0,
        emotion: (stateRow?['emotion'] as String?) ?? 'neutral',
      );

      final raw =
          (isWeekly ? parsed['weekly'] : parsed['daily']) as List<dynamic>?;
      if (raw == null || raw.isEmpty) {
        throw Exception(
            'Empty ${isWeekly ? 'weekly' : 'daily'} quest list from API');
      }
      var quests = raw
          .map((e) => GeneratedQuest.fromJson(e as Map<String, dynamic>))
          .toList();

      // Safety net: guarantee discipline/health/knowledge/social are all
      // represented even if the model didn't spread categories evenly.
      quests = GeneratedQuest.ensureAllCategories(
        quests,
        fillerByCategory: isWeekly
            ? GeneratedQuest.weeklyFillerByCategory()
            : GeneratedQuest.dailyFillerByCategory(widget.goal),
      );

      // Always a NEW generation row for this new batch — never reattach to
      // contextGenerationId, or the new rows would share a batch identity
      // with the old (possibly-completed) quests they're replacing.
      final newGenerationId = await _createGenerationRow(
        userId: userId,
        primaryProblem: parsed['primary_problem'] as String? ?? widget.goal,
        rootCause: parsed['root_cause'] as String? ?? 'unknown',
        reasoning: parsed['reasoning'] as String? ??
            'Regenerated from the dashboard refresh button.',
      );

      return (quests: quests, generationId: newGenerationId);
    } catch (e) {
      debugPrint('Quest regeneration failed — using the same fallback quests '
          'onboarding uses when the API is unavailable: $e');
      _lastRefreshError =
          'Couldn\'t reach your model, so fallback quests were used '
          'instead. (${e.toString().replaceFirst('Exception: ', '')})';
      final quests = isWeekly
          ? GeneratedQuest.fallbackWeekly()
          : GeneratedQuest.fallbackDaily(widget.goal);

      // Same reasoning as above — a fresh generation_id for this batch,
      // never the old contextGenerationId.
      final newGenerationId = await _createGenerationRow(
        userId: userId,
        primaryProblem: widget.goal,
        rootCause: 'unknown',
        reasoning: 'Fallback quests — the model was unavailable when this '
            'batch was generated.',
      );

      return (quests: quests, generationId: newGenerationId);
    }
  }

  /// Creates a minimal user_state + ai_generations row pair, mirroring the
  /// shape onboarding writes in student_quest_screen.dart, and returns the
  /// new generation id. Called on every dashboard refresh (success or
  /// fallback) so each new batch gets its own generation_id, distinct from
  /// whatever batch it's replacing — see _generateFreshQuests above.
  Future<dynamic> _createGenerationRow({
    required String userId,
    required String primaryProblem,
    required String rootCause,
    required String reasoning,
  }) async {
    final stateRow = await Supabase.instance.client
        .from('user_state')
        .insert({
          'user_id': userId,
          'sleep_hours': 7.0,
          'study_hours': 4.0,
          'screen_time_hours': 4.0,
          'stress_level': 3,
          'physical_activity_hours': 1.0,
          'social_hours': 2.0,
          'gpa': 3.0,
          'emotion': 'neutral',
          'source': 'dashboard_refresh',
        })
        .select()
        .single();

    final generationRow = await Supabase.instance.client
        .from('ai_generations')
        .insert({
          'user_id': userId,
          'user_state_id': stateRow['id'],
          'primary_problem': primaryProblem,
          'root_cause': rootCause,
          'reasoning': reasoning,
          'model_version': AiService.lastSource,
        })
        .select()
        .single();

    return generationRow['id'];
  }

  /// Inserts a freshly generated batch into Supabase — exactly like the
  /// insert onboarding does after generation — and returns the
  /// dashboard-shaped rows (with real ids) ready to drop into state. If the
  /// insert itself fails (e.g. offline, or a schema constraint like a
  /// required generation_id), the quests are still shown locally without
  /// ids rather than silently discarded, and the failure is recorded in
  /// _lastRefreshError so the caller can surface it instead of it going
  /// completely unnoticed.
  Future<List<Map<String, dynamic>>> _saveFreshQuests({
    required String userId,
    required List<GeneratedQuest> quests,
    required bool isWeekly,
    required DateTime expiresAt,
    dynamic generationId,
  }) async {
    final rowsToInsert = quests
        .map((q) => {
              'user_id': userId,
              if (generationId != null) 'generation_id': generationId,
              'title': q.title,
              'xp_reward': int.tryParse(q.xp) ?? 10,
              'category': q.category,
              'why': q.why,
              'quest_type': isWeekly ? 'weekly' : 'daily',
              'completed': false,
              'expires_at': expiresAt.toUtc().toIso8601String(),
            })
        .toList();

    try {
      // Clear out the old batch of this type first, so the table only
      // ever holds one active daily batch and one active weekly batch per
      // user instead of accumulating every past refresh.
      await Supabase.instance.client
          .from('quests')
          .delete()
          .eq('user_id', userId)
          .eq('quest_type', isWeekly ? 'weekly' : 'daily');

      final inserted = await Supabase.instance.client
          .from('quests')
          .insert(rowsToInsert)
          .select();
      return List<Map<String, dynamic>>.from(inserted)
          .map(_mapQuestRow)
          .toList();
    } catch (e) {
      debugPrint('Failed to save regenerated quests (showing locally): $e');
      _lastRefreshError =
          'Generated new quests, but saving them failed, so they\'re only '
          'showing on this screen for now. (${e.toString().replaceFirst('Exception: ', '')})';
      return quests
          .map((q) => {
                'id': null,
                'title': q.title,
                'xp': q.xp,
                'category': q.category,
                'completed': false,
                'why': q.why,
                'expires_at': expiresAt.toUtc().toIso8601String(),
              })
          .toList();
    }
  }

  DateTime? _questSetExpiry(List<Map<String, dynamic>> quests) {
    DateTime? earliest;
    for (final q in quests) {
      final raw = q['expires_at'];
      DateTime? dt;
      if (raw is DateTime) {
        dt = raw;
      } else if (raw is String) {
        dt = DateTime.tryParse(raw);
      }
      if (dt == null) continue;
      if (earliest == null || dt.isBefore(earliest)) earliest = dt;
    }
    return earliest;
  }

  Future<void> _loadAvatarData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final progress = await AvatarService().getUserAvatarProgress(user.id);
        if (progress != null && mounted) {
          final avatar = await AvatarService().getAvatarById(
            progress.selectedAvatarId,
          );
          setState(() {
            _avatarProgress = progress;
            _currentAvatar = avatar;
            _avatarLoading = false;
            // The database is the source of truth for all of this — a
            // returning player should see their real saved progress, not
            // whatever these fields happened to default to on this device.
            _level = progress.currentLevel;
            _currentXP = progress.currentXp;
            _completedQuests = progress.completedQuests;
            _stats
              ..clear()
              ..addAll(progress.stats);
            _streak = progress.streakCount;
            _everCompletedBeforeSixAM = progress.ghostModeUnlocked;
            _lastActiveDate = progress.lastActiveDate;
          });
        } else {
          if (mounted) {
            setState(() => _avatarLoading = false);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading avatar data: $e');
      if (mounted) {
        setState(() => _avatarLoading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headerCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A Modal generation can take up to ~7 minutes, easily longer than the
    // app can stay foregrounded/unbackgrounded on some devices. If that
    // happens mid-refresh, the in-flight request finishes and saves fine,
    // but this widget instance might have missed the moment to update
    // itself. Reloading on resume picks up whatever's actually in
    // Supabase, so a completed refresh is never stuck invisible.
    if (state == AppLifecycleState.resumed && mounted) {
      _loadQuestsFromSupabase();
    }
  }

  void _onQuestComplete(Map<String, dynamic> quest, {required bool isWeekly}) {
    if (quest['completed'] == true) return; // already done, ignore double-taps

    final xp = int.tryParse(quest['xp'] as String? ?? '0') ?? 0;
    final category = quest['category'] as String? ?? '';
    var leveledUp = false;

    setState(() {
      quest['completed'] = true;

      _currentXP += xp;
      _completedQuests++;

      // Bump the stat matching the quest's category (health, knowledge,
      // discipline, social), clamped to 100 so it can't run away.
      final key = category.toLowerCase();
      if (_stats.containsKey(key)) {
        _stats[key] = ((_stats[key] ?? 0) + 5).clamp(0, 100).toInt();
      }

      if (_currentXP >= _maxXP) {
        _currentXP = _currentXP - _maxXP;
        _level++;
        _showLevelUp = true;
        _avatarAnimationState = AvatarAnimationState.levelUp;
        leveledUp = true;
      } else {
        _avatarAnimationState = AvatarAnimationState.acting;
        leveledUp = false;
      }
    });

    // Persist completion so it survives logout/login. Quests that arrived
    // via the AI-generation hand-off may not carry a Supabase row id yet
    // (the insert happens before the id is threaded back), so guard for null.
    final questId = quest['id'];
    if (questId != null) {
      Supabase.instance.client
          .from('quests')
          .update({'completed': true})
          .eq('id', questId)
          .then((_) {},
              onError: (e) => debugPrint('Error saving quest completion: $e'));
    }

    // Persist level, XP, quest count, stats, and streak/ghost-mode data
    // together in one Supabase write. Streak only advances for daily
    // quests — see the isWeekly check inside _persistProgress.
    _persistProgress(isWeekly: isWeekly);

    Future.delayed(Duration(milliseconds: leveledUp ? 1800 : 700), () {
      if (mounted && !_showLevelUp) {
        setState(() => _avatarAnimationState = AvatarAnimationState.idle);
      }
    });
  }

  Future<void> _persistProgress({required bool isWeekly}) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Streak is a daily-habit metric — only a completed *daily* quest
      // should move it. Completing a weekly quest still saves XP/level/
      // stats as normal, it just leaves streak/last-active-date alone.
      var streak = _streak;
      var ghostMode = _everCompletedBeforeSixAM;
      var lastActive = _lastActiveDate;

      if (!isWeekly) {
        // Work out the new streak from the last known active date. Same
        // calendar day → unchanged. Exactly one day later → +1. Anything
        // longer than that → the streak was broken, restart at 1.
        final now = DateTime.now();
        if (_lastActiveDate == null) {
          streak = 1;
        } else {
          final daysSince = DateTime(now.year, now.month, now.day)
              .difference(DateTime(_lastActiveDate!.year,
                  _lastActiveDate!.month, _lastActiveDate!.day))
              .inDays;
          if (daysSince == 1) {
            streak += 1;
          } else if (daysSince > 1) {
            streak = 1;
          }
          // daysSince == 0 (same day): streak stays as-is.
        }

        ghostMode = _everCompletedBeforeSixAM || now.hour < 6;
        lastActive = now;

        if (mounted) {
          setState(() {
            _streak = streak;
            _everCompletedBeforeSixAM = ghostMode;
            _lastActiveDate = lastActive;
          });
        } else {
          _streak = streak;
          _everCompletedBeforeSixAM = ghostMode;
          _lastActiveDate = lastActive;
        }
      }

      await AvatarService().saveProgressSnapshot(
        user.id,
        level: _level,
        currentXp: _currentXP,
        completedQuests: _completedQuests,
        stats: _stats,
        streak: streak,
        lastActiveDate: lastActive ?? DateTime.now(),
        ghostModeUnlocked: ghostMode,
      );

      // Check for new badges based on the just-saved level/quest count.
      final newBadges = AvatarService().checkBadgesUnlocked(
        _level,
        _completedQuests,
      );
      await AvatarService().updateBadges(user.id, newBadges);

      // Reload avatar progress (avatar image/badges may have changed).
      await _loadAvatarData();
    } catch (e) {
      debugPrint('Error persisting progress: $e');
    }
  }

  // ── Logout ───────────────────────────────────────────────────────────────
  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bg800,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppTheme.borderDim),
        ),
        title: Text(
          'Log out?',
          style: AppTheme.uiFont(
            size: 16,
            weight: FontWeight.w800,
            color: AppTheme.text100,
          ),
        ),
        content: Text(
          'You can log back in anytime with your account.',
          style: AppTheme.uiFont(size: 13, color: AppTheme.text400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppTheme.uiFont(size: 13, color: AppTheme.text400)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Log out',
                style: AppTheme.uiFont(
                  size: 13,
                  weight: FontWeight.w800,
                  color: AppTheme.copper,
                )),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Error signing out: $e');
    }

    if (!mounted) return;
    setState(() => _loggingOut = false);

    // No AuthGate in this app, so we explicitly send the user back to
    // SplashScreen and wipe the entire nav stack behind it (dashboard,
    // any quest/profile screens, etc.) so the back button can't return
    // to authenticated screens after logout.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  // ── Avatar stats popup ──────────────────────────────────────────────────
  void _showAvatarStatsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.only(top: 60),
          decoration: BoxDecoration(
            color: AppTheme.bg800,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: AppTheme.borderDim),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Drag handle
                  Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppTheme.borderDim,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Avatar
                  _avatarLoading ||
                          _currentAvatar == null ||
                          _avatarProgress == null
                      ? Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderDim),
                            color: AppTheme.bg700,
                          ),
                          child: Center(
                            child: Text(
                              widget.playerName.isNotEmpty
                                  ? widget.playerName[0]
                                  : 'P',
                              style: AppTheme.displayFont(
                                size: 32,
                                color: AppTheme.text100,
                              ),
                            ),
                          ),
                        )
                      : AvatarDisplay(
                          avatar: _currentAvatar!,
                          progress: _avatarProgress!,
                          size: 96,
                          showBadges: true,
                          animationState: AvatarAnimationState.idle,
                        ),

                  const SizedBox(height: 14),
                  Text(
                    widget.playerName.isEmpty ? 'Player' : widget.playerName,
                    style:
                        AppTheme.displayFont(size: 18, color: AppTheme.text100),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Level $_level  |  ${widget.profession}',
                    style: AppTheme.uiFont(size: 12, color: AppTheme.text400),
                  ),
                  const SizedBox(height: 18),

                  XpBar(
                    current: _currentXP.toDouble(),
                    max: _maxXP.toDouble(),
                    label: 'Karma progress',
                  ),
                  const SizedBox(height: 20),

                  // Growth stats
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration:
                        AppTheme.baseCard(borderColor: AppTheme.borderDim),
                    child: Column(
                      children: [
                        StatBar(
                          statName: 'Health',
                          emoji: '🏃',
                          value: (_stats['health'] ?? 0).toDouble(),
                          delay: Duration.zero,
                        ),
                        StatBar(
                          statName: 'Knowledge',
                          emoji: '📚',
                          value: (_stats['knowledge'] ?? 0).toDouble(),
                          delay: Duration.zero,
                        ),
                        StatBar(
                          statName: 'Discipline',
                          emoji: '⚡',
                          value: (_stats['discipline'] ?? 0).toDouble(),
                          delay: Duration.zero,
                        ),
                        StatBar(
                          statName: 'Social',
                          emoji: '🧍',
                          value: (_stats['social'] ?? 0).toDouble(),
                          delay: Duration.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Full profile button
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            playerName: widget.playerName,
                            level: _level,
                            completedQuests: _completedQuests,
                            stats: Map<String, int>.from(_stats),
                            streak: _streak,
                            everCompletedBeforeSixAM: _everCompletedBeforeSixAM,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.copper,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'VIEW FULL PROFILE  ›',
                        textAlign: TextAlign.center,
                        style: AppTheme.displayFont(
                            size: 13, color: AppTheme.bg900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg900,
      body: Container(
        decoration: AppTheme.scaffoldBackground(),
        child: Stack(
          children: [
            Column(
              children: [
                // ── TOP HEADER ──
                _buildHeader(),
                // ── TABS ──
                _buildTabs(),
                // ── CONTENT ──
                Expanded(
                  child:
                      _selectedTab == 0 ? _buildQuestView() : _buildStatsView(),
                ),
              ],
            ),
            // ── BOTTOM NAV ──
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
            const IgnorePointer(
              child: Opacity(
                opacity: 0.14,
                child: ScanlineOverlay(child: SizedBox.expand()),
              ),
            ),
            // ── LEVEL UP OVERLAY ──
            if (_showLevelUp)
              LevelUpOverlay(
                newLevel: _level,
                avatar: _currentAvatar,
                progress: _avatarProgress?.copyWith(currentLevel: _level),
                onDismiss: () => setState(() {
                  _showLevelUp = false;
                  _avatarAnimationState = AvatarAnimationState.idle;
                }),
              ),
            // ── LOGOUT LOADING VEIL ──
            if (_loggingOut)
              Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.mana),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _headerFade,
      child: SlideTransition(
        position: _headerSlide,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.of(context).padding.top + 14,
            20,
            18,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF111936), Color(0xFF090B1D)],
            ),
            border: const Border(
              bottom: BorderSide(color: AppTheme.borderDim, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back,',
                        style: AppTheme.uiFont(
                          size: 13,
                          color: AppTheme.text400,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.playerName.isEmpty
                            ? 'Player'
                            : widget.playerName,
                        style: AppTheme.uiFont(
                          size: 24,
                          weight: FontWeight.w800,
                          color: AppTheme.text100,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'Level $_level  |  ${widget.profession}',
                        style: AppTheme.uiFont(
                          size: 12,
                          color: AppTheme.text200,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: _showAvatarStatsSheet,
                        child: _avatarLoading ||
                                _currentAvatar == null ||
                                _avatarProgress == null
                            ? Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.borderDim),
                                  color: AppTheme.bg700,
                                ),
                                child: Center(
                                  child: Text(
                                    widget.playerName.isNotEmpty
                                        ? widget.playerName[0]
                                        : 'P',
                                    style: AppTheme.displayFont(
                                      size: 18,
                                      color: AppTheme.text100,
                                    ),
                                  ),
                                ),
                              )
                            : AvatarDisplay(
                                avatar: _currentAvatar!,
                                progress: _avatarProgress!,
                                size: 44,
                                showBadges: false,
                                animationState: _avatarAnimationState,
                              ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _handleLogout,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.bg700.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.borderDim),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: AppTheme.text200,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildGoalCard(),
              const SizedBox(height: 16),
              XpBar(
                current: _currentXP.toDouble(),
                max: _maxXP.toDouble(),
                label: 'Karma progress',
              ),
              const SizedBox(height: 14),
              _buildHciToggle(),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your steady path',
                    style: AppTheme.uiFont(
                      size: 11,
                      color: AppTheme.text400,
                    ),
                  ),
                  Text(
                    '$_completedQuests quests done',
                    style: AppTheme.uiFont(
                      size: 11,
                      color: AppTheme.text400,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg800.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderDim),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.mana.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.flag_rounded,
              color: AppTheme.mana,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Main goal',
                  style: AppTheme.uiFont(size: 11, color: AppTheme.text400),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.goal,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.uiFont(
                    size: 15,
                    weight: FontWeight.w700,
                    color: AppTheme.text100,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    final tabs = ['Today', 'Growth'];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppTheme.bg900.withValues(alpha: 0.4),
        border: const Border(
          bottom: BorderSide(color: AppTheme.borderDim, width: 1),
        ),
      ),
      child: Row(
        children: tabs.asMap().entries.map((e) {
          final sel = e.key == _selectedTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: EdgeInsets.only(
                  right: e.key == tabs.length - 1 ? 0 : 8,
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: sel
                      ? AppTheme.mana.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel
                        ? AppTheme.mana.withValues(alpha: 0.48)
                        : AppTheme.borderDim,
                  ),
                ),
                child: Text(
                  e.value,
                  textAlign: TextAlign.center,
                  style: AppTheme.uiFont(
                    size: 13,
                    weight: sel ? FontWeight.w800 : FontWeight.w600,
                    color: sel ? AppTheme.text100 : AppTheme.text400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuestView() {
    if (_dailyQuests.isEmpty && _weeklyQuests.isEmpty) {
      return _buildEmptyQuestState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 108),
      children: [
        // ── DAILY QUESTS ──
        _sectionTitle(
          title: 'Today',
          subtitle: _refreshingDaily
              ? 'Generating new quests — this can take up to ~7 minutes '
                  'on a cold start, please wait.'
              : 'Small wins that keep the bigger goal moving.',
          trailing: _dailyQuests.isEmpty
              ? null
              : (_dailyExpired
                  ? _refreshButton(isWeekly: false, color: AppTheme.mana)
                  : CountdownChip(
                      target: _questSetExpiry(_dailyQuests) ?? DateTime.now(),
                      color: AppTheme.mana,
                      onExpire: () {
                        if (!mounted) return;
                        setState(() => _dailyExpired = true);
                      },
                    )),
        ),
        const SizedBox(height: 12),
        if (_dailyQuests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('No daily quests yet.',
                style: AppTheme.monoFont(size: 12, color: AppTheme.text600)),
          )
        else
          ..._buildQuestSection(_dailyQuests, isWeekly: false),
        const SizedBox(height: 24),
        // ── WEEKLY QUESTS ──
        _sectionTitle(
          title: 'This week',
          subtitle: _refreshingWeekly
              ? 'Generating new quests — this can take up to ~7 minutes '
                  'on a cold start, please wait.'
              : 'Larger pushes for when you have breathing room.',
          trailing: _weeklyQuests.isEmpty
              ? null
              : (_weeklyExpired
                  ? _refreshButton(isWeekly: true, color: AppTheme.xpBlue)
                  : CountdownChip(
                      target: _questSetExpiry(_weeklyQuests) ?? DateTime.now(),
                      color: AppTheme.xpBlue,
                      onExpire: () {
                        if (!mounted) return;
                        setState(() => _weeklyExpired = true);
                      },
                    )),
        ),
        const SizedBox(height: 12),
        if (_weeklyQuests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('No weekly quests yet.',
                style: AppTheme.monoFont(size: 12, color: AppTheme.text600)),
          )
        else
          ..._buildQuestSection(_weeklyQuests, isWeekly: true),
      ],
    );
  }

  /// Renders a quest list split into active cards up top and a collapsible
  /// "Completed" sub-section below, instead of interleaving done quests
  /// (struck-through) among the ones still to do.
  List<Widget> _buildQuestSection(
    List<Map<String, dynamic>> quests, {
    required bool isWeekly,
  }) {
    final active = quests.where((q) => q['completed'] != true).toList();
    final completed = quests.where((q) => q['completed'] == true).toList();
    final expanded =
        isWeekly ? _weeklyCompletedExpanded : _dailyCompletedExpanded;

    Widget buildCard(Map<String, dynamic> q, int index) {
      return QuestCard(
        // Without a stable key, Flutter matches widgets to state by list
        // position — so when a quest moves out of the active list (into
        // Completed) and something else slides into that same slot, the
        // new occupant could inherit the old widget's leftover
        // _localCompleted=true state and render as done when it isn't.
        // Falling back to title+category only matters for quests that
        // somehow have no id (e.g. an insert failed) so two quests never
        // collide on the same key.
        key: ValueKey(q['id'] ?? '${q['title']}_${q['category']}'),
        title: q['title'] as String,
        xpReward: q['xp'] as String,
        category: q['category'] as String,
        completed: q['completed'] as bool,
        index: index,
        description: q['why'] as String?,
        onComplete: () => _onQuestComplete(q, isWeekly: isWeekly),
      );
    }

    final widgets = <Widget>[
      ...active.asMap().entries.map((e) => buildCard(e.value, e.key)),
    ];

    if (active.isEmpty && completed.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'All done for now — nice work.',
            style: AppTheme.monoFont(size: 12, color: AppTheme.text600),
          ),
        ),
      );
    }

    if (completed.isNotEmpty) {
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        GestureDetector(
          onTap: () => setState(() {
            if (isWeekly) {
              _weeklyCompletedExpanded = !_weeklyCompletedExpanded;
            } else {
              _dailyCompletedExpanded = !_dailyCompletedExpanded;
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: AppTheme.text400,
                ),
                const SizedBox(width: 4),
                Text(
                  'Completed (${completed.length})',
                  style: AppTheme.monoFont(size: 12, color: AppTheme.text400),
                ),
              ],
            ),
          ),
        ),
      );
      if (expanded) {
        widgets.addAll(
          completed
              .asMap()
              .entries
              .map((e) => buildCard(e.value, active.length + e.key)),
        );
      }
    }

    return widgets;
  }

  /// Small tappable "refresh" pill shown in place of the countdown chip
  /// once a batch expires — taps trigger the same generateQuests() call
  /// onboarding uses (see _generateFreshQuests below).
  Widget _refreshButton({required bool isWeekly, required Color color}) {
    final generating = isWeekly ? _refreshingWeekly : _refreshingDaily;
    return GestureDetector(
      onTap: generating
          ? null
          : () => isWeekly ? _refreshWeeklyQuests() : _refreshDailyQuests(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: generating ? 0.06 : 0.14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (generating)
              SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            else
              Icon(Icons.refresh, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              generating ? 'Generating…' : 'Refresh quests',
              style: AppTheme.monoFont(size: 10, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // ── HCI Study Mode toggle ─────────────────────────────────────────────────
  Widget _buildHciToggle() => const HciConditionToggle();

  // ── Empty quest state ───────────────────────────────────────────────────────
  Widget _buildEmptyQuestState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('⚔', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 20),
            Text('NO ACTIVE QUESTS',
                style: AppTheme.displayFont(size: 18, color: AppTheme.mana)),
            const SizedBox(height: 10),
            Text(
              'Type your problem to generate\npersonalised quests with AI.',
              textAlign: TextAlign.center,
              style: AppTheme.monoFont(size: 13, color: AppTheme.text400),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => StudentProblemScreen(
                  playerName: widget.playerName,
                  schedule: widget.profession,
                ),
              )),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.copper,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.copper.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text('START HERE  ›',
                    style:
                        AppTheme.displayFont(size: 13, color: AppTheme.bg900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    final textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.uiFont(
            size: 18,
            weight: FontWeight.w800,
            color: AppTheme.text100,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTheme.uiFont(
            size: 12,
            color: AppTheme.text400,
            height: 1.35,
          ),
        ),
      ],
    );

    if (trailing == null) return textColumn;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: textColumn),
        const SizedBox(width: 10),
        trailing,
      ],
    );
  }

  Widget _buildStatsView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 108),
      children: [
        _sectionTitle(
          title: 'Growth areas',
          subtitle: 'A simple read on where your effort has been landing.',
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.baseCard(borderColor: AppTheme.borderDim),
          child: Column(
            children: [
              StatBar(
                statName: 'Health',
                emoji: '🏃',
                value: (_stats['health'] ?? 0).toDouble(),
                delay: const Duration(milliseconds: 100),
              ),
              StatBar(
                statName: 'Knowledge',
                emoji: '📚',
                value: (_stats['knowledge'] ?? 0).toDouble(),
                delay: const Duration(milliseconds: 200),
              ),
              StatBar(
                statName: 'Discipline',
                emoji: '⚡',
                value: (_stats['discipline'] ?? 0).toDouble(),
                delay: const Duration(milliseconds: 300),
              ),
              StatBar(
                statName: 'Social',
                emoji: '🧍',
                value: (_stats['social'] ?? 0).toDouble(),
                delay: const Duration(milliseconds: 400),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle(
          title: 'Progress notes',
          subtitle: 'Numbers that make the streak feel real.',
        ),
        const SizedBox(height: 12),
        ...[
          {'label': 'Quests Completed', 'value': '$_completedQuests'},
          {'label': 'Current Level', 'value': 'LVL $_level'},
          {'label': 'Total XP', 'value': '${(_level - 1) * 500 + _currentXP}'},
          {
            'label': 'Streak',
            'value': _streak == 1 ? '1 DAY' : '$_streak DAYS'
          },
        ].map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: AppTheme.baseCard(borderColor: AppTheme.borderDim),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item['label']!,
                  style: AppTheme.uiFont(size: 13, color: AppTheme.text200),
                ),
                Text(
                  item['value']!,
                  style: AppTheme.uiFont(
                    size: 14,
                    weight: FontWeight.w800,
                    color: AppTheme.text100,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        top: 8,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bg900.withValues(alpha: 0.94),
        border: const Border(
          top: BorderSide(color: AppTheme.borderDim, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.check_circle_outline_rounded, 'Today', 0),
          _navItem(Icons.trending_up_rounded, 'Growth', 1),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final sel = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.bg700.withValues(alpha: 0.78) : null,
          border: sel ? Border.all(color: AppTheme.borderDim) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: sel ? AppTheme.mana : AppTheme.text400,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.uiFont(
                size: 10,
                weight: FontWeight.w700,
                color: sel ? AppTheme.text100 : AppTheme.text400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
