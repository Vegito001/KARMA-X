class UserAvatarProgress {
  final String id;
  final String userId;
  final String? selectedAvatarId;
  final int currentLevel;
  final String? dominantStat;
  final List<String> equippedBadges;
  final DateTime lastUpdated;

  // ── Persisted progress data ─────────────────────────────────────────────
  // These used to live only on-device (SharedPreferences) or reset on every
  // load (hardcoded defaults). They're now real columns on
  // user_avatar_progress, so progress follows the account across logins
  // and devices instead of resetting. Parsed defensively (`as int? ?? 0`)
  // so this model still works against a database that hasn't had the
  // migration in MIGRATION_progress_persistence.sql applied yet.
  final int currentXp;
  final int completedQuests;
  final int healthStat;
  final int knowledgeStat;
  final int disciplineStat;
  final int socialStat;
  final int streakCount;
  final DateTime? lastActiveDate;
  final bool ghostModeUnlocked;

  UserAvatarProgress({
    required this.id,
    required this.userId,
    required this.selectedAvatarId,
    required this.currentLevel,
    required this.dominantStat,
    required this.equippedBadges,
    required this.lastUpdated,
    this.currentXp = 0,
    this.completedQuests = 0,
    this.healthStat = 0,
    this.knowledgeStat = 0,
    this.disciplineStat = 0,
    this.socialStat = 0,
    this.streakCount = 0,
    this.lastActiveDate,
    this.ghostModeUnlocked = false,
  });

  Map<String, int> get stats => {
        'health': healthStat,
        'knowledge': knowledgeStat,
        'discipline': disciplineStat,
        'social': socialStat,
      };

  factory UserAvatarProgress.fromJson(Map<String, dynamic> json) {
    final badgesRaw = json['equipped_badges'];
    List<String> badges = [];
    if (badgesRaw is List) {
      badges = badgesRaw.map((e) => e.toString()).toList();
    } else if (badgesRaw is String) {
      badges = badgesRaw.split(',').where((e) => e.isNotEmpty).toList();
    }

    final lastActiveRaw = json['last_active_date'] as String?;

    return UserAvatarProgress(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      // selected_avatar_id is nullable in the DB (e.g. before a user has
      // picked an avatar, or if their chosen avatar was later removed
      // from the catalog and the FK was set to null) — don't force-cast.
      selectedAvatarId: json['selected_avatar_id'] as String?,
      currentLevel: json['current_level'] as int,
      dominantStat: json['dominant_stat'] as String?,
      equippedBadges: badges,
      lastUpdated: DateTime.parse(json['last_updated'] as String),
      currentXp: json['current_xp'] as int? ?? 0,
      completedQuests: json['completed_quests'] as int? ?? 0,
      healthStat: json['health_stat'] as int? ?? 0,
      knowledgeStat: json['knowledge_stat'] as int? ?? 0,
      disciplineStat: json['discipline_stat'] as int? ?? 0,
      socialStat: json['social_stat'] as int? ?? 0,
      streakCount: json['streak_count'] as int? ?? 0,
      lastActiveDate:
          lastActiveRaw != null ? DateTime.tryParse(lastActiveRaw) : null,
      ghostModeUnlocked: json['ghost_mode_unlocked'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'selected_avatar_id': selectedAvatarId,
      'current_level': currentLevel,
      'dominant_stat': dominantStat,
      'equipped_badges': equippedBadges,
      'last_updated': lastUpdated.toIso8601String(),
      'current_xp': currentXp,
      'completed_quests': completedQuests,
      'health_stat': healthStat,
      'knowledge_stat': knowledgeStat,
      'discipline_stat': disciplineStat,
      'social_stat': socialStat,
      'streak_count': streakCount,
      'last_active_date': lastActiveDate?.toIso8601String(),
      'ghost_mode_unlocked': ghostModeUnlocked,
    };
  }

  UserAvatarProgress copyWith({
    String? id,
    String? userId,
    String? selectedAvatarId,
    int? currentLevel,
    String? dominantStat,
    List<String>? equippedBadges,
    DateTime? lastUpdated,
    int? currentXp,
    int? completedQuests,
    int? healthStat,
    int? knowledgeStat,
    int? disciplineStat,
    int? socialStat,
    int? streakCount,
    DateTime? lastActiveDate,
    bool? ghostModeUnlocked,
  }) {
    return UserAvatarProgress(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      selectedAvatarId: selectedAvatarId ?? this.selectedAvatarId,
      currentLevel: currentLevel ?? this.currentLevel,
      dominantStat: dominantStat ?? this.dominantStat,
      equippedBadges: equippedBadges ?? this.equippedBadges,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      currentXp: currentXp ?? this.currentXp,
      completedQuests: completedQuests ?? this.completedQuests,
      healthStat: healthStat ?? this.healthStat,
      knowledgeStat: knowledgeStat ?? this.knowledgeStat,
      disciplineStat: disciplineStat ?? this.disciplineStat,
      socialStat: socialStat ?? this.socialStat,
      streakCount: streakCount ?? this.streakCount,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
      ghostModeUnlocked: ghostModeUnlocked ?? this.ghostModeUnlocked,
    );
  }
}
