import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/job_card.dart';

class JobCardMatch {
  const JobCardMatch({
    required this.jobCard,
    required this.documentId,
    required this.storagePath,
    required this.originalFilename,
  });

  final JobCard jobCard;
  final String documentId;
  final String storagePath;
  final String originalFilename;
}

class JobCardChoice {
  const JobCardChoice({required this.jobCard});

  final JobCard jobCard;
}

class JobCardService {
  JobCardService({SupabaseClient? supabase})
    : _supabase = supabase ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  static const String _jobCardTable = 'job_cards';
  static const String _documentTable = 'roster_documents';
  static const String _bucketName = 'roster-documents';

  Future<JobCardMatch?> findMatchingJobCard({
    required String turnNumber,
    required DateTime dutyDate,
  }) async {
    final String normalisedTurn = _normaliseTurnNumber(turnNumber);

    if (normalisedTurn.isEmpty) {
      return null;
    }

    final String databaseDate = _databaseDate(dutyDate);

    final List<dynamic> rows = await _supabase
        .from(_jobCardTable)
        .select(
          'id, document_id, turn_number, original_turn_code, day_code, '
          'plan_type, valid_from, valid_to, book_on, book_off, '
          'rostered_minutes, page_number, raw_text, instructions',
        )
        .eq('turn_number', normalisedTurn)
        .lte('valid_from', databaseDate)
        .gte('valid_to', databaseDate);

    if (rows.isEmpty) {
      return null;
    }

    final List<_JobCardCandidate> candidates = rows
        .whereType<Map<String, dynamic>>()
        .map(_candidateFromRow)
        .where((candidate) => candidate.card.isValidOn(dutyDate))
        .toList(growable: false);

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((first, second) {
      final int planComparison = second.card.planPriority.compareTo(
        first.card.planPriority,
      );

      if (planComparison != 0) {
        return planComparison;
      }

      final int dayComparison = second.card.daySpecificity.compareTo(
        first.card.daySpecificity,
      );

      if (dayComparison != 0) {
        return dayComparison;
      }

      return second.card.validFrom.compareTo(first.card.validFrom);
    });

    final _JobCardCandidate selected = candidates.first;

    final Map<String, dynamic>? document = await _supabase
        .from(_documentTable)
        .select('id, storage_path, original_filename')
        .eq('id', selected.documentId)
        .maybeSingle();

    if (document == null) {
      return null;
    }

    final String storagePath = _stringValue(document['storage_path']);

    if (storagePath.isEmpty) {
      return null;
    }

    return JobCardMatch(
      jobCard: selected.card,
      documentId: selected.documentId,
      storagePath: storagePath,
      originalFilename: _stringValue(document['original_filename']),
    );
  }

  Future<List<JobCardChoice>> findValidJobCardsForDate({
    required DateTime dutyDate,
  }) async {
    final String databaseDate = _databaseDate(dutyDate);

    final List<dynamic> rows = await _supabase
        .from(_jobCardTable)
        .select(
          'id, document_id, turn_number, original_turn_code, day_code, '
          'plan_type, valid_from, valid_to, book_on, book_off, '
          'rostered_minutes, page_number, raw_text, instructions',
        )
        .lte('valid_from', databaseDate)
        .gte('valid_to', databaseDate);

    final List<_JobCardCandidate> candidates = rows
        .whereType<Map<String, dynamic>>()
        .map(_candidateFromRow)
        .where(
          (candidate) =>
              candidate.card.turnNumber.isNotEmpty &&
              candidate.card.isValidOn(dutyDate),
        )
        .toList();

    final Map<String, _JobCardCandidate> bestByTurn =
        <String, _JobCardCandidate>{};

    for (final _JobCardCandidate candidate in candidates) {
      final String turn = candidate.card.turnNumber;
      final _JobCardCandidate? current = bestByTurn[turn];

      if (current == null || _isBetterCandidate(candidate, current)) {
        bestByTurn[turn] = candidate;
      }
    }

    final List<JobCardChoice> choices = bestByTurn.values
        .map((candidate) => JobCardChoice(jobCard: candidate.card))
        .toList();

    choices.sort((first, second) {
      final int firstTurn = int.tryParse(first.jobCard.turnNumber) ?? 999999;
      final int secondTurn = int.tryParse(second.jobCard.turnNumber) ?? 999999;

      final int numberComparison = firstTurn.compareTo(secondTurn);

      if (numberComparison != 0) {
        return numberComparison;
      }

      return first.jobCard.turnNumber.compareTo(second.jobCard.turnNumber);
    });

    return choices;
  }

