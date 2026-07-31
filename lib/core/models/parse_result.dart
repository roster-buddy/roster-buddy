import 'annual_leave_allocation.dart';
import 'document_type.dart';
import 'duty.dart';
import 'job_card.dart';
import 'parse_warning.dart';

class ParseResult {
  const ParseResult({
    required this.documentType,
    this.duties = const [],
    this.annualLeaveAllocations = const [],
    this.jobCards = const [],
    this.driverFound = false,
    this.driverNumber,
    this.payrollNumber,
    this.pagesProcessed = 0,
    this.weeksDetected = 0,
    this.recordsDetected = 0,
    this.warnings = const [],
  });

  final DocumentType documentType;

  /// Duties extracted from Base Rosters or amendment documents.
  ///
  /// Shared documents may contain duties for many drivers. Matching those
  /// duties to user accounts happens after parsing.
  final List<Duty> duties;

  /// All driver allocations extracted from an Annual Leave Roster.
  final List<AnnualLeaveAllocation> annualLeaveAllocations;

  /// All cards extracted from a Job Card PDF.
  ///
  /// Multiple cards with the same turn number must be retained when their
  /// day code, validity dates or plan type differ.
  final List<JobCard> jobCards;

  /// Used for personal previews and Base Roster activation.
  ///
  /// This is not required for shared amendment, annual-leave or Job Card
  /// uploads because those documents are processed for all applicable users.
  final bool driverFound;
  final String? driverNumber;
  final String? payrollNumber;

  final int pagesProcessed;
  final int weeksDetected;

  /// Total structured records extracted from the document.
  final int recordsDetected;

  final List<ParseWarning> warnings;

  bool get hasWarnings => warnings.isNotEmpty;

  bool get hasBlockingWarnings =>
      warnings.any((warning) => warning.preventsImport);

  bool get hasContent =>
      duties.isNotEmpty ||
      annualLeaveAllocations.isNotEmpty ||
      jobCards.isNotEmpty;

  /// A shared document can be imported without matching the uploader.
  bool get canImport => hasContent && !hasBlockingWarnings;

  int get calculatedRecordCount {
    return duties.length + annualLeaveAllocations.length + jobCards.length;
  }

  int get effectiveRecordCount {
    if (recordsDetected > 0) {
      return recordsDetected;
    }

    return calculatedRecordCount;
  }

  ParseResult copyWith({
    DocumentType? documentType,
    List<Duty>? duties,
    List<AnnualLeaveAllocation>? annualLeaveAllocations,
    List<JobCard>? jobCards,
    bool? driverFound,
    String? driverNumber,
    String? payrollNumber,
    int? pagesProcessed,
    int? weeksDetected,
    int? recordsDetected,
    List<ParseWarning>? warnings,
  }) {
    return ParseResult(
      documentType: documentType ?? this.documentType,
      duties: duties ?? this.duties,
      annualLeaveAllocations:
          annualLeaveAllocations ?? this.annualLeaveAllocations,
      jobCards: jobCards ?? this.jobCards,
      driverFound: driverFound ?? this.driverFound,
      driverNumber: driverNumber ?? this.driverNumber,
      payrollNumber: payrollNumber ?? this.payrollNumber,
      pagesProcessed: pagesProcessed ?? this.pagesProcessed,
      weeksDetected: weeksDetected ?? this.weeksDetected,
      recordsDetected: recordsDetected ?? this.recordsDetected,
      warnings: warnings ?? this.warnings,
    );
  }
}
