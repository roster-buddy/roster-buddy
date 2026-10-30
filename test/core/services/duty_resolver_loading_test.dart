import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/services/duty_resolver.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('range reads start concurrently and still resolve the correct driver', () async {
    const owner = '00000000-0000-4000-8000-000000000001';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final release = Completer<void>();
    var reads = 0;
    server.listen((request) async {
      try {
        Object result;
        if (request.uri.path == '/auth/v1/token') {
          final payload = base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'exp': 4102444800}))).replaceAll('=', '');
          result = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
            'refresh_token': 'fixture-refresh', 'token_type': 'bearer', 'expires_in': 3600,
            'user': {'id': owner, 'aud': 'authenticated', 'role': 'authenticated',
              'email': 'fixture@example.test', 'app_metadata': {}, 'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z'},
          };
        } else if (request.uri.path.endsWith('driver_profiles')) {
          final profile = {'payroll_number': '21910', 'roster_number': '3524',
            'driver_number': '3167', 'permanently_unavailable_sundays': true};
          result = request.headers.value('accept')?.contains('vnd.pgrst.object') == true
              ? profile : [profile];
        } else {
          reads++;
          // A serial loader cannot reach this barrier; parallel reads can.
          if (reads >= 6 && !release.isCompleted) release.complete();
          await release.future;
          result = request.uri.path.endsWith('document_duties') ? [
            {'duty_date': '2026-11-25', 'source': '48_hour', 'duty_type': 'working',
              'turn_number': '204', 'payroll_number': '21910', 'book_on': '04:25', 'book_off': '12:58'},
            {'duty_date': '2026-11-25', 'source': '48_hour', 'duty_type': 'working',
              'turn_number': '999', 'payroll_number': 'other-driver'},
          ] : [];
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      } finally { await request.response.close(); }
    });
    final client = SupabaseClient('http://127.0.0.1:${server.port}', 'fixture-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    try {
      await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture');
      final result = await DutyResolver(supabase: client)
          .getResolvedDutiesForRange(DateTime(2026, 11, 23), DateTime(2026, 11, 28))
          .timeout(const Duration(seconds: 8));
      expect(reads, 7);
      expect(result['2026-11-25']?.turnNumber, '204');
      expect(result['2026-11-25']?.bookOn, '04:25');
    } finally {
      if (!release.isCompleted) release.complete();
      await client.dispose();
      await server.close(force: true);
    }
  });
}
