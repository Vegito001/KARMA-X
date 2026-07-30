import 'package:flutter/material.dart';

class AvatarTheme {
  static const Map<String, Color> statColors = {
    'health': Color(0xFFFF6B4A), // Red-orange
    'knowledge': Color(0xFF5B7FFF), // Blue-purple
    'discipline': Color(0xFFFFD54F), // Gold-yellow
    'social': Color(0xFF4ECDC4), // Teal-green
  };

  static const Map<String, String> statEmojis = {
    'health': '🏃',
    'knowledge': '📚',
    'discipline': '⚡',
    'social': '🧍',
  };

  static const Map<String, String> badgeNames = {
    'first_quest': 'First Step',
    'first_10_quests': 'On a Roll',
    'quest_master': 'Quest Master',
    'legend': 'Living Legend',
    'level_5': 'Rising Star',
    'level_10': 'Seasoned Warrior',
    'level_20': 'Legendary Hero',
  };

  static const Map<String, String> badgeEmojis = {
    'first_quest': '⭐',
    'first_10_quests': '🔥',
    'quest_master': '👑',
    'legend': '🌟',
    'level_5': '🌱',
    'level_10': '⚔️',
    'level_20': '🏆',
  };

  // Avatar archetypes
  static const List<Map<String, String>> avatarArchetypes = [
    {
      'archetype': 'vegeta',
      'name': 'Vegeta',
      'description':
          'Prince of Saiyans — relentless discipline, driven to be the best.',
      'defaultStat': 'discipline',
      'colorHex': '#3D5AFC',
    },
    {
      'archetype': 'broly',
      'name': 'Broly',
      'description':
          'The Legendary Super Saiyan — raw, unstoppable physical power.',
      'defaultStat': 'health',
      'colorHex': '#43A047',
    },
    {
      'archetype': 'goku',
      'name': 'Goku',
      'description': 'A warrior always hungry to learn the next technique.',
      'defaultStat': 'knowledge',
      'colorHex': '#FF8C1A',
    },
    {
      'archetype': 'roshi',
      'name': 'Master Roshi',
      'description': 'The Turtle Hermit — wise mentor, master of connection.',
      'defaultStat': 'social',
      'colorHex': '#F4B400',
    },
  ];

  // Maps each archetype to its 3D model asset(s), tiered by level. Drop the
  // matching .glb files into assets/models/ (already registered wholesale
  // in pubspec.yaml, so no pubspec change needed for new files there) and
  // add an entry below.
  //
  // Each archetype has a list of (minLevel, path) tiers, ascending by
  // minLevel. AvatarTheme.modelPathFor picks the highest tier the current
  // level qualifies for — e.g. with tiers [(1, v1), (5, v2)], level 4 still
  // gets v1, level 5+ gets v2. Add a third tier the same way if you get a
  // v3 model later.
  //
  // NOTE: _v2TierLevel below is the one number to tune — it's the level a
  // player needs to hit for every archetype's v2 model to kick in. Change
  // it in one place rather than editing every tier list.
  static const int _v2TierLevel = 2;

  static final Map<String, List<AvatarModelTier>> avatarModels = {
    'vegeta': [
      const AvatarModelTier(minLevel: 1, path: 'assets/models/vegeta.glb'),
      AvatarModelTier(
          minLevel: _v2TierLevel, path: 'assets/models/vegetalv2.glb'),
    ],
    'broly': [
      const AvatarModelTier(minLevel: 1, path: 'assets/models/broly.glb'),
      AvatarModelTier(
          minLevel: _v2TierLevel, path: 'assets/models/brolylv2.glb'),
    ],
    'goku': [
      const AvatarModelTier(minLevel: 1, path: 'assets/models/goku.glb'),
      AvatarModelTier(
          minLevel: _v2TierLevel, path: 'assets/models/gokulv2.glb'),
    ],
    'roshi': [
      const AvatarModelTier(minLevel: 1, path: 'assets/models/roshi.glb'),
      AvatarModelTier(
          minLevel: _v2TierLevel, path: 'assets/models/roshilv2.glb'),
    ],
  };

  /// Picks the highest-tier model the given level qualifies for. Falls
  /// back to 'assets/models/default.glb' if the archetype isn't in
  /// [avatarModels] at all, matching AvatarDisplay's previous fallback.
  static String modelPathFor(String archetype, int level) {
    final tiers = avatarModels[archetype];
    if (tiers == null || tiers.isEmpty) return 'assets/models/default.glb';

    // Tiers are declared ascending by minLevel, so the last one the level
    // still qualifies for is the right pick.
    var path = tiers.first.path;
    for (final tier in tiers) {
      if (level >= tier.minLevel) {
        path = tier.path;
      } else {
        break;
      }
    }
    return path;
  }
}

/// A single level-gated model asset for an archetype. See
/// [AvatarTheme.avatarModels] / [AvatarTheme.modelPathFor].
class AvatarModelTier {
  final int minLevel;
  final String path;

  const AvatarModelTier({required this.minLevel, required this.path});
}
