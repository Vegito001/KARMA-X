import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'config/supabase_config.dart';

void probeDefines() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  const ref = String.fromEnvironment('SUPABASE_PROJECT_REF');

  debugPrint('--- DART-DEFINE PROBE ---');
  debugPrint('SUPABASE_URL define = "$url" (length ${url.length})');
  debugPrint('SUPABASE_ANON_KEY define = "$key" (length ${key.length})');
  debugPrint('SUPABASE_PROJECT_REF define = "$ref" (length ${ref.length})');
  debugPrint('-------------------------');
}

Future<void> main() async {
  // google_fonts normally fetches font files over the network the first
  // time each style is used (Cinzel, Share Tech Mono, Inter, Cinzel
  // Decorative — all 4 fonts this app uses). If that fetch is blocked,
  // slow, or fails in the current environment, affected text can end up
  // rendering invisibly while surrounding box decorations (which don't
  // need a font) still show — which matches the "blank quest card"
  // symptom exactly. Disabling runtime fetching makes every GoogleFonts.*
  // call resolve IMMEDIATELY to the safe system fallback font instead of
  // waiting on a network call that might never resolve, so text is always
  // visible even if it's not in the intended branded font.
  GoogleFonts.config.allowRuntimeFetching = false;

  probeDefines();
  WidgetsFlutterBinding.ensureInitialized();

  // Load local env (optional). If missing, --dart-define still works.
  // NOTE: dotenv.load() REPLACES the entire env map each time it's
  // called successfully — it does not merge across calls. So whichever
  // load below succeeds LAST is the one that actually takes effect.
  bool loadedAny = false;

  try {
    await dotenv.load(fileName: 'assets/.env');
    debugPrint('✓ dotenv loaded from assets/.env');
    debugPrint('  → SUPABASE_URL=${dotenv.env['SUPABASE_URL']}');
    debugPrint('  → SUPABASE_ANON_KEY=${dotenv.env['SUPABASE_ANON_KEY']}');
    loadedAny = true;
  } catch (e) {
    debugPrint('✗ assets/.env load failed: $e');
  }

  try {
    await dotenv.load(fileName: 'assets/.env.local');
    debugPrint(
        '✓ dotenv loaded from assets/.env.local (THIS WINS if it succeeded)');
    debugPrint('  → SUPABASE_URL=${dotenv.env['SUPABASE_URL']}');
    debugPrint('  → SUPABASE_ANON_KEY=${dotenv.env['SUPABASE_ANON_KEY']}');
    loadedAny = true;
  } catch (e) {
    debugPrint('✗ assets/.env.local load failed: $e');
    try {
      await dotenv.load(fileName: '.env.local');
      debugPrint(
          '✓ dotenv loaded from .env.local (non-asset path, THIS WINS if it succeeded)');
      debugPrint('  → SUPABASE_URL=${dotenv.env['SUPABASE_URL']}');
      debugPrint('  → SUPABASE_ANON_KEY=${dotenv.env['SUPABASE_ANON_KEY']}');
      loadedAny = true;
    } catch (e2) {
      debugPrint('✗ .env.local load failed: $e2');
    }
  }

  if (!loadedAny) {
    debugPrint('⚠ NO .env file was successfully loaded — relying entirely '
        'on --dart-define values, if any.');
  }

  debugPrint('Supabase configured: ${SupabaseConfig.isConfigured}');
  debugPrint('Supabase URL: ${SupabaseConfig.resolvedUrl}');
  debugPrint(
      'Supabase Anon Key: ${SupabaseConfig.anonKey.isNotEmpty ? '✓ loaded' : '✗ missing'}');

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.resolvedUrl,
      anonKey: SupabaseConfig.anonKey,
    );
    debugPrint('Supabase initialized successfully');
  } else {
    debugPrint(SupabaseConfig.missingConfigMessage);
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bg900,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const KarmaXApp());
}

class KarmaXApp extends StatelessWidget {
  const KarmaXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KarmaX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
