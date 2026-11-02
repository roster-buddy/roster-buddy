import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:roster_buddy/core/models/document_type.dart';
import 'package:roster_buddy/core/models/duty.dart';
import 'package:roster_buddy/core/models/duty_type.dart';
import 'package:roster_buddy/core/models/parse_result.dart';
import 'package:roster_buddy/core/models/roster_source.dart';
import 'package:roster_buddy/features/upload/document_processing_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FixtureHttp extends HttpOverrides {}

class _FixtureStorage extends GotrueAsyncStorage {
  const _FixtureStorage();
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reviewed import sends exact records once through atomic RPC and propagates failure',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <String>[];
        Map<String, dynamic>? payload;
        var rejectRpc = false;
        server.listen((request) async {
          requests.add('${request.method} ${request.uri.path}');
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path.endsWith('replace_document_import')) {
            payload =
                jsonDecode(await utf8.decoder.bind(request).join())
                    as Map<String, dynamic>;
            if (rejectRpc) {
              request.response.statusCode = 400;
              request.response.write(
                jsonEncode({
                  'code': '23514',
                  'message': 'Fixture replacement failed',
                }),
              );
            } else {
              request.response.write('1');
            }
          } else {
            expect(request.method, 'PATCH');
            expect(
              request.uri.queryParameters['processing_status'],
              'neq.processed',
            );
            request.response.write('[]');
          }
          await request.response.close();
        });
        await Supabase.initialize(
          url: 'http://127.0.0.1:${server.port}',
          publishableKey: 'fixture',
          authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage(),
            pkceAsyncStorage: _FixtureStorage(),
          ),
        );
        final reviewed = ParseResult(
          documentType: DocumentType.fortyEightHourAmendment,
          duties: [
            Duty(
              date: DateTime(2026, 8, 3),
              source: RosterSource.fortyEightHour,
              dutyType: DutyType.working,
              payrollNumber: '21910',
              turnNumber: '204',
              bookOn: '04:25',
              bookOff: '12:58',
            ),
          ],
        );
        Future<DocumentProcessingResult> commit(DocumentType type) =>
            DocumentProcessingService.processUploadedDocument(
              documentId: 'fixture-document',
              bytes: Uint8List.fromList([1]),
              originalFilename: 'photo.jpg',
              documentType: type,
              reviewedResult: reviewed,
            );
        try {
          // Invalid image bytes prove that confirmation reuses the reviewed parse
          // and does not rerun OCR on the device.
          final result = await commit(DocumentType.fortyEightHourAmendment);
          expect(result.wasProcessed, isTrue);
          expect(result.recordsInserted, 1);
          expect(payload!['p_document_id'], 'fixture-document');
          expect(payload!['p_kind'], 'duties');
          final row = (payload!['p_rows'] as List).single as Map;
          expect(row['payroll_number'], '21910');
          expect(row['duty_date'], '2026-08-03');
          expect(row['turn_number'], '204');
          expect(row['book_on'], '04:25:00');
          expect(row['book_off'], '12:58:00');
          expect(requests, [
            'PATCH /rest/v1/roster_documents',
            'POST /rest/v1/rpc/replace_document_import',
          ]);

          requests.clear();
          await expectLater(
            commit(DocumentType.sevenDayAmendment),
            throwsA(isA<DocumentProcessingException>()),
          );
          expect(requests, isEmpty);

          rejectRpc = true;
          await expectLater(
            commit(DocumentType.fortyEightHourAmendment),
            throwsA(
              isA<DocumentProcessingException>().having(
                (e) => e.message,
                'message',
                'Fixture replacement failed',
              ),
            ),
          );
          expect(requests.where((r) => r.startsWith('DELETE')), isEmpty);
          expect(requests.where((r) => r.contains('/rpc/')).length, 1);
        } finally {
          await Supabase.instance.dispose();
          await server.close(force: true);
        }
      }, _FixtureHttp());
    },
  );
}
