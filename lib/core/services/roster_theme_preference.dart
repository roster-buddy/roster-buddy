import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// System by default; a saved user selection overrides the device appearance.
class RosterThemePreference {
  RosterThemePreference._();

  static const String _key = 'roster_buddy_theme_mode';
  static final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    mode.value = _fromStored(preferences.getString(_key));
  }

  static ThemeMode _fromStored(String? stored) {
    switch (stored) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static Future<void> setMode(ThemeMode selection) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, selection.name);
    mode.value = selection;
  }
}
