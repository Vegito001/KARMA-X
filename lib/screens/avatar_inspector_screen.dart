import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../theme/avatar_theme.dart';
import '../models/avatar.dart';
import '../models/avatar_composition.dart';
import '../models/user_avatar_progress.dart';
import '../widgets/avatar_display.dart';
import '../widgets/sparkle_burst.dart';

/// Full-screen "inspect your avatar" view, opened by tapping the avatar on
/// the profile page. The model itself is already drag-to-rotate /
/// pinch-to-zoom (model_viewer_plus's cameraControls), this just gives it
/// more room to breathe plus a few playful, purely-cosmetic reactions —
/// tap the model for a hype quote + sparkle burst, or pick a pose.
class AvatarInspectorScreen extends StatefulWidget {
  final Avatar avatar;
  final UserAvatarProgress progress;

  const AvatarInspectorScreen({
    super.key,
    required this.avatar,
    required this.progress,
  });

  @override
  State<AvatarInspectorScreen> createState() => _AvatarInspectorScreenState();
}

class _AvatarInspectorScreenState extends State<AvatarInspectorScreen> {
  AvatarAnimationState _pose = AvatarAnimationState.idle;
  final _burstCtrl = SparkleBurstController();
  final _rand = math.Random();
  String? _quote;

  static const _quotes = [
    'Looking sharp, operator.',
    'That streak isn\'t going to protect itself.',
    'Every quest completed shows.',
    'Karma matrix: fully synced.',
    'Next level is closer than you think.',
    'Discipline looks good on you.',
  ];

  Color get _statColor =>
      AvatarTheme.statColors[widget.progress.dominantStat] ?? AppTheme.copper;

  void _reactToTap() {
    HapticFeedback.lightImpact();
    _burstCtrl.fire();
    setState(() {
      _quote = _quotes[_rand.nextInt(_quotes.length)];
      _pose = AvatarAnimationState.acting;
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _pose = AvatarAnimationState.idle);
    });
  }

  void _setPose(AvatarAnimationState pose) {
    HapticFeedback.selectionClick();
    setState(() => _pose = pose);
    if (pose == AvatarAnimationState.levelUp) {
      _burstCtrl.fire();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final modelSize = math.min(size.width * 0.78, 340.0);

    return Scaffold(
      backgroundColor: AppTheme.bg900,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _reactToTap,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AvatarDisplay(
                            avatar: widget.avatar,
                            progress: widget.progress,
                            size: modelSize,
                            showBadges: true,
                            animationState: _pose,
                          ),
                          IgnorePointer(
                            child: SparkleBurst(
                              controller: _burstCtrl,
                              color: _statColor,
                              size: modelSize * 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _quote == null
                          ? Text(
                              'Drag to rotate · pinch to zoom · tap to react',
                              key: const ValueKey('hint'),
                              style: AppTheme.monoFont(
                                size: 10,
                                color: AppTheme.text400,
                                letterSpacing: 0.5,
                              ),
                            )
                          : Container(
                              key: ValueKey(_quote),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppTheme.bg800,
                                border: Border.all(
                                    color: _statColor.withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '"$_quote"',
                                style: AppTheme.monoFont(
                                  size: 11,
                                  color: AppTheme.text200,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
            _buildPoseRow(),
            const SizedBox(height: 10),
            _buildStatsStrip(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.avatar.name, style: AppTheme.displayFont(size: 18)),
              Text(
                'LEVEL ${widget.progress.currentLevel} · ${widget.avatar.defaultStat.toUpperCase()}',
                style: AppTheme.monoFont(
                  size: 9,
                  color: AppTheme.text400,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.bg800,
                border: Border.all(color: AppTheme.borderDim),
                borderRadius: BorderRadius.circular(17),
              ),
              child: const Icon(Icons.close, color: AppTheme.text200, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoseRow() {
    final poses = <(AvatarAnimationState, String, IconData)>[
      (AvatarAnimationState.idle, 'Idle', Icons.self_improvement),
      (AvatarAnimationState.acting, 'Pose', Icons.bolt),
      (AvatarAnimationState.levelUp, 'Celebrate', Icons.celebration),
      (AvatarAnimationState.resting, 'Rest', Icons.nightlight_round),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final p in poses)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => _setPose(p.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _pose == p.$1
                          ? _statColor.withValues(alpha: 0.16)
                          : AppTheme.bg800,
                      border: Border.all(
                        color: _pose == p.$1
                            ? _statColor.withValues(alpha: 0.6)
                            : AppTheme.borderDim,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Icon(p.$3,
                            size: 16,
                            color:
                                _pose == p.$1 ? _statColor : AppTheme.text400),
                        const SizedBox(height: 3),
                        Text(
                          p.$2,
                          style: AppTheme.monoFont(
                            size: 8,
                            color: _pose == p.$1
                                ? AppTheme.text100
                                : AppTheme.text400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip() {
    final stats = widget.progress.stats;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final entry in stats.entries)
            Expanded(
              child: Column(
                children: [
                  Text(
                    AvatarTheme.statEmojis[entry.key] ?? '',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entry.value}',
                    style: AppTheme.monoFont(
                      size: 12,
                      color:
                          AvatarTheme.statColors[entry.key] ?? AppTheme.text200,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
