import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'config/supabase_config.dart';
import 'utils/model_mode.dart';

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

  WidgetsFlutterBinding.ensureInitialized();
  await ModelMode.instance.load(); // restores last switch position

  // Load local env (optional). If missing, --dart-define still works.
  // NOTE: dotenv.load() REPLACES the entire env map each time it's
  // called successfully — it does not merge across calls, so whichever
  // load below succeeds LAST is the one that actually takes effect.
  try {
    await dotenv.load(fileName: 'assets/.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'assets/.env.local');
    } catch (_) {
      try {
        await dotenv.load(fileName: '.env.local');
      } catch (_) {
        // No .env file found — relying entirely on --dart-define values.
      }
    }
  }

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.resolvedUrl,
      anonKey: SupabaseConfig.anonKey,
    );
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
