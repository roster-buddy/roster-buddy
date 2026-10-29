import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared identity line for roster, leave, union and future email templates.
/// Roster numbers identify a roster line; they must not replace a driver number.
Future<String> driverNumberEmailLine() async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;
  if (user == null) return '';
  final profile = await client.from('driver_profiles').select('driver_number')
      .eq('user_id', user.id).maybeSingle();
  final number = (profile?['driver_number'] ?? user.userMetadata?['driver_number'] ?? '').toString().trim();
  return number.isEmpty ? '' : 'Driver Number: $number';
}
