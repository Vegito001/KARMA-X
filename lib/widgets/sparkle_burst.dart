import 'dart:math' as math;
import 'package:flutter/material.dart';

/// One-shot radial burst of small sparkle glyphs, fired by calling
/// [SparkleBurstController.fire]. Used to give a bit of tactile "juice" to
/// taps on the avatar — purely decorative, no game-state effect.
class SparkleBurstController {
  _SparkleBurstState? _state;

  void _attach(_SparkleBurstState state) => _state = state;

  void fire() => _state?._fire();
}

class SparkleBurst extends StatefulWidget {
  final SparkleBurstController controller;
  final Color color;
  final double size;

  const SparkleBurst({
    super.key,
    required this.controller,
    required this.color,
    this.size = 200,
  });

  @override
  State<SparkleBurst> createState() => _SparkleBurstState();
}

class _SparkleBurstState extends State<SparkleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  static const _glyphs = ['✦', '✧', '⋆', '✺'];
  final _rand = math.Random();
  List<double> _angles = [];
  List<double> _glyphPick = [];

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  void _fire() {
    _angles = List.generate(
      10,
      (_) => _rand.nextDouble() * 2 * math.pi,
    );
    _glyphPick = List.generate(10, (_) => _rand.nextDouble());
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          if (_ctrl.value == 0 || _angles.isEmpty) {
            return const SizedBox.shrink();
          }
          final progress = Curves.easeOut.transform(_ctrl.value);
          final fade = 1.0 - Curves.easeIn.transform(_ctrl.value);
          final travel = widget.size * 0.5 * progress;

          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < _angles.length; i++)
                  Transform.translate(
                    offset: Offset(
                      math.cos(_angles[i]) * travel,
                      math.sin(_angles[i]) * travel,
                    ),
                    child: Opacity(
                      opacity: fade.clamp(0.0, 1.0),
                      child: Text(
                        _glyphs[(_glyphPick[i] * _glyphs.length).floor() %
                            _glyphs.length],
                        style: TextStyle(
                          color: widget.color,
                          fontSize: 10 + _glyphPick[i] * 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
