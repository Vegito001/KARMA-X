import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/model_mode.dart';

class ModelModeToggle extends StatefulWidget {
  const ModelModeToggle({super.key});
  @override
  State<ModelModeToggle> createState() => _ModelModeToggleState();
}

class _ModelModeToggleState extends State<ModelModeToggle> {
  Future<void> _handleTap() async {
    await ModelMode.instance.toggle();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final useModal = ModelMode.instance.useModal;
    final accent = useModal ? AppTheme.mana : AppTheme.text400;

    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color:
              useModal ? AppTheme.mana.withValues(alpha: 0.12) : AppTheme.bg700,
          border: Border.all(
            color: useModal ? AppTheme.mana : AppTheme.borderDim,
            width: useModal ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: useModal ? AppTheme.mana : AppTheme.text600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            useModal ? 'KARMAX MODEL (MODAL)' : 'GEMINI (DEFAULT)',
            style: AppTheme.monoFont(size: 9, color: accent, letterSpacing: 1),
          ),
          const SizedBox(width: 8),
          Text(
            'TAP TO SWITCH',
            style: AppTheme.monoFont(
                size: 8, color: AppTheme.text600, letterSpacing: 1),
          ),
        ]),
      ),
    );
  }
}
