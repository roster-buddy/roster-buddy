import 'package:supabase_flutter/supabase_flutter.dart';

enum AppAccessStatus { pending, approved, declined, renewalRequired }

int subscriptionDaysLeft(DateTime expiry) {
  final remaining = expiry.difference(DateTime.now()).inMilliseconds;
  if (remaining <= 0) return 0;
  return (remaining / Duration.millisecondsPerDay).ceil();
}

class AppAccessService {
  const AppAccessService();

  Future<AppAccessStatus> currentStatus() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return AppAccessStatus.pending;
    final row = await Supabase.instance.client
        .from('app_access')
        .select('status, subscription_expires_at')
        .eq('user_id', user.id)
        .maybeSingle();
    final expiry = DateTime.tryParse(row?['subscription_expires_at'] as String? ?? '');
    return switch (row?['status']) {
      'suspended' => AppAccessStatus.renewalRequired,
      'approved' when expiry != null && !expiry.isAfter(DateTime.now()) =>
        AppAccessStatus.renewalRequired,
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

  Future<DateTime?> subscriptionExpiry() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;
    final row = await client.from('app_access')
        .select('subscription_expires_at')
        .eq('user_id', user.id)
        .maybeSingle();
    return DateTime.tryParse(row?['subscription_expires_at'] as String? ?? '');
  }
}
