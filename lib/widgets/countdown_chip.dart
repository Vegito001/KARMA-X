import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small pill showing time remaining until [target], ticking every second
/// on its own timer so only this chip rebuilds — not the whole quest list.
///
/// Fires [onExpire] exactly once, the moment [target] is reached, so the
/// caller can swap in a fresh set of quests right when the countdown hits
/// zero instead of waiting for the next manual reload.
class CountdownChip extends StatefulWidget {
  final DateTime target;
  final Color color;
  final VoidCallback? onExpire;

  const CountdownChip({
    super.key,
    required this.target,
    required this.color,
    this.onExpire,
  });

  @override
  State<CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<CountdownChip> {
  Timer? _timer;
  late Duration _remaining;
  bool _firedExpire = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.target.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Handle the case where we're constructed already past the target.
    if (_remaining <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
    }
  }

  @override
  void didUpdateWidget(covariant CountdownChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new target (e.g. quests just refreshed) resets the "already fired"
    // guard so the next expiry can fire again.
    if (oldWidget.target != widget.target) {
      _firedExpire = false;
      setState(() => _remaining = widget.target.difference(DateTime.now()));
    }
  }

  void _tick() {
    if (!mounted) return;
    final remaining = widget.target.difference(DateTime.now());
    setState(() => _remaining = remaining);
    if (remaining <= Duration.zero && !_firedExpire) {
      _firedExpire = true;
      widget.onExpire?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    if (d <= Duration.zero) return 'Refreshing…';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (days > 0) {
      return '${days}d ${hours}h left';
    }
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return '$hh:$mm:$ss left';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.10),
        border: Border.all(color: widget.color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 12, color: widget.color),
          const SizedBox(width: 5),
          Text(
            _format(_remaining),
            style: AppTheme.monoFont(size: 10, color: widget.color),
          ),
        ],
      ),
    );
  }
}
