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
      'archetype': 'knight',
      'name': 'Noble Knight',
      'description': 'A steadfast warrior, strong in discipline and honor.',
      'defaultStat': 'discipline',
      'colorHex': '#FFD54F',
    },
    {
      'archetype': 'sage',
      'name': 'Mystic Sage',
      'description': 'A seeker of knowledge, mastering the arcane arts.',
      'defaultStat': 'knowledge',
      'colorHex': '#5B7FFF',
    },
    {
      'archetype': 'rogue',
      'name': 'Swift Rogue',
      'description': 'Quick and cunning, balanced in all aspects.',
      'defaultStat': 'social',
      'colorHex': '#4ECDC4',
    },
    {
      'archetype': 'guardian',
      'name': 'Steadfast Guardian',
      'description': 'Protector of wellness, radiating vitality.',
      'defaultStat': 'health',
      'colorHex': '#FF6B4A',
    },
    {
      'archetype': 'mage',
      'name': 'Arcane Mage',
      'description': 'Master of mystical forces and transformation.',
      'defaultStat': 'knowledge',
      'colorHex': '#9D5FFF',
    },
    {
      'archetype': 'druid',
      'name': 'Natural Druid',
      'description': 'Harmonious with nature, balanced and resilient.',
      'defaultStat': 'health',
      'colorHex': '#52C977',
    },
  ];
}
