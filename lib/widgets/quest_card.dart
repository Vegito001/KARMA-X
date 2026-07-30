import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class QuestCard extends StatefulWidget {
  final String title;
  final String xpReward;
  final String category;
  final bool completed;
  final VoidCallback? onComplete;
  final int index;
  // One-line "why" description tying the quest back to the student's
  // problem — optional because manually-created quests may not have one.
  final String? description;
  // Set to false once the quest's daily/weekly batch has expired — the
  // card stays visible for reference but can no longer be tapped complete.
  final bool enabled;

  const QuestCard({
    super.key,
    required this.title,
    required this.xpReward,
    required this.category,
    this.completed = false,
    this.onComplete,
    this.index = 0,
    this.description,
    this.enabled = true,
  });

  @override
  State<QuestCard> createState() => _QuestCardState();
}

class _QuestCardState extends State<QuestCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideIn;
  bool _localCompleted = false;

  @override
  void initState() {
    super.initState();
    _localCompleted = widget.completed;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(
      begin: const Offset(0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant QuestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep local visual state in sync with the real data. This matters
    // whenever the same State object gets reused for what is logically a
    // different completed value — e.g. the underlying quest list reloads
    // from Supabase (a fresh generation replacing the old one) rather than
    // going through _handleComplete's tap flow.
    if (widget.completed != oldWidget.completed) {
      setState(() => _localCompleted = widget.completed);
    }
  }

  void _handleComplete() {
    setState(() => _localCompleted = true);
    widget.onComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    final categoryColor = _categoryColor(widget.category);

    return FadeTransition(
      opacity: _fadeIn,
      child: SlideTransition(
        position: _slideIn,
        child: GestureDetector(
          onTap: (!widget.enabled || _localCompleted) ? null : _handleComplete,
          child: AnimatedOpacity(
            opacity: widget.enabled ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 300),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.questCard(completed: _localCompleted),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _localCompleted
                          ? AppTheme.copper
                          : categoryColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: _localCompleted
                            ? AppTheme.copper
                            : categoryColor.withValues(alpha: 0.58),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_localCompleted
                                  ? AppTheme.copper
                                  : categoryColor)
                              .withValues(alpha: 0.16),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: _localCompleted
                        ? const Icon(Icons.check,
                            size: 15, color: AppTheme.bg900)
                        : Icon(
                            Icons.auto_awesome,
                            size: 15,
                            color: categoryColor,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: AppTheme.uiFont(
                            size: 14,
                            weight: FontWeight.w700,
                            color: _localCompleted
                                ? AppTheme.text400
                                : AppTheme.text100,
                          ).copyWith(
                            decoration: _localCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: AppTheme.text400,
                          ),
                        ),
                        if (widget.description != null &&
                            widget.description!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.uiFont(
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: _localCompleted
                                  ? AppTheme.text600
                                  : AppTheme.text400,
                            ).copyWith(height: 1.3),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: categoryColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        categoryColor.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _categoryLabel(widget.category),
                              style: AppTheme.uiFont(
                                size: 11,
                                weight: FontWeight.w600,
                                color: categoryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _localCompleted ? 0.35 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _localCompleted
                            ? AppTheme.bg700
                            : AppTheme.copper.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.copper.withValues(alpha: 0.16),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Text(
                        '+${widget.xpReward} XP',
                        style: AppTheme.uiFont(
                          size: 11,
                          weight: FontWeight.w800,
                          color: _localCompleted
                              ? AppTheme.text400
                              : AppTheme.bg900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'health':
        return AppTheme.danger;
      case 'knowledge':
        return AppTheme.xpBlue;
      case 'discipline':
        return AppTheme.copper;
      case 'social':
        return AppTheme.mana;
      default:
        return AppTheme.text200;
    }
  }

  String _categoryLabel(String category) {
    if (category.isEmpty) return 'General';
    return '${category[0].toUpperCase()}${category.substring(1).toLowerCase()}';
  }
}
