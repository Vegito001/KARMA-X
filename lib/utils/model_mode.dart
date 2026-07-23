import 'package:shared_preferences/shared_preferences.dart';

/// Global switch: Modal (your fine-tuned karmax LoRA) vs Gemini (default/fallback).
/// When useModal is false, AiService NEVER calls Modal — zero credits used.
class ModelMode {
  ModelMode._();
  static final ModelMode instance = ModelMode._();

  static const _prefsKey = 'use_modal_model';

  bool useModal = false;
  bool _loaded = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    useModal = prefs.getBool(_prefsKey) ?? false;
    _loaded = true;
  }

  Future<void> toggle() async {
    useModal = !useModal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, useModal);
  }

  bool get isLoaded => _loaded;
}