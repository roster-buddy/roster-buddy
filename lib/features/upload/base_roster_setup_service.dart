import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/parser/base_roster_parser.dart';
import 'storage_service.dart';

class PendingBaseRosterSetup {
  const PendingBaseRosterSetup({
    required this.documentId,
    required this.fileName,
    required this.officialStartDate,
    required this.pages,
  });

  final String documentId;
  final String fileName;
  final DateTime officialStartDate;
  final List<String> pages;
}

class BaseRosterSetupService {
  BaseRosterSetupService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<PendingBaseRosterSetup?> loadPending() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final profile = await _client
        .from('driver_profiles')
        .select('depot')
        .eq('user_id', user.id)
        .maybeSingle();
    final depot = (profile?['depot'] ?? '').toString().trim().toLowerCase();
    if (depot.isEmpty) return null;

    final document = await _client
        .from('roster_documents')
        .select(
          'id, original_filename, base_roster_commencement, '
          'base_roster_pages, created_at',
        )
        .eq('depot', depot)
        .eq('detected_type', 'base_roster')
        .eq('processing_status', 'processed')
        .not('base_roster_commencement', 'is', null)
        .order('base_roster_commencement', ascending: false)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (document == null) return null;

    final documentId = document['id'].toString();
    final existing = await _client
        .from('base_rosters')
        .select('id')
        .eq('user_id', user.id)
        .eq('document_id', documentId)
        .maybeSingle();
    if (existing != null) return null;

    final officialStartDate = DateTime.tryParse(
      (document['base_roster_commencement'] ?? '').toString(),
    );
    final pages = (document['base_roster_pages'] as List?)
        ?.map((value) => value.toString())
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (officialStartDate == null || pages == null || pages.isEmpty) return null;

    return PendingBaseRosterSetup(
      documentId: documentId,
      fileName: (document['original_filename'] ?? 'Base Roster').toString(),
      officialStartDate: officialStartDate,
      pages: pages,
    );
  }

  Future<void> activate({
    required PendingBaseRosterSetup action,
    required BaseRosterActivation setup,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in to set up the Base Roster.');
    if (setup.commencementDate.isBefore(action.officialStartDate)) {
      throw StateError('Your starting Sunday cannot be before the roster starts.');
    }

    final profile = await _client
        .from('driver_profiles')
        .select('roster_number, driver_number')
        .eq('user_id', user.id)
        .single();
    final rosterNumber =
        (profile['roster_number'] ?? profile['driver_number'] ?? '')
            .toString()
            .trim();
    if (rosterNumber.isEmpty) {
      throw StateError('Add your roster number before setting up this roster.');
    }

    final result = await BaseRosterParser(
      commencementDate: setup.commencementDate,
      rosterNumber: rosterNumber,
      startWeekNumber: setup.startWeekNumber,
      swapPartnerWeekNumber: setup.swapPartnerWeekNumber,
      initialLine: setup.startingLine == BaseRosterStartingLine.partner
          ? BaseRosterInitialLine.swapPartner
          : BaseRosterInitialLine.driver,
    ).parse(pageText: action.pages);
    if (!result.canImport) {
      final message = result.warnings
          .where((warning) => warning.preventsImport)
          .map((warning) => warning.message)
          .join('\n');
      throw StateError(
        message.isEmpty ? 'The selected roster line could not be read.' : message,
      );
    }

    await _client.from('base_rosters').upsert({
      'user_id': user.id,
      'document_id': action.documentId,
      'commencement_date': _databaseDate(setup.commencementDate),
      'has_mutual_swap': setup.hasMutualSwap,
      'start_week_number': setup.startWeekNumber,
      'swap_partner_week_number': setup.hasMutualSwap
          ? setup.swapPartnerWeekNumber
          : null,
      'swap_partner_driver_number': null,
      'swap_partner_roster_number': null,
      'starts_with_line': setup.hasMutualSwap
          ? setup.startingLine.name
          : BaseRosterStartingLine.mine.name,
    }, onConflict: 'user_id,document_id');

    await _client.from('driver_profiles').update({
      'base_roster_commencement_date': _databaseDate(setup.commencementDate),
      'has_mutual_roster_swap': setup.hasMutualSwap,
      'base_roster_starts_with_line': setup.hasMutualSwap
          ? setup.startingLine.name
          : BaseRosterStartingLine.mine.name,
    }).eq('user_id', user.id);
  }

  static String _databaseDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