  static bool _isBetterCandidate(
    _JobCardCandidate candidate,
    _JobCardCandidate current,
  ) {
    final int planComparison = candidate.card.planPriority.compareTo(
      current.card.planPriority,
    );

    if (planComparison != 0) {
      return planComparison > 0;
    }

    final int dayComparison = candidate.card.daySpecificity.compareTo(
      current.card.daySpecificity,
    );

    if (dayComparison != 0) {
      return dayComparison > 0;
    }

    return candidate.card.validFrom.isAfter(current.card.validFrom);
  }

  Future<String> createSignedPdfUrl(JobCardMatch match) async {
    return _supabase.storage
        .from(_bucketName)
        .createSignedUrl(match.storagePath, 60 * 30);
  }

  static _JobCardCandidate _candidateFromRow(Map<String, dynamic> row) {
    final String documentId = _stringValue(row['document_id']);

    return _JobCardCandidate(
      documentId: documentId,
      card: JobCard(
        turnNumber: _normaliseTurnNumber(_stringValue(row['turn_number'])),
        originalTurnCode: _stringValue(row['original_turn_code']),
        dayCode: _stringValue(row['day_code']),
        planType: _planType(row['plan_type']),
        validFrom: _dateValue(row['valid_from']),
        validTo: _dateValue(row['valid_to']),
        bookOn: _timeValue(row['book_on']),
        bookOff: _timeValue(row['book_off']),
        rosteredMinutes: _integerValue(row['rostered_minutes']),
        pageNumber: _nullableInteger(row['page_number']),
        rawText: _stringValue(row['raw_text']),
        instructions: _instructions(row['instructions']),
      ),
    );
  }

  static JobCardPlanType _planType(dynamic value) {
    switch (_stringValue(value).toLowerCase()) {
      case 'ltp':
        return JobCardPlanType.ltp;
      case 'stp':
        return JobCardPlanType.stp;
      case 'vstp':
        return JobCardPlanType.vstp;
      default:
        return JobCardPlanType.unknown;
    }
  }

  static DateTime _dateValue(dynamic value) {
    final DateTime? parsed = DateTime.tryParse(_stringValue(value));

    if (parsed == null) {
      throw const JobCardServiceException(
        'A stored Job Card contains an invalid validity date.',
      );
    }

    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  static String _timeValue(dynamic value) {
    final String text = _stringValue(value);

    if (text.length >= 5) {
      return text.substring(0, 5);
    }

    return text;
  }

  static int _integerValue(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(_stringValue(value)) ?? 0;
  }

  static int? _nullableInteger(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(_stringValue(value));
  }

  static List<String> _instructions(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }

    return const <String>[];
  }

  static String _normaliseTurnNumber(String value) {
    final Match? match = RegExp(
      r'(\d{1,4})',
      caseSensitive: false,
    ).firstMatch(value.trim());

    return match?.group(1) ?? '';
  }

  static String _databaseDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  static String _stringValue(dynamic value) {
    return value?.toString().trim() ?? '';
  }
}

class _JobCardCandidate {
  const _JobCardCandidate({required this.documentId, required this.card});

  final String documentId;
  final JobCard card;
}

class JobCardServiceException implements Exception {
  const JobCardServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
