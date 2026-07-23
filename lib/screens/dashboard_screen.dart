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
    with SingleTickerProviderStateMixin {
  // All of these start at sensible fresh-player defaults and are
  // overwritten by the real values from Supabase (user_avatar_progress)
  // as soon as _loadAvatarData() resolves — see below. Previously XP
  // defaulted to a hardcoded 340 and level to a hardcoded 7 regardless of
  // the actual player.
  int _currentXP = 0;
  final int _maxXP = 500;
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

  @override
  void initState() {
    super.initState();

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
      // Pull everything (not just unexpired rows) so we can tell the
      // difference between "no quests were ever generated" and "the last
      // batch expired while the app was closed" — the latter should
      // trigger an immediate refresh instead of showing an empty state.
      final rows = await Supabase.instance.client
          .from('quests')
          .select()
          .eq('user_id', user.id)
          .order('created_at');

      final daily = <Map<String, dynamic>>[];
      final weekly = <Map<String, dynamic>>[];
      final now = DateTime.now();
      var sawDaily = false;
      var sawWeekly = false;
      var dailyAllExpired = true;
      var weeklyAllExpired = true;

      for (final row in (rows as List<dynamic>)) {
        final map = row as Map<String, dynamic>;
        final expiresAt = DateTime.tryParse(map['expires_at']?.toString() ?? '');
        final expired = expiresAt != null && expiresAt.isBefore(now);

        if (map['quest_type'] == 'daily') {
          sawDaily = true;
          if (!expired) {
            daily.add(_mapQuestRow(map));
            dailyAllExpired = false;
          }
        } else if (map['quest_type'] == 'weekly') {
          sawWeekly = true;
          if (!expired) {
            weekly.add(_mapQuestRow(map));
            weeklyAllExpired = false;
          }
        }
      }

      if (mounted) {
        setState(() {
          _dailyQuests = daily;
          _weeklyQuests = weekly;
        });
      }

      // If the whole batch expired while the app was closed, refresh right
      // away rather than waiting for the on-screen countdown to reach zero.
      if (sawDaily && dailyAllExpired) _refreshDailyQuests();
      if (sawWeekly && weeklyAllExpired) _refreshWeeklyQuests();
    } catch (e) {
      debugPrint('Error loading quests from Supabase: $e');
    }
  }

  // ── Quest refresh (daily every 24h, weekly every 7d) ────────────────────
  //
  // "Reset" always goes through the exact same generation call onboarding
  // uses — AiService().generateQuests(), which itself routes to your Modal
  // model (or Gemini, depending on ModelMode) — using the problem/root-cause
  // + lifestyle context that produced the expiring batch. If that call
  // fails for any reason (network, API down, no prior context to work
  // from), it falls back to the same static fallback quest set onboarding
  // already uses when its own generation call fails — never a "just reset
  // completed on the old quests" shortcut.
  bool _refreshingDaily = false;
  bool _refreshingWeekly = false;

  Future<void> _refreshDailyQuests() => _refreshQuestSet(isWeekly: false);
  Future<void> _refreshWeeklyQuests() => _refreshQuestSet(isWeekly: true);

  Future<void> _refreshQuestSet({required bool isWeekly}) async {
    if (isWeekly ? _refreshingWeekly : _refreshingDaily) return;
    final current = isWeekly ? _weeklyQuests : _dailyQuests;
    if (current.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return; // can't attribute/save a regeneration

    if (isWeekly) {
      _refreshingWeekly = true;
    } else {
      _refreshingDaily = true;
    }

    try {
      final now = DateTime.now();
      final newExpiry = isWeekly
          ? now.add(const Duration(days: 7))
          : DateTime(now.year, now.month, now.day + 1);

      final freshQuests = await _generateFreshQuests(
        userId: user.id,
        currentQuests: current,
        isWeekly: isWeekly,
      );

      final newRows = await _saveFreshQuests(
        userId: user.id,
        quests: freshQuests,
        isWeekly: isWeekly,
        expiresAt: newExpiry,
      );

      if (!mounted) return;
      setState(() {
        if (isWeekly) {
          _weeklyQuests = newRows;
        } else {
          _dailyQuests = newRows;
        }
      });
    } catch (e) {
      debugPrint('Error refreshing ${isWeekly ? 'weekly' : 'daily'} quests: $e');
    } finally {
      if (isWeekly) {
        _refreshingWeekly = false;
      } else {
        _refreshingDaily = false;
      }
    }
  }

  /// Looks up the AI generation (and lifestyle snapshot) behind the
  /// expiring quests and asks for a new batch through the same
  /// AiService().generateQuests() call onboarding uses. On any failure,
  /// returns the same static fallback quests onboarding falls back to —
  /// so a "reset" always produces a real quest set, generated the same way.
  Future<List<GeneratedQuest>> _generateFreshQuests({
    required String userId,
    required List<Map<String, dynamic>> currentQuests,
    required bool isWeekly,
  }) async {
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
        final generationId = questRow?['generation_id'];
        if (generationId != null) {
          generationRow = await Supabase.instance.client
              .from('ai_generations')
              .select()
              .eq('id', generationId)
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

      final raw = (isWeekly ? parsed['weekly'] : parsed['daily'])
          as List<dynamic>?;
      if (raw == null || raw.isEmpty) {
        throw Exception(
            'Empty ${isWeekly ? 'weekly' : 'daily'} quest list from API');
      }
      return raw
          .map((e) => GeneratedQuest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(
          'Quest regeneration failed — using the same fallback quests '
          'onboarding uses when the API is unavailable: $e');
      return isWeekly
          ? GeneratedQuest.fallbackWeekly()
          : GeneratedQuest.fallbackDaily(widget.goal);
    }
  }

  /// Inserts a freshly generated batch into Supabase — exactly like the
  /// insert onboarding does after generation — and returns the
  /// dashboard-shaped rows (with real ids) ready to drop into state. If the
  /// insert itself fails (e.g. offline), the quests are still shown locally
  /// without ids rather than silently discarded.
  Future<List<Map<String, dynamic>>> _saveFreshQuests({
    required String userId,
    required List<GeneratedQuest> quests,
    required bool isWeekly,
    required DateTime expiresAt,
  }) async {
    final rowsToInsert = quests
        .map((q) => {
              'user_id': userId,
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
      final inserted = await Supabase.instance.client
          .from('quests')
          .insert(rowsToInsert)
          .select();
      return List<Map<String, dynamic>>.from(inserted)
          .map(_mapQuestRow)
          .toList();
    } catch (e) {
      debugPrint('Failed to save regenerated quests (showing locally): $e');
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
    _headerCtrl.dispose();
    super.dispose();
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
    // together in one Supabase write.
    _persistProgress();

    Future.delayed(Duration(milliseconds: leveledUp ? 1800 : 700), () {
      if (mounted && !_showLevelUp) {
        setState(() => _avatarAnimationState = AvatarAnimationState.idle);
      }
    });
  }

  Future<void> _persistProgress() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // Work out the new streak from the last known active date. Same
      // calendar day → unchanged. Exactly one day later → +1. Anything
      // longer than that → the streak was broken, restart at 1.
      final now = DateTime.now();
      var streak = _streak;
      if (_lastActiveDate == null) {
        streak = 1;
      } else {
        final daysSince = DateTime(now.year, now.month, now.day)
            .difference(DateTime(_lastActiveDate!.year, _lastActiveDate!.month,
                _lastActiveDate!.day))
            .inDays;
        if (daysSince == 1) {
          streak += 1;
        } else if (daysSince > 1) {
          streak = 1;
        }
        // daysSince == 0 (same day): streak stays as-is.
      }

      final ghostMode = _everCompletedBeforeSixAM || now.hour < 6;

      if (mounted) {
        setState(() {
          _streak = streak;
          _everCompletedBeforeSixAM = ghostMode;
          _lastActiveDate = now;
        });
      } else {
        _streak = streak;
        _everCompletedBeforeSixAM = ghostMode;
        _lastActiveDate = now;
      }

      await AvatarService().saveProgressSnapshot(
        user.id,
        level: _level,
        currentXp: _currentXP,
        completedQuests: _completedQuests,
        stats: _stats,
        streak: streak,
        lastActiveDate: now,
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

    final now = DateTime.now();
    final dailyExpiry = _questSetExpiry(_dailyQuests) ??
        DateTime(now.year, now.month, now.day + 1);
    final weeklyExpiry =
        _questSetExpiry(_weeklyQuests) ?? now.add(const Duration(days: 7));

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 108),
      children: [
        // ── DAILY QUESTS ──
        _sectionTitle(
          title: 'Today',
          subtitle: 'Small wins that keep the bigger goal moving.',
          trailing: _dailyQuests.isEmpty
              ? null
              : CountdownChip(
                  target: dailyExpiry,
                  color: AppTheme.mana,
                  onExpire: _refreshDailyQuests,
                ),
        ),
        const SizedBox(height: 12),
        if (_dailyQuests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('No daily quests yet.',
                style: AppTheme.monoFont(size: 12, color: AppTheme.text600)),
          )
        else
          ..._dailyQuests.asMap().entries.map((e) {
            return QuestCard(
              title: e.value['title'] as String,
              xpReward: e.value['xp'] as String,
              category: e.value['category'] as String,
              completed: e.value['completed'] as bool,
              index: e.key,
              description: e.value['why'] as String?,
              onComplete: () => _onQuestComplete(e.value, isWeekly: false),
            );
          }),
        const SizedBox(height: 24),
        // ── WEEKLY QUESTS ──
        _sectionTitle(
          title: 'This week',
          subtitle: 'Larger pushes for when you have breathing room.',
          trailing: _weeklyQuests.isEmpty
              ? null
              : CountdownChip(
                  target: weeklyExpiry,
                  color: AppTheme.xpBlue,
                  onExpire: _refreshWeeklyQuests,
                ),
        ),
        const SizedBox(height: 12),
        if (_weeklyQuests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('No weekly quests yet.',
                style: AppTheme.monoFont(size: 12, color: AppTheme.text600)),
          )
        else
          ..._weeklyQuests.asMap().entries.map((e) {
            return QuestCard(
              title: e.value['title'] as String,
              xpReward: e.value['xp'] as String,
              category: e.value['category'] as String,
              completed: e.value['completed'] as bool,
              index: e.key,
              description: e.value['why'] as String?,
              onComplete: () => _onQuestComplete(e.value, isWeekly: true),
            );
          }),
      ],
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
