import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../utils/hci_mode.dart';
import '../widgets/glitch_text.dart';
import '../widgets/scanline_overlay.dart';
import '../widgets/quest_card.dart';
import '../widgets/hci_condition_toggle.dart';
import '../services/player_profile_service.dart';
import '../services/ai_service.dart';
import '../utils/student_state.dart';
import 'student_problem_screen.dart';
import 'dashboard_screen.dart';

// ─────────────────────────────────────────────
//  Quest data model
// ─────────────────────────────────────────────
class GeneratedQuest {
  final String title;
  final String xp;
  final String category; // discipline | health | knowledge | social
  final String why; // one-line reason tying back to the problem/cause

  const GeneratedQuest({
    required this.title,
    required this.xp,
    required this.category,
    required this.why,
  });

  factory GeneratedQuest.fromJson(Map<String, dynamic> json) {
    return GeneratedQuest(
      title: json['title'] as String? ?? 'Complete a daily task',
      xp: json['xp']?.toString() ?? '10',
      category: json['category'] as String? ?? 'discipline',
      why: json['why'] as String? ?? 'Builds momentum.',
    );
  }

  // ── Shared fallback quests (used when the API is unavailable) ──────────
  // Kept here as static generators so both the onboarding flow AND the
  // dashboard's daily/weekly refresh use the exact same fallback set when
  // Modal/Gemini can't be reached — "resetting" a quest set always goes
  // through the same generation path, with the same safety net either way.
  static List<GeneratedQuest> fallbackDaily(String problemTitle) => [
        GeneratedQuest(
          title: '2-min rule: start any task immediately',
          xp: '10',
          category: 'discipline',
          why: 'Breaks the initiation barrier causing '
              '${problemTitle.toLowerCase()}.',
        ),
        GeneratedQuest(
          title: 'Phone in another room during 1 study block',
          xp: '15',
          category: 'discipline',
          why: 'Removes the primary distraction trigger.',
        ),
        GeneratedQuest(
          title: '10-min walk between study sessions',
          xp: '8',
          category: 'health',
          why: 'Resets dopamine for sustained focus.',
        ),
        GeneratedQuest(
          title: 'Write 3 tasks for tomorrow before bed',
          xp: '10',
          category: 'knowledge',
          why: 'Reduces decision fatigue next morning.',
        ),
        GeneratedQuest(
          title: 'Sleep by a consistent time tonight',
          xp: '12',
          category: 'health',
          why: 'Sleep consistency is the root fix for most student struggles.',
        ),
      ];

  static List<GeneratedQuest> fallbackWeekly() => [
        GeneratedQuest(
          title: 'Complete one full Pomodoro session (4×25 min)',
          xp: '30',
          category: 'discipline',
          why: 'Builds structured focus habit directly targeting your block.',
        ),
        GeneratedQuest(
          title: 'Talk to one person you normally avoid',
          xp: '25',
          category: 'social',
          why: 'Expands comfort zone in a controlled, low-stakes way.',
        ),
        GeneratedQuest(
          title: 'Reflect on the week: what worked, what didn\'t',
          xp: '20',
          category: 'knowledge',
          why: 'Self-awareness is the meta-skill that improves all others.',
        ),
      ];
}

// ─────────────────────────────────────────────
//  Screen
// ─────────────────────────────────────────────
class StudentQuestScreen extends StatefulWidget {
  final String playerName;
  final String schedule;
  final StudentProblem problem;
  final List<String> selectedCauses;
  final List<String> quizAnswers;

  const StudentQuestScreen({
    super.key,
    required this.playerName,
    required this.schedule,
    required this.problem,
    required this.selectedCauses,
    required this.quizAnswers,
  });

  @override
  State<StudentQuestScreen> createState() => _StudentQuestScreenState();
}

