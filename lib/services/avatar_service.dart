import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/avatar.dart';
import '../models/user_avatar_progress.dart';

/// Handles all Supabase reads/writes for the avatar system:
/// - the `avatars` reference table (publicly readable catalog of archetypes)
/// - the `user_avatar_progress` table (one row per user, their selection +
///   level/stat/badge progress)
class AvatarService {
  final _db = Supabase.instance.client;

  // ── CATALOG ────────────────────────────────────────────────────────────
  /// Returns every avatar option in the catalog. Publicly readable —
  /// no auth required, matches the "avatars are publicly readable" RLS
  /// policy on the table.
  Future<List<Avatar>> getAvailableAvatars() async {
    final rows = await _db.from('avatars').select().order('created_at');
    return rows.map((row) => Avatar.fromJson(row)).toList();
  }

  /// Fetch a single avatar by id. Returns null if not found.
  Future<Avatar?> getAvatarById(String? avatarId) async {
    if (avatarId == null || avatarId.isEmpty) return null;
    final row =
        await _db.from('avatars').select().eq('id', avatarId).maybeSingle();
    if (row == null) return null;
    return Avatar.fromJson(row);
  }

  // ── USER PROGRESS ──────────────────────────────────────────────────────
  /// Fetch the current user's avatar progress row. Returns null if the
  /// user hasn't selected an avatar yet (no row exists).
  Future<UserAvatarProgress?> getUserAvatarProgress(String userId) async {
    final row = await _db
        .from('user_avatar_progress')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return UserAvatarProgress.fromJson(row);
  }

  /// Create or update the user's avatar selection. Called when a user
  /// picks an avatar during onboarding or changes it later.
  ///
  /// Uses upsert with onConflict on user_id, so this is safe to call
  /// whether or not a progress row already exists for this user.
  Future<void> selectAvatar(String userId, String avatarId) async {
    // Look up the avatar's default stat so a brand-new progress row
    // starts with a sensible dominant_stat instead of null.
    final avatar = await getAvatarById(avatarId);

    final existing = await getUserAvatarProgress(userId);

    await _db.from('user_avatar_progress').upsert(
      {
        'user_id': userId,
        'selected_avatar_id': avatarId,
        'current_level': existing?.currentLevel ?? 1,
        'dominant_stat': existing?.dominantStat ?? avatar?.defaultStat,
        'equipped_badges': existing?.equippedBadges ?? <String>[],
        'last_updated': DateTime.now().toIso8601String(),
        'current_xp': existing?.currentXp ?? 0,
        'completed_quests': existing?.completedQuests ?? 0,
        'health_stat': existing?.healthStat ?? 0,
        'knowledge_stat': existing?.knowledgeStat ?? 0,
        'discipline_stat': existing?.disciplineStat ?? 0,
        'social_stat': existing?.socialStat ?? 0,
        'streak_count': existing?.streakCount ?? 0,
        'last_active_date': existing?.lastActiveDate?.toIso8601String(),
        'ghost_mode_unlocked': existing?.ghostModeUnlocked ?? false,
      },
      onConflict: 'user_id',
    );
  }

  /// Bump the user's avatar level (e.g. after enough quests completed).
  Future<void> updateLevel(String userId, int newLevel) async {
    await _db.from('user_avatar_progress').update({
      'current_level': newLevel,
      'last_updated': DateTime.now().toIso8601String(),
    }).eq('user_id', userId);
  }

  /// Persist the full set of run-time progress in one round trip: level,
  /// XP, completed-quest count, the four growth stats, and the streak /
  /// ghost-mode data. Replaces what used to be several separate calls
  /// (updateLevel + updateDominantStat) plus on-device-only
  /// SharedPreferences writes for XP, quests, stats, and streak — all of
  /// that now lives in user_avatar_progress and follows the account across
  /// logins and devices.
  Future<void> saveProgressSnapshot(
    String userId, {
    required int level,
    required int currentXp,
    required int completedQuests,
    required Map<String, int> stats,
    required int streak,
    required DateTime lastActiveDate,
    required bool ghostModeUnlocked,
  }) async {
    final dominant = stats.isEmpty
        ? null
        : stats.entries.reduce((a, b) => b.value > a.value ? b : a).key;

    await _db.from('user_avatar_progress').update({
      'current_level': level,
      'current_xp': currentXp,
      'completed_quests': completedQuests,
      'health_stat': stats['health'] ?? 0,
      'knowledge_stat': stats['knowledge'] ?? 0,
      'discipline_stat': stats['discipline'] ?? 0,
      'social_stat': stats['social'] ?? 0,
      'streak_count': streak,
      'last_active_date': lastActiveDate.toIso8601String(),
      'ghost_mode_unlocked': ghostModeUnlocked,
      if (dominant != null) 'dominant_stat': dominant,
      'last_updated': DateTime.now().toIso8601String(),
    }).eq('user_id', userId);
  }

  /// Recompute and persist the user's dominant stat — whichever stat in
  /// the given map currently has the highest value. Called after quest
  /// completion so the avatar's "dominant_stat" stays in sync with the
  /// player's actual stat distribution.
  Future<void> updateDominantStat(
    String userId,
    Map<String, int> stats,
  ) async {
    if (stats.isEmpty) return;

    final dominant =
        stats.entries.reduce((a, b) => b.value > a.value ? b : a).key;

    await _db.from('user_avatar_progress').update({
      'dominant_stat': dominant,
      'last_updated': DateTime.now().toIso8601String(),
    }).eq('user_id', userId);
  }

  /// Pure function — given the player's current level and completed quest
  /// count, returns the list of badge ids that should be unlocked. Does
  /// not touch the database; pair with updateBadges() to persist.
  List<String> checkBadgesUnlocked(int level, int completedQuests) {
    final badges = <String>[];

    if (completedQuests >= 1) badges.add('first_blood');
    if (completedQuests >= 10) badges.add('iron_will');
    if (completedQuests >= 50) badges.add('apex_node');
    if (level >= 5) badges.add('rising_star');
    if (level >= 10) badges.add('apex_node_lvl');
    if (level >= 20) badges.add('champion');

    return badges;
  }

  /// Merge the given badge ids into the user's equipped_badges (union —
  /// never removes existing badges), then persist.
  Future<void> updateBadges(String userId, List<String> badgeIds) async {
    if (badgeIds.isEmpty) return;

    final existing = await getUserAvatarProgress(userId);
    final merged = {
      ...(existing?.equippedBadges ?? <String>[]),
      ...badgeIds,
    }.toList();

    await _db.from('user_avatar_progress').update({
      'equipped_badges': merged,
      'last_updated': DateTime.now().toIso8601String(),
    }).eq('user_id', userId);
  }

  /// Add a single badge to the user's equipped badges, if not already
  /// present. Thin convenience wrapper around updateBadges().
  Future<void> addBadge(String userId, String badge) async {
    await updateBadges(userId, [badge]);
  }
}
