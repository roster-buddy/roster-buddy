import 'package:supabase_flutter/supabase_flutter.dart';

enum AppAccessStatus { pending, approved, declined }

class AppAccessService {
  const AppAccessService();

  Future<AppAccessStatus> currentStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return AppAccessStatus.pending;
    final row = await Supabase.instance.client
        .from('app_access')
        .select('status')
        .eq('user_id', user.id)
        .maybeSingle();
    return switch (row?['status']) {
      'approved' => AppAccessStatus.approved,
      'declined' => AppAccessStatus.declined,
      _ => AppAccessStatus.pending,
    };
  }

  Future<bool> isAdministrator() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    final row = await Supabase.instance.client
        .from('app_admins')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();
    return row != null;
  }
}
