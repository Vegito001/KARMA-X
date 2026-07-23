import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Resolves the Gemini API key the same way [SupabaseConfig] resolves the
/// Supabase credentials: prefer a --dart-define value (best for CI/release
/// builds), falling back to whatever .env file flutter_dotenv managed to
/// load at startup (see main.dart). The key itself never lives in source
/// control — only in the gitignored .env files or as a build-time define.
class AiConfig {
  static const String _apiKeyEnv = String.fromEnvironment('GEMINI_API_KEY');

  static String get apiKey {
    final fromDefine = _apiKeyEnv.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    return _normalizeValue(_lookupDotenv('GEMINI_API_KEY'));
  }

  static bool get isConfigured => apiKey.isNotEmpty;

  static String get missingConfigMessage =>
      'GEMINI_API_KEY is not configured. Add it to assets/.env (see '
      'assets/.env.example) or run with --dart-define=GEMINI_API_KEY=...';

  static String _lookupDotenv(String key) {
    try {
      final normalizedKey = key.trim().toUpperCase();
      for (final entry in dotenv.env.entries) {
        if (entry.key.trim().toUpperCase() == normalizedKey) {
          return entry.value;
        }
      }
    } catch (_) {
      return '';
    }
    return '';
  }

  static String _normalizeValue(String value) {
    var v = value.trim();
    if (v.length >= 2) {
      final startsQuote = v.startsWith('"') || v.startsWith("'");
      final endsQuote = v.endsWith('"') || v.endsWith("'");
      if (startsQuote && endsQuote) {
        v = v.substring(1, v.length - 1).trim();
      }
    }
    return v;
  }

  // ── NEW: your Modal vLLM endpoint ─────────────────────────────────────
  static const String modalUrl =
      'https://sgogeta997--karmax-lora-vllm-serve.modal.run/v1/chat/completions';
}