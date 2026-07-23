import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/glitch_text.dart';
import '../widgets/xp_bar.dart';
import '../widgets/scanline_overlay.dart';
import '../widgets/avatar_display.dart';
import '../models/avatar.dart';
import '../models/user_avatar_progress.dart';
import '../services/avatar_service.dart';

class ProfileScreen extends StatefulWidget {
  final String playerName;
  final int level;
  final int completedQuests;
  // Real growth stats (health/knowledge/discipline/social), the player's
  // current day streak, and whether they've ever completed a quest before
  // 6AM — all sourced from persisted data on the Dashboard rather than
  // hardcoded here.
  final Map<String, int> stats;
  final int streak;
  final bool everCompletedBeforeSixAM;

  const ProfileScreen({
    super.key,
    required this.playerName,
    required this.level,
    required this.completedQuests,
    this.stats = const {
      'health': 0,
      'knowledge': 0,
      'discipline': 0,
      'social': 0,
    },
    this.streak = 0,
    this.everCompletedBeforeSixAM = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  // Avatar system state
  Avatar? _currentAvatar;
  UserAvatarProgress? _avatarProgress;
  bool _avatarLoading = true;

  // Computed from the real player data passed into this screen instead of
  // a fixed true/false list — each achievement reflects actual progress.
  List<Map<String, dynamic>> get _achievements {
    final health = widget.stats['health'] ?? 0;
    final knowledge = widget.stats['knowledge'] ?? 0;
    final discipline = widget.stats['discipline'] ?? 0;
    final social = widget.stats['social'] ?? 0;

    return [
      {
        'title': 'FIRST BLOOD',
        'desc': 'Complete your first quest',
        'earned': widget.completedQuests >= 1,
        'icon': '⚔️',
      },
      {
        'title': 'IRON WILL',
        'desc': 'Maintain a 3-day streak',
        'earned': widget.streak >= 3,
        'icon': '🔩',
      },
      {
        'title': 'MIND FORGE',
        'desc': 'Reach 70+ Knowledge stat',
        'earned': knowledge >= 70,
        'icon': '🧠',
      },
      {
        'title': 'GHOST MODE',
        'desc': 'Complete a quest before 6AM',
        'earned': widget.everCompletedBeforeSixAM,
        'icon': '👻',
      },
      {
        'title': 'APEX NODE',
        'desc': 'Reach Level 10',
        'earned': widget.level >= 10,
        'icon': '🔺',
      },
      {
        'title': 'FULL STACK',
        'desc': 'Max all 4 core stats',
        'earned': health >= 100 &&
            knowledge >= 100 &&
            discipline >= 100 &&
            social >= 100,
        'icon': '⬛',
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

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
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg900,
      body: ScanlineOverlay(
        child: FadeTransition(
          opacity: _fade,
          child: SafeArea(
            child: Column(
              children: [
                // ── TOP BAR ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.borderDim),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new,
                            size: 14,
                            color: AppTheme.text100,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'PROFILE',
                        style: AppTheme.displayFont(
                          size: 16,
                          color: AppTheme.text100,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      // ── AVATAR ──
                      _buildAvatarSection(),
                      const SizedBox(height: 28),
                      // ── STATS ROW ──
                      _buildStatsRow(),
                      const SizedBox(height: 28),
                      // ── XP BARS ──
                      _buildXpSection(),
                      const SizedBox(height: 28),
                      // ── ACHIEVEMENTS ──
                      _buildAchievements(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Row(
      children: [
        // ── AVATAR DISPLAY ──
        _avatarLoading || _currentAvatar == null || _avatarProgress == null
            ? Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.bg800,
                  border: Border.all(color: AppTheme.text100, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.text100.withValues(alpha: 0.15),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: GlitchText(
                    text: widget.playerName.isNotEmpty
                        ? widget.playerName[0]
                        : 'P',
                    fontSize: 40,
                    useDisplay: true,
                  ),
                ),
              )
            : AvatarDisplay(
                avatar: _currentAvatar!,
                progress: _avatarProgress!,
                size: 88,
                showBadges: true,
              ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.playerName, style: AppTheme.displayFont(size: 20)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.borderBright),
                ),
                child: Text(
                  'LEVEL ${widget.level} OPERATOR',
                  style: AppTheme.monoFont(
                    size: 10,
                    color: AppTheme.text200,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'KARMA MATRIX ACTIVE',
                style: AppTheme.monoFont(
                  size: 9,
                  color: AppTheme.text400,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    final stats = [
      {'label': 'LEVEL', 'value': '${widget.level}'},
      {'label': 'QUESTS', 'value': '${widget.completedQuests}'},
      {'label': 'STREAK', 'value': '${widget.streak}'},
    ];
    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: AppTheme.baseCard(borderColor: AppTheme.borderBright),
            child: Column(
              children: [
                Text(s['value']!, style: AppTheme.displayFont(size: 26)),
                const SizedBox(height: 4),
                Text(
                  s['label']!,
                  style: AppTheme.monoFont(
                    size: 9,
                    color: AppTheme.text400,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildXpSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.baseCard(borderColor: AppTheme.borderDim),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '// STAT PROGRESSION',
            style: AppTheme.monoFont(
              size: 10,
              color: AppTheme.text400,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 16),
          XpBar(
            current: (widget.stats['health'] ?? 0).toDouble(),
            max: 100,
            label: '🏃 HEALTH',
          ),
          const SizedBox(height: 12),
          XpBar(
            current: (widget.stats['knowledge'] ?? 0).toDouble(),
            max: 100,
            label: '📚 KNOWLEDGE',
          ),
          const SizedBox(height: 12),
          XpBar(
            current: (widget.stats['discipline'] ?? 0).toDouble(),
            max: 100,
            label: '⚡ DISCIPLINE',
          ),
          const SizedBox(height: 12),
          XpBar(
            current: (widget.stats['social'] ?? 0).toDouble(),
            max: 100,
            label: '🧍 SOCIAL',
          ),
        ],
      ),
    );
  }

  Widget _buildAchievements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '// ACHIEVEMENTS',
          style: AppTheme.monoFont(
            size: 10,
            color: AppTheme.text400,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
          ),
          itemCount: _achievements.length,
          itemBuilder: (_, i) {
            final a = _achievements[i];
            final earned = a['earned'] as bool;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: earned ? AppTheme.bg700 : AppTheme.bg900,
                border: Border.all(
                  color: earned ? AppTheme.borderBright : AppTheme.borderDim,
                  width: earned ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        a['icon'] as String,
                        style: TextStyle(
                          fontSize: 18,
                          color: earned ? null : const Color(0x44FFFFFF),
                        ),
                      ),
                      if (!earned)
                        const Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: AppTheme.bg600,
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a['title'] as String,
                        style: AppTheme.displayFont(
                          size: 10,
                          color: earned ? AppTheme.text100 : AppTheme.bg600,
                        ),
                      ),
                      Text(
                        a['desc'] as String,
                        style: AppTheme.monoFont(
                          size: 9,
                          color: earned ? AppTheme.text200 : AppTheme.bg600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
