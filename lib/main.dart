import 'core/formatters/roster_date_format.dart';
import 'core/services/roster_theme_preference.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/authentication/session_startup.dart';
import 'supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  await RosterThemePreference.load();
  runApp(const RosterBuddyApp());
}

class RosterBuddyApp extends StatelessWidget {
  const RosterBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: RosterThemePreference.mode,
      builder: (context, selectedMode, _) => MaterialApp(
        title: 'Roster Buddy',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [RosterDateLocalizationsDelegate()],
        themeMode: selectedMode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)),
          scaffoldBackgroundColor: const Color(0xFFF4F7FA),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF62B7F6),
            brightness: Brightness.dark,
            surface: const Color(0xFF121D2B),
          ),
          scaffoldBackgroundColor: const Color(0xFF09131F),
          cardTheme: const CardThemeData(
            color: Color(0xFF182637),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF101C2B),
            foregroundColor: Colors.white,
          ),
          bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            backgroundColor: Color(0xFF101C2B),
            selectedItemColor: Color(0xFF67BFFF),
            unselectedItemColor: Color(0xFFB5C2D1),
          ),
        ),
        home: const SessionStartup(),
      ),
    );
  }
}
