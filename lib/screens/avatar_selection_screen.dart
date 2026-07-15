import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../theme/avatar_theme.dart';
import '../models/avatar.dart';
import '../models/user_avatar_progress.dart';
import '../services/avatar_service.dart';
import '../widgets/avatar_display.dart';
import 'student_problem_screen.dart';

class AvatarSelectionScreen extends StatefulWidget {
  final String? playerName;
  final String? profession;
  final String? schedule;
  final VoidCallback? onComplete;

  const AvatarSelectionScreen({
    super.key,
    this.playerName,
    this.profession,
    this.schedule,
    this.onComplete,
  });

  @override
  State<AvatarSelectionScreen> createState() => _AvatarSelectionScreenState();
}

class _AvatarSelectionScreenState extends State<AvatarSelectionScreen> {
  late Future<List<Avatar>> avatarsFuture;
  String? selectedAvatarId;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAvatars();
  }

  void _loadAvatars() {
    avatarsFuture = AvatarService().getAvailableAvatars();
  }

  void _navigateNext() {
    if (widget.onComplete != null) {
      widget.onComplete!();
    } else if (widget.playerName != null &&
        widget.profession != null &&
        widget.schedule != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StudentProblemScreen(
            playerName: widget.playerName!,
            schedule: widget.schedule!,
          ),
        ),
      );
    }
  }

  Future<void> _selectAvatar() async {
    if (selectedAvatarId == null) {
      _navigateNext();
      return;
    }

    setState(() => isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await AvatarService().selectAvatar(user.id, selectedAvatarId!);
      }
      if (mounted) _navigateNext();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting avatar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg900,
      appBar: AppBar(
        backgroundColor: AppTheme.bg900,
        elevation: 0,
        title: Text(
          '// SELECT YOUR AVATAR',
          style: AppTheme.monoFont(
            size: 12,
            color: AppTheme.text100,
            letterSpacing: 3,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _navigateNext,
            child: Text(
              'SKIP',
              style: AppTheme.monoFont(
                size: 10,
                color: AppTheme.text400,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: AppTheme.scaffoldBackground(),
        child: FutureBuilder<List<Avatar>>(
          future: avatarsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.copper),
              );
            }

            final avatars = snapshot.data ?? [];
            final hasError = snapshot.hasError || avatars.isEmpty;

            if (hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.copper, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      snapshot.hasError
                          ? 'Error loading avatars'
                          : 'No avatars found',
                      style: AppTheme.displayFont(
                        size: 16,
                        color: AppTheme.text100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.hasError
                          ? '${snapshot.error}'
                          : 'The avatars table may be empty or not yet set up.',
                      style: AppTheme.monoFont(
                        size: 9,
                        color: AppTheme.text400,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () => setState(_loadAvatars),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.copper,
                          ),
                          child: Text(
                            'RETRY',
                            style: AppTheme.monoFont(
                              size: 11,
                              color: AppTheme.bg900,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          onPressed: _navigateNext,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.borderDim),
                          ),
                          child: Text(
                            'SKIP FOR NOW',
                            style: AppTheme.monoFont(
                              size: 11,
                              color: AppTheme.text400,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'Choose your character archetype. Your avatar will grow stronger as you complete quests and level up.',
                        style: AppTheme.monoFont(
                          size: 10,
                          color: AppTheme.text200,
                          letterSpacing: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      ...avatars.map((avatar) => _buildAvatarCard(avatar)),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    20,
                    24,
                    MediaQuery.of(context).padding.bottom + 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.bg900.withValues(alpha: 0.88),
                    border: const Border(
                      top: BorderSide(color: AppTheme.borderBright),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _selectAvatar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedAvatarId != null
                            ? AppTheme.copper
                            : AppTheme.bg700,
                        disabledBackgroundColor: AppTheme.bg700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: selectedAvatarId != null
                                ? AppTheme.borderCopper
                                : AppTheme.borderDim,
                          ),
                        ),
                      ),
                      child: Text(
                        isLoading
                            ? 'SAVING...'
                            : selectedAvatarId != null
                                ? 'CONFIRM SELECTION'
                                : 'SKIP FOR NOW',
                        style: AppTheme.monoFont(
                          size: 11,
                          color: selectedAvatarId != null
                              ? AppTheme.bg900
                              : AppTheme.text400,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAvatarCard(Avatar avatar) {
    final isSelected = selectedAvatarId == avatar.id;
    final previewProgress = UserAvatarProgress(
      id: 'preview-${avatar.id}',
      userId: 'preview',
      selectedAvatarId: avatar.id,
      currentLevel: isSelected ? 5 : 1,
      dominantStat: avatar.defaultStat,
      equippedBadges: const [],
      lastUpdated: DateTime.now(),
    );

    return GestureDetector(
      onTap: () => setState(() => selectedAvatarId = avatar.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isSelected
                ? [const Color(0xFF25265C), AppTheme.bg700]
                : [AppTheme.bg800, AppTheme.bg900],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.mana : AppTheme.borderDim,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.mana.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            AvatarDisplay(
              avatar: avatar,
              progress: previewProgress,
              size: 80,
              showBadges: false,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    avatar.name.toUpperCase(),
                    style: AppTheme.displayFont(
                      size: 14,
                      color: AppTheme.text100,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    avatar.description,
                    style: AppTheme.monoFont(
                      size: 9,
                      color: AppTheme.text200,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'DEFAULT: ',
                        style: AppTheme.monoFont(
                          size: 8,
                          color: AppTheme.text400,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        AvatarTheme.statEmojis[avatar.defaultStat] ?? '⭐',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        avatar.defaultStat.toUpperCase(),
                        style: AppTheme.monoFont(
                          size: 8,
                          color: AppTheme.text200,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.mana.withValues(alpha: 0.2),
                ),
                child: const Icon(
                  Icons.check,
                  color: AppTheme.mana,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
