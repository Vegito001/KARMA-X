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
import 'story_feed_screen.dart';
import 'profile_screen.dart';
import 'student_problem_screen.dart';
import '../widgets/hci_condition_toggle.dart';
import '../utils/hci_mode.dart';

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
  int _currentXP = 340;
  final int _maxXP = 500;
  int _level = 7;
  int _completedQuests = 0;
  bool _showLevelUp = false;
  int _selectedTab = 0;

  late AnimationController _headerCtrl;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;

  // Avatar system state
  Avatar? _currentAvatar;
  UserAvatarProgress? _avatarProgress;
  bool _avatarLoading = true;
  AvatarAnimationState _avatarAnimationState = AvatarAnimationState.idle;

  // Computed stats
  final Map<String, int> _stats = {
    'health': 62,
    'knowledge': 74,
    'discipline': 55,
    'social': 48,
  };

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

    // Load avatar data
    _loadAvatarData();
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
          });

          // Update dominant stat based on current stats
          await AvatarService().updateDominantStat(user.id, _stats);
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

  void _onQuestComplete(int xp, String category) {
    var leveledUp = false;
    setState(() {
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

    // Sync with avatar system
    _syncAvatarProgress();

    Future.delayed(Duration(milliseconds: leveledUp ? 1800 : 700), () {
      if (mounted && !_showLevelUp) {
        setState(() => _avatarAnimationState = AvatarAnimationState.idle);
      }
    });
  }

  Future<void> _syncAvatarProgress() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await AvatarService().updateLevel(user.id, _level);
        await AvatarService().updateDominantStat(user.id, _stats);

        // Check for new badges
        final newBadges = AvatarService().checkBadgesUnlocked(
          _level,
          _completedQuests,
        );
        await AvatarService().updateBadges(user.id, newBadges);

        // Reload avatar progress
        await _loadAvatarData();
      }
    } catch (e) {
      debugPrint('Error syncing avatar progress: $e');
    }
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
                  child: _selectedTab == 0
                      ? _buildQuestView()
                      : _selectedTab == 1
                          ? _buildStatsView()
                          : _buildFeedView(),
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
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileScreen(
                          playerName: widget.playerName,
                          level: _level,
                          completedQuests: _completedQuests,
                        ),
                      ),
                    ),
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
    final tabs = ['Today', 'Growth', 'Feed'];
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
          subtitle: 'Small wins that keep the bigger goal moving.',
        ),
        const SizedBox(height: 12),
        if (_dailyQuests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('No daily quests yet.', style: AppTheme.monoFont(size: 12, color: AppTheme.text600)),
          )
        else
          ..._dailyQuests.asMap().entries.map((e) {
            return QuestCard(
              title: e.value['title'] as String,
              xpReward: e.value['xp'] as String,
              category: e.value['category'] as String,
              completed: e.value['completed'] as bool,
              index: e.key,
              onComplete: () => _onQuestComplete(
                  int.parse(e.value['xp'] as String), e.value['category'] as String),
            );
          }),
        const SizedBox(height: 24),
        // ── WEEKLY QUESTS ──
        _sectionTitle(
          title: 'This week',
          subtitle: 'Larger pushes for when you have breathing room.',
        ),
        const SizedBox(height: 12),
        if (_weeklyQuests.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('No weekly quests yet.', style: AppTheme.monoFont(size: 12, color: AppTheme.text600)),
          )
        else
          ..._weeklyQuests.asMap().entries.map((e) {
            return QuestCard(
              title: e.value['title'] as String,
              xpReward: e.value['xp'] as String,
              category: e.value['category'] as String,
              completed: e.value['completed'] as bool,
              index: e.key,
              onComplete: () => _onQuestComplete(
                  int.parse(e.value['xp'] as String), e.value['category'] as String),
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
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.copper,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.copper.withValues(alpha: 0.3),
                      blurRadius: 20, offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text('START HERE  ›',
                    style: AppTheme.displayFont(size: 13, color: AppTheme.bg900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle({required String title, required String subtitle}) {
    return Column(
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
          child: const Column(
            children: [
              StatBar(
                statName: 'Health',
                emoji: '🏃',
                value: 62,
                delay: Duration(milliseconds: 100),
              ),
              StatBar(
                statName: 'Knowledge',
                emoji: '📚',
                value: 74,
                delay: Duration(milliseconds: 200),
              ),
              StatBar(
                statName: 'Discipline',
                emoji: '⚡',
                value: 55,
                delay: Duration(milliseconds: 300),
              ),
              StatBar(
                statName: 'Social',
                emoji: '🧍',
                value: 48,
                delay: Duration(milliseconds: 400),
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
          {'label': 'Streak', 'value': '4 DAYS'},
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

  Widget _buildFeedView() {
    return const StoryFeedWidget();
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
          _navItem(Icons.auto_awesome_outlined, 'Feed', 2),
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
