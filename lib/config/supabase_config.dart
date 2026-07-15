import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseConfig {
  static const String _urlEnv = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKeyEnv = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _projectRefEnv =
      String.fromEnvironment('SUPABASE_PROJECT_REF');

  static String get anonKey {
    final fromDefine = _anonKeyEnv.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    return _normalizeValue(_lookupDotenv('SUPABASE_ANON_KEY'));
  }

  static String get projectRef {
    final fromDefine = _projectRefEnv.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    return _normalizeValue(_lookupDotenv('SUPABASE_PROJECT_REF'));
  }

  static String get url {
    final fromDefine = _urlEnv.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    return _normalizeValue(_lookupDotenv('SUPABASE_URL'));
  }

  static String get resolvedUrl {
    if (url.isNotEmpty) return _normalizeUrl(url);
    if (projectRef.isNotEmpty) return 'https://$projectRef.supabase.co';
    return '';
  }

  static bool get isConfigured => resolvedUrl.isNotEmpty && anonKey.isNotEmpty;

  static String get missingConfigMessage =>
      'Supabase is not configured. Run with --dart-define=SUPABASE_URL=... '
      '(or --dart-define=SUPABASE_PROJECT_REF=...) and --dart-define=SUPABASE_ANON_KEY=...';

  static String _normalizeUrl(String input) {
    final trimmed = input.trim();

    // If user accidentally pastes the dashboard URL, convert it.
    // Example: https://supabase.com/dashboard/project/<ref>
    const marker = '/dashboard/project/';
    final idx = trimmed.indexOf(marker);
    if (idx != -1) {
      final ref = trimmed.substring(idx + marker.length).split('/').first;
      if (ref.isNotEmpty) return 'https://$ref.supabase.co';
    }

    // If they pass just the ref, convert it.
    final looksLikeRef = RegExp(r'^[a-z0-9]{20}$').hasMatch(trimmed);
    if (looksLikeRef) return 'https://$trimmed.supabase.co';

    return trimmed;
  }

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
}