class _StudentQuestScreenState extends State<StudentQuestScreen>
    with TickerProviderStateMixin {
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  String? _saveError;
  List<GeneratedQuest> _dailyQuests = [];
  List<GeneratedQuest> _weeklyQuests = [];

  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;
  late AnimationController _resultFade;
  late Animation<double> _fade;

  static const String _loadingLine1 = '> SCANNING KARMA PATTERN...';
  static const String _loadingLine2 = '> MAPPING ROOT CAUSE VECTORS...';
  static const String _loadingLine3 = '> GENERATING LIFE QUEST PATH...';
  int _loadingStep = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.3, end: 1.0).animate(_pulseCtrl);

    _resultFade = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _resultFade, curve: Curves.easeOut);

    _startLoadingAnimation();
    _generateQuests();
  }

  void _startLoadingAnimation() async {
    for (int i = 0; i < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _loadingStep = i + 1);
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _resultFade.dispose();
    super.dispose();
  }

  // ── Save profile using PlayerProfileService (handles local + Supabase) ──
  Future<void> _saveProfileToSupabase() async {
    await PlayerProfileService().saveComplete(
      playerName: widget.playerName,
      profession: 'Student',
      schedule: widget.schedule,
      goal: widget.problem.title,
    );
  }

  // ── Save AI reasoning + generated quests to Supabase ──
  Future<void> _saveQuestsToSupabase(
    String userId,
    List<GeneratedQuest> daily,
    List<GeneratedQuest> weekly,
    String reasoning,
    String primaryProblem,
    String rootCause,
  ) async {
    final now = DateTime.now();

    // Daily quests expire at midnight tonight
    final todayMidnight = DateTime(now.year, now.month, now.day + 1);

    // Weekly quests expire in 7 days
    final nextWeek = now.add(const Duration(days: 7));

    // 1. Save the lifestyle state snapshot first, so ai_generations can
    // link back to the exact state that informed this reasoning.
    final stateRow = await Supabase.instance.client
        .from('user_state')
        .insert({
          'user_id': userId,
          'sleep_hours': StudentState.instance.sleepHours,
          'study_hours': StudentState.instance.studyHours,
          'screen_time_hours': StudentState.instance.screenTimeHours,
          'stress_level': StudentState.instance.stressLevel,
          'physical_activity_hours':
              StudentState.instance.physicalActivityHours,
          'social_hours': StudentState.instance.socialHours,
          'gpa': StudentState.instance.gpa,
          'emotion': StudentState.instance.emotion,
          'source': 'onboarding',
        })
        .select()
        .single();

    final userStateId = stateRow['id'];

    // 2. Save the reasoning as one ai_generations row, get its id back.
    // This is what makes fine-tuning possible later — without this row,
    // there would be no record of WHY these quests were chosen.
    final generationRow = await Supabase.instance.client
        .from('ai_generations')
        .insert({
          'user_id': userId,
          'user_state_id': userStateId,
          'primary_problem': primaryProblem,
          'root_cause': rootCause,
          'reasoning': reasoning,
          'model_version': 'gemini-3.1-flash-lite',
        })
        .select()
        .single();

    final generationId = generationRow['id'];

    // 3. Build quest rows, each pointing back at that generation.
    // Daily and weekly are inserted separately (each with .select()) so the
    // ids Supabase assigns come back in the same order as the input lists —
    // that lets us thread real row ids into the dashboard hand-off below,
    // instead of the dashboard only discovering them on the next reload.
    final dailyRows = daily
        .map((q) => {
              'user_id': userId,
              'generation_id': generationId,
              'title': q.title,
              'xp_reward': int.tryParse(q.xp) ?? 10,
              'category': q.category,
              'why': q.why,
              'quest_type': 'daily',
              'completed': false,
              'expires_at': todayMidnight.toUtc().toIso8601String(),
            })
        .toList();
    final weeklyRows = weekly
        .map((q) => {
              'user_id': userId,
              'generation_id': generationId,
              'title': q.title,
              'xp_reward': int.tryParse(q.xp) ?? 10,
              'category': q.category,
              'why': q.why,
              'quest_type': 'weekly',
              'completed': false,
              'expires_at': nextWeek.toUtc().toIso8601String(),
            })
        .toList();

    final insertedDaily = dailyRows.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await Supabase.instance.client
            .from('quests')
            .insert(dailyRows)
            .select());
    final insertedWeekly = weeklyRows.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(await Supabase.instance.client
            .from('quests')
            .insert(weeklyRows)
            .select());

    _savedDailyQuestIds = insertedDaily.map((r) => r['id']).toList();
    _savedWeeklyQuestIds = insertedWeekly.map((r) => r['id']).toList();
  }

  // Row ids Supabase assigned to the most recently saved quests, in the
  // same order as _dailyQuests / _weeklyQuests. Used to pass real ids into
  // the dashboard so quest completion can be persisted immediately.
  List<dynamic> _savedDailyQuestIds = [];
  List<dynamic> _savedWeeklyQuestIds = [];

  // ── Build the AI prompt ──────────────────────
  // ── Call Gemini via AiService ─────────────────
  Future<void> _generateQuests() async {
    try {
      final parsed = await AiService().generateQuests(
        playerName: widget.playerName,
        schedule: widget.schedule,
        problemTitle: widget.problem.title,
        problemSubtitle: widget.problem.subtitle,
        selectedCauses: widget.selectedCauses,
        quizAnswers: widget.quizAnswers,
        sleepHours: StudentState.instance.sleepHours,
        studyHours: StudentState.instance.studyHours,
        screenTimeHours: StudentState.instance.screenTimeHours,
        stressLevel: StudentState.instance.stressLevel,
        physicalActivityHours: StudentState.instance.physicalActivityHours,
        socialHours: StudentState.instance.socialHours,
        gpa: StudentState.instance.gpa,
        emotion: StudentState.instance.emotion,
      );

      final dailyRaw = parsed['daily'] as List<dynamic>;
      final weeklyRaw = parsed['weekly'] as List<dynamic>;
      final reasoning = parsed['reasoning'] as String? ?? '';
      final primaryProblem =
          parsed['primary_problem'] as String? ?? widget.problem.title;
      final rootCause = parsed['root_cause'] as String? ?? '';

      final daily = dailyRaw
          .map((e) => GeneratedQuest.fromJson(e as Map<String, dynamic>))
          .toList();
      final weekly = weeklyRaw
          .map((e) => GeneratedQuest.fromJson(e as Map<String, dynamic>))
          .toList();

      // ── Save profile + quests to Supabase ──────
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw Exception('No authenticated user');
        await Future.wait([
          _saveProfileToSupabase(),
          _saveQuestsToSupabase(
              user.id, daily, weekly, reasoning, primaryProblem, rootCause),
        ]);
        if (mounted) setState(() => _saveError = null);
      } catch (saveErr) {
        debugPrint('Supabase save error: $saveErr');
        if (mounted) setState(() => _saveError = saveErr.toString());
      }

      if (mounted) {
        setState(() {
          _dailyQuests = daily;
          _weeklyQuests = weekly;
          _loading = false;
        });
        _resultFade.forward();
      }
    } catch (e) {
      debugPrint('Quest generation error: $e');
      _loadFailed = true;
      // Fallback quests if API fails — still attempt Supabase save
      final fallbackDaily = _fallbackDaily();
      final fallbackWeekly = _fallbackWeekly();
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await Future.wait([
            _saveProfileToSupabase(),
            _saveQuestsToSupabase(
              user.id,
              fallbackDaily,
              fallbackWeekly,
              'Gemini API was unavailable — fallback quests shown instead of a reasoned intervention.',
              widget.problem.title,
              'Unknown (API error)',
            ),
          ]);
          if (mounted) setState(() => _saveError = null);
        }
      } catch (saveErr) {
        debugPrint('Supabase save error (fallback path): $saveErr');
        if (mounted) setState(() => _saveError = saveErr.toString());
      }

      if (mounted) {
        setState(() {
          _dailyQuests = fallbackDaily;
          _weeklyQuests = fallbackWeekly;
          _loading = false;
        });
        _resultFade.forward();
      }
    }
  }

  // ── Fallback quests (offline / API error) ────
  List<GeneratedQuest> _fallbackDaily() =>
      GeneratedQuest.fallbackDaily(widget.problem.title);

  List<GeneratedQuest> _fallbackWeekly() => GeneratedQuest.fallbackWeekly();

  // ── Navigate to dashboard ─────────────────────
  Future<void> _enterDashboard() async {
    // If save failed earlier, retry once before entering dashboard
    if (_saveError != null) {
      setState(() => _saving = true);
      try {
        await _saveProfileToSupabase();
        setState(() {
          _saveError = null;
          _saving = false;
        });
      } catch (e) {
        setState(() {
          _saveError = e.toString();
          _saving = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Profile save failed — you can retry from Settings.\n$e',
                style: AppTheme.monoFont(size: 11),
              ),
              backgroundColor: AppTheme.bg800,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }

    if (!mounted) return;

    // Same expiry convention used when these rows were inserted into
    // Supabase (see _saveQuestsToSupabase above) — daily quests expire at
    // midnight tonight, weekly quests expire 7 days from now. Handing this
    // to the dashboard means the countdown shows the right time immediately,
    // without waiting on another round trip to Supabase.
    final now = DateTime.now();
    final dailyExpiry = DateTime(now.year, now.month, now.day + 1);
    final weeklyExpiry = now.add(const Duration(days: 7));

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => DashboardScreen(
          playerName: widget.playerName,
          goal: widget.problem.title,
          profession: 'Student',
          dailyQuestsOverride: _dailyQuests
              .asMap()
              .entries
              .map((e) => {
                    'id': e.key < _savedDailyQuestIds.length
                        ? _savedDailyQuestIds[e.key]
                        : null,
                    'title': e.value.title,
                    'xp': e.value.xp,
                    'category': e.value.category,
                    'completed': false,
                    'why': e.value.why,
                    'expires_at': dailyExpiry.toUtc().toIso8601String(),
                  })
              .toList(),
          weeklyQuestsOverride: _weeklyQuests
              .asMap()
              .entries
              .map((e) => {
                    'id': e.key < _savedWeeklyQuestIds.length
                        ? _savedWeeklyQuestIds[e.key]
                        : null,
                    'title': e.value.title,
                    'xp': e.value.xp,
                    'category': e.value.category,
                    'completed': false,
                    'why': e.value.why,
                    'expires_at': weeklyExpiry.toUtc().toIso8601String(),
                  })
              .toList(),
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HciMode.instance.useGestalt ? _buildGestalt() : _buildBaseline(),
        Positioned(
          top: 76,
          right: 12,
          child: SafeArea(child: HciConditionToggle()),
        ),
      ],
    );
  }

  Widget _buildBaseline() {
    return Scaffold(
      backgroundColor: AppTheme.bg900,
      body: ScanlineOverlay(
        child: SafeArea(
          child: _loading ? _buildLoading() : _buildResults(),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  //  CONDITION B — GESTALT REDESIGN
  //  • Closure      — 4-step strip: user sees they are on the LAST step
  //  • Proximity    — icon + title + desc + tags = ONE tightly grouped unit
  //  • Similarity   — all daily cards identical; all weekly cards identical
  //  • Prägnanz     — simplest readable card form, zero noise
  //  • Figure/Ground — quest card floats via accent-glow left border
  // ══════════════════════════════════════════════════════════════════
  Widget _buildGestalt() {
    return Scaffold(
      backgroundColor: AppTheme.bg900,
      body: Container(
        decoration: AppTheme.scaffoldBackground(),
        child: ScanlineOverlay(
          child: SafeArea(
            child: _loading
                ? _buildLoading()
                : Column(children: [
                    // CLOSURE — step 4 of 4, journey complete
                    _gestaltStepStrip(activeStep: 3),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                        children: [
                          // HEADER
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('STEP 04  ·  YOUR PERSONALISED QUESTS',
                                    style: AppTheme.monoFont(
                                        size: 9,
                                        color: AppTheme.mana,
                                        letterSpacing: 2)),
                                const SizedBox(height: 10),
                                const GlitchText(
                                    text: 'YOUR LIFE\nQUESTS AWAIT',
                                    fontSize: 24,
                                    useDisplay: true),
                                const SizedBox(height: 8),
                                Text(
                                    'Built by Gemini AI from YOUR problem and answers.\nComplete them to earn XP and evolve your avatar.',
                                    style: AppTheme.monoFont(
                                        size: 12, color: AppTheme.text400)),
                                const SizedBox(height: 10),
                                // CLOSURE — shows total count upfront
                                Row(children: [
                                  _gestaltCountBadge('${_dailyQuests.length}',
                                      'DAILY', AppTheme.mana),
                                  const SizedBox(width: 10),
                                  _gestaltCountBadge('${_weeklyQuests.length}',
                                      'WEEKLY', AppTheme.copper),
                                  const SizedBox(width: 10),
                                  _gestaltCountBadge(
                                      '${_dailyQuests.length + _weeklyQuests.length}',
                                      'TOTAL',
                                      AppTheme.text400),
                                ]),
                              ]),
                          if (_loadFailed) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.copper.withValues(alpha: 0.06),
                                border: Border.all(
                                    color:
                                        AppTheme.copper.withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(children: [
                                const Icon(Icons.info_outline,
                                    color: AppTheme.copper, size: 14),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(
                                        'Showing fallback quests (AI error)',
                                        style: AppTheme.monoFont(
                                            size: 10, color: AppTheme.copper))),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 24),
                          if (_dailyQuests.isNotEmpty) ...[
                            _gestaltSectionHeader('DAILY QUESTS', AppTheme.mana,
                                'Do these every day for consistent growth'),
                            const SizedBox(height: 12),
                            // SIMILARITY — all daily cards share IDENTICAL structure
                            ..._dailyQuests.asMap().entries.map((e) =>
                                _gestaltQuestCard(e.value, e.key,
                                    isWeekly: false)),
                            const SizedBox(height: 28),
                          ],
                          if (_weeklyQuests.isNotEmpty) ...[
                            _gestaltSectionHeader(
                                'WEEKLY QUESTS',
                                AppTheme.copper,
                                'Bigger challenges for your days off'),
                            const SizedBox(height: 12),
                            // SIMILARITY — all weekly cards share a distinct but consistent style
                            ..._weeklyQuests.asMap().entries.map((e) =>
                                _gestaltQuestCard(
                                    e.value, _dailyQuests.length + e.key,
                                    isWeekly: true)),
                          ],
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                    // FIGURE/GROUND — CTA is the sole figure, isolated below border
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                      decoration: BoxDecoration(
                        color: AppTheme.bg900.withValues(alpha: 0.96),
                        border: const Border(
                            top: BorderSide(color: AppTheme.borderDim)),
                      ),
                      child: Column(children: [
                        // Prägnanz — single clear XP number
                        Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('TOTAL XP AVAILABLE  ',
                                  style: AppTheme.monoFont(
                                      size: 10, color: AppTheme.text400)),
                              Text(
                                '+${([
                                  ..._dailyQuests,
                                  ..._weeklyQuests
                                ].fold<int>(0, (s, q) => s + (int.tryParse(q.xp) ?? 0)))} XP',
                                style: AppTheme.monoFont(
                                    size: 13, color: AppTheme.copper),
                              ),
                            ]),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _saving ? null : _enterDashboard,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            decoration: BoxDecoration(
                              color: AppTheme.copper,
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: [
                                BoxShadow(
                                    color:
                                        AppTheme.copper.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 6))
                              ],
                            ),
                            child: Center(
                                child: Text('ACCEPT QUESTS  ›  GO TO DASHBOARD',
                                    style: AppTheme.displayFont(
                                        size: 12, color: AppTheme.bg900))),
                          ),
                        ),
                      ]),
                    ),
                  ]),
          ),
        ),
      ),
    );
  }

  // 4-step strip — reused across all 3 gestalt screens
  Widget _gestaltStepStrip({required int activeStep}) {
    final steps = ['DESCRIBE', 'ROOT CAUSE', 'QUIZ', 'QUESTS'];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: const BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppTheme.borderDim, width: 1))),
      child: Row(
          children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final filledStep = i ~/ 2;
          return Expanded(
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 1.5,
                  color: activeStep > filledStep
                      ? AppTheme.mana
                      : AppTheme.bg500));
        }
        final stepIdx = i ~/ 2;
        final isDone = activeStep > stepIdx;
        final isActive = activeStep == stepIdx;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? AppTheme.mana : AppTheme.bg700,
              border: Border.all(
                  color: isDone || isActive ? AppTheme.mana : AppTheme.bg500,
                  width: isActive ? 2 : 1),
            ),
            child: Center(
                child: isDone
                    ? const Icon(Icons.check,
                        size: 14, color: Color(0xFF070818))
                    : Text('${stepIdx + 1}',
                        style: AppTheme.monoFont(
                            size: 10,
                            color:
                                isActive ? AppTheme.mana : AppTheme.text600))),
          ),
          const SizedBox(height: 4),
          Text(steps[stepIdx],
              style: AppTheme.monoFont(
                  size: 8,
                  color: isActive
                      ? AppTheme.mana
                      : isDone
                          ? AppTheme.mana.withValues(alpha: 0.6)
                          : AppTheme.text600,
                  letterSpacing: 1)),
        ]);
      })),
    );
  }

  // PROXIMITY — all quest info in one tightly bordered unit
  // FIGURE/GROUND — card floats via accent left border + glow
  Widget _gestaltQuestCard(GeneratedQuest q, int index,
      {required bool isWeekly}) {
    final accentColor = isWeekly ? AppTheme.copper : AppTheme.mana;
    final statColor = _statColor(q.category);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isWeekly
                  ? AppTheme.copper.withValues(alpha: 0.07)
                  : AppTheme.mana.withValues(alpha: 0.05),
              AppTheme.bg800,
            ]),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
          top: BorderSide(color: AppTheme.borderDim, width: 1),
          right: BorderSide(color: AppTheme.borderDim, width: 1),
          bottom: BorderSide(color: AppTheme.borderDim, width: 1),
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
              color: accentColor.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // PROXIMITY — icon + title always together
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_categoryEmoji(q.category),
              style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Text(q.title,
                  style: AppTheme.monoFont(size: 13, color: AppTheme.text100))),
          // SIMILARITY — all XP badges identical style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              border: Border.all(color: accentColor.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('+${q.xp}',
                style: AppTheme.monoFont(size: 11, color: accentColor)),
          ),
        ]),
        if (q.why.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(q.why,
              style: AppTheme.monoFont(
                  size: 11, color: AppTheme.text400, height: 1.5)),
        ],
        // PROXIMITY — tags inside same card unit
        const SizedBox(height: 10),
        Row(children: [
          _gestaltTag(q.category.toUpperCase(), statColor),
          const SizedBox(width: 8),
          _gestaltTag(isWeekly ? 'WEEKLY' : 'DAILY', AppTheme.text600),
        ]),
      ]),
    );
  }

  Widget _gestaltTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(label,
          style: AppTheme.monoFont(size: 9, color: color, letterSpacing: 1)),
    );
  }

  Widget _gestaltCountBadge(String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(count, style: AppTheme.monoFont(size: 14, color: color)),
        const SizedBox(width: 5),
        Text(label,
            style: AppTheme.monoFont(
                size: 8,
                color: color.withValues(alpha: 0.7),
                letterSpacing: 1)),
      ]),
    );
  }

  Widget _gestaltSectionHeader(String label, Color color, String subtitle) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Container(width: 3, height: 28, color: color),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: AppTheme.monoFont(size: 11, color: color, letterSpacing: 2)),
        Text(subtitle,
            style: AppTheme.monoFont(size: 9, color: AppTheme.text600)),
      ]),
    ]);
  }

  String _categoryEmoji(String cat) => switch (cat.toLowerCase()) {
        'health' => '💪',
        'knowledge' => '📚',
        'discipline' => '⚡',
        'social' => '🤝',
        _ => '🎯',
      };

  Color _statColor(String stat) => switch (stat.toLowerCase()) {
        'health' => const Color(0xFF4ADE80),
        'knowledge' => AppTheme.xpBlue,
        'discipline' => AppTheme.copper,
        'social' => AppTheme.copperDim,
        _ => AppTheme.text400,
      };

  // ── Shared Loading View ─────────────────────────────
  Widget _buildLoading() {
    final lines = [_loadingLine1, _loadingLine2, _loadingLine3];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Opacity(
                opacity: _pulse.value,
                child: const Text('⚡', style: TextStyle(fontSize: 48)),
              ),
            ),
            const SizedBox(height: 32),
            const GlitchText(
              text: 'AI ANALYSIS\nIN PROGRESS',
              fontSize: 26,
              useDisplay: true,
            ),
            const SizedBox(height: 32),
            ...lines.asMap().entries.map((e) {
              final visible = _loadingStep > e.key;
              return AnimatedOpacity(
                duration: const Duration(milliseconds: 400),
                opacity: visible ? 1.0 : 0.0,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    e.value,
                    style: AppTheme.monoFont(size: 11, color: AppTheme.mana),
                  ),
                ),
              );
            }),
            const SizedBox(height: 24),
            const SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: AppTheme.bg700,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.copper),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Results View ──────────────────────────────
  Widget _buildResults() {
    return FadeTransition(
      opacity: _fade,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '> QUEST PATH GENERATED',
                  style: AppTheme.monoFont(
                      size: 10, color: AppTheme.mana, letterSpacing: 2),
                ),
                const SizedBox(height: 10),
                const GlitchText(
                  text: 'YOUR LIFE\nQUESTS',
                  fontSize: 28,
                  useDisplay: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'Customised for your ${widget.problem.title.toLowerCase()} pattern.\nComplete quests to level up your real life.',
                  style: AppTheme.monoFont(size: 12, color: AppTheme.text200),
                ),
                const SizedBox(height: 16),
                // Problem context chip
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.borderBright),
                    color: AppTheme.bg800,
                  ),
                  child: Text(
                    '${widget.problem.icon}  ${widget.problem.title}  ·  '
                    '${widget.selectedCauses.length} causes  ·  '
                    '5 quiz answers',
                    style: AppTheme.monoFont(size: 11, color: AppTheme.text400),
                  ),
                ),
                // ── Supabase save status ──
                if (_saveError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.bg600),
                      color: AppTheme.bg900,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: AppTheme.copper, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '> PROFILE SAVE FAILED — WILL RETRY ON ENTER',
                            style: AppTheme.monoFont(
                                size: 9, color: AppTheme.copper),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppTheme.mana, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        '> PROFILE SAVED TO SYSTEM',
                        style: AppTheme.monoFont(size: 9, color: AppTheme.mana),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Container(height: 1, color: AppTheme.borderDim),
              ],
            ),
          ),

          // Quest lists
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                // Daily
                _sectionHeader('DAILY QUESTS', AppTheme.copper),
                const SizedBox(height: 12),
                ..._dailyQuests.asMap().entries.map((e) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        QuestCard(
                          title: e.value.title,
                          xpReward: e.value.xp,
                          category: e.value.category,
                          index: e.key,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, left: 4),
                          child: Text(
                            '↳ ${e.value.why}',
                            style: AppTheme.monoFont(
                                size: 10, color: AppTheme.text400),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    )),

                const SizedBox(height: 20),

                // Weekly
                _sectionHeader('WEEKLY QUESTS', AppTheme.xpBlue),
                const SizedBox(height: 12),
                ..._weeklyQuests.asMap().entries.map((e) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        QuestCard(
                          title: e.value.title,
                          xpReward: e.value.xp,
                          category: e.value.category,
                          index: e.key + 5,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, left: 4),
                          child: Text(
                            '↳ ${e.value.why}',
                            style: AppTheme.monoFont(
                                size: 10, color: AppTheme.text400),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    )),

                const SizedBox(height: 100),
              ],
            ),
          ),

          // CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: GestureDetector(
              onTap: _saving ? null : _enterDashboard,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: _saving ? AppTheme.bg700 : AppTheme.copper,
                ),
                child: Center(
                  child: Text(
                    _saving ? 'SAVING PROFILE...' : 'ENTER THE SYSTEM  ⚡',
                    style: AppTheme.displayFont(
                      size: 13,
                      color: _saving ? AppTheme.text400 : AppTheme.bg900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label, Color color) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppTheme.monoFont(size: 11, color: color, letterSpacing: 2),
        ),
      ],
    );
  }
}
