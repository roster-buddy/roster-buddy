import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/services/annual_leave_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Exercises the real service and its REST filters against an isolated fixture.
// No production account, leave or email is touched.
void main() {
  late HttpServer server;
  late SupabaseClient client;
  late AnnualLeaveService service;
  late List<Map<String, dynamic>> requests;
  const owner = '00000000-0000-4000-8000-000000000001';

  Map<String, dynamic> leave(String id, String date, String status,
      {String userId = owner, String type = 'floating', bool pending = false}) => {
    'id': id, 'user_id': userId, 'leave_date': date, 'status': status,
    'request_type': type, 'requested_at': '2026-10-30T09:00:00Z',
    'cancellation_pending': pending,
  };

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        final path = request.uri.path;
        Object? result;
        if (path == '/auth/v1/token') {
          final payload = base64Url.encode(utf8.encode(jsonEncode({
            'sub': owner, 'exp': 4102444800,
          }))).replaceAll('=', '');
          result = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.signature',
            'refresh_token': 'fixture-refresh', 'token_type': 'bearer',
            'expires_in': 3600,
            'user': {'id': owner, 'aud': 'authenticated', 'role': 'authenticated',
              'email': 'fixture@example.test', 'app_metadata': {}, 'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z'},
          };
        } else if (path.endsWith('/rpc/action_floating_leave_cancellation')) {
          final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['p_action'], 'confirm');
          for (final row in requests.where((row) => (body['p_ids'] as List).contains(row['id']))) {
            row['status'] = 'cancelled';
            row['cancellation_pending'] = false;
            row['queue_position'] = null;
          }
          result = null;
        } else {
          final rows = path.endsWith('annual_leave_balances')
              ? <Map<String, dynamic>>[{
                  'id': 'balance', 'user_id': owner, 'leave_year': 2026,
                  'entitlement_days': 14, 'starting_balance_days': 14,
                  'bonus_days': 1, 'carry_over_days': 2, 'lieu_days': 1,
                }]
              : requests;
          final matched = rows.where((row) {
            for (final filter in request.uri.queryParametersAll.entries) {
              for (final expression in filter.value) {
              final parts = expression.split('.');
              if (parts.length < 2) continue;
              final expected = parts.skip(1).join('.');
              final actual = row[filter.key]?.toString() ?? '';
              switch (parts.first) {
                case 'eq': if (actual != expected) return false;
                case 'neq': if (actual == expected) return false;
                case 'gte': if (actual.compareTo(expected) < 0) return false;
                case 'lte': if (actual.compareTo(expected) > 0) return false;
                case 'in':
                  if (!expected.replaceAll(RegExp(r'[()]'), '').split(',').contains(actual)) {
                    return false;
                  }
              }
              }
            }
            return true;
          }).toList();
          if (request.method == 'PATCH') {
            final changes = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
            for (final row in matched) { row.addAll(Map<String, dynamic>.from(changes)); }
          }
          result = request.headers.value('accept')?.contains('vnd.pgrst.object') == true
              ? matched.single : matched;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
      } catch (error) {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({'message': '$error'}));
      } finally {
        await request.response.close();
      }
    });
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'fixture-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
    await client.auth.signInWithPassword(email: 'fixture@example.test', password: 'fixture');
    service = AnnualLeaveService(supabase: client);
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('requested and abeyance never deduct; grant deducts; cancellation returns day', () async {
    requests.add(leave('one', '2026-11-25', 'requested'));
    expect((await service.getBalanceForYear(2026)).remainingDays, 18);
    await service.markAbeyance(requestId: 'one', queuePosition: 2);
    expect((await service.getBalanceForYear(2026)).remainingDays, 18);
    await service.markGranted(requestId: 'one');
    expect((await service.getBalanceForYear(2026)).remainingDays, 17);
    expect(requests.single['queue_position'], isNull);
    requests.single['cancellation_pending'] = true;
    expect((await service.getBalanceForYear(2026)).remainingDays, 17);
    expect(await service.getPendingFloatingRequests(), hasLength(1));
    await service.cancelRequest(requestId: 'one');
    expect((await service.getBalanceForYear(2026)).remainingDays, 18);
    expect(await service.getPendingFloatingRequests(), isEmpty);
    expect(await service.getRequestsForRange(DateTime(2026, 11, 25), DateTime(2026, 11, 25)), isEmpty);
  });

  test('balance excludes other years, block leave and another account', () async {
    requests.addAll([
      leave('first', '2026-01-01', 'granted'),
      leave('last', '2026-12-31', 'granted'),
      leave('next', '2027-01-01', 'granted'),
      leave('prior', '2025-12-31', 'granted'),
      leave('block', '2026-06-01', 'granted', type: 'block'),
      leave('other', '2026-06-02', 'granted', userId: 'other-account'),
      leave('waiting', '2026-06-03', 'requested'),
      leave('queue', '2026-06-04', 'abeyance'),
      leave('cancelled', '2026-06-05', 'cancelled'),
    ]);
    final balance = await service.getBalanceForYear(2026);
    expect(balance.committedDays, 2);
    expect(balance.remainingDays, 16);
  });
}
