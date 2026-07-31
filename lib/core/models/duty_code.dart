import 'duty_type.dart';

enum DutyCodeContext { crewplan, traincrewUnavailability }

class DutyCodeDefinition {
  const DutyCodeDefinition({
    required this.code,
    this.crewplanMeaning,
    this.traincrewUnavailabilityMeaning,
    this.dutyType = DutyType.unknown,
  });

  final String code;
  final String? crewplanMeaning;
  final String? traincrewUnavailabilityMeaning;
  final DutyType dutyType;

  bool get isCrewplanCode => crewplanMeaning != null;

  bool get isTraincrewUnavailabilityCode =>
      traincrewUnavailabilityMeaning != null;

  String? meaningFor(DutyCodeContext context) {
    switch (context) {
      case DutyCodeContext.crewplan:
        return crewplanMeaning;
      case DutyCodeContext.traincrewUnavailability:
        return traincrewUnavailabilityMeaning;
    }
  }

  String get preferredMeaning =>
      traincrewUnavailabilityMeaning ?? crewplanMeaning ?? 'Unknown duty code';
}

class DutyCodeLibrary {
  const DutyCodeLibrary._();

  static const List<DutyCodeDefinition> codes = [
    DutyCodeDefinition(
      code: 'AC',
      crewplanMeaning: 'Accident at work',
      traincrewUnavailabilityMeaning: 'Accident at work',
    ),
    DutyCodeDefinition(
      code: 'ACC',
      crewplanMeaning: 'Accommodation – Non Traincrew',
    ),
    DutyCodeDefinition(
      code: 'ALD',
      crewplanMeaning: 'Daily Annual Leave',
      traincrewUnavailabilityMeaning: 'Daily Annual Leave',
      dutyType: DutyType.annualLeave,
    ),
    DutyCodeDefinition(
      code: 'ALW',
      traincrewUnavailabilityMeaning: 'Annual Leave Weekly',
      dutyType: DutyType.annualLeave,
    ),
    DutyCodeDefinition(
      code: 'AS',
      crewplanMeaning: 'Strike',
      traincrewUnavailabilityMeaning: 'Strike',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'AW',
      crewplanMeaning: 'Absent Without Leave',
      traincrewUnavailabilityMeaning: 'Absent Without Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'BH',
      crewplanMeaning: 'Bank Holiday',
      traincrewUnavailabilityMeaning: 'Bank Holiday',
      dutyType: DutyType.publicHoliday,
    ),
    DutyCodeDefinition(
      code: 'BHL',
      traincrewUnavailabilityMeaning: 'Annual Leave (Bank Holiday)',
      dutyType: DutyType.annualLeave,
    ),
    DutyCodeDefinition(
      code: 'BL',
      crewplanMeaning: 'Bereavement Leave',
      traincrewUnavailabilityMeaning: 'Bereavement Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'C1',
      crewplanMeaning: 'Civic Duties',
      traincrewUnavailabilityMeaning: 'Civic Duties',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'C2',
      crewplanMeaning: 'Attendance at a Tribunal',
      traincrewUnavailabilityMeaning: 'Attendance at Tribunal',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'C4',
      crewplanMeaning: 'Magisterial Leave',
      traincrewUnavailabilityMeaning: 'Magisterial Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'C5',
      crewplanMeaning: 'School Governor Leave',
      traincrewUnavailabilityMeaning: 'School Governor Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'CC',
      crewplanMeaning: 'Chain of care',
      traincrewUnavailabilityMeaning: 'Chain of Care',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'CL',
      crewplanMeaning: 'Compensatory Leave',
      traincrewUnavailabilityMeaning: 'Compensatory Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'CO',
      crewplanMeaning: 'Represent Company at Court',
      traincrewUnavailabilityMeaning: 'Represent Company at Court',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'CW',
      crewplanMeaning: 'Court Witness',
      traincrewUnavailabilityMeaning: 'Court Witness',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'D1',
      crewplanMeaning: 'Grievance Hearing',
      traincrewUnavailabilityMeaning: 'Grievance Hearing',
    ),
    DutyCodeDefinition(
      code: 'D2',
      crewplanMeaning: 'MFA Interview',
      traincrewUnavailabilityMeaning: 'MFA Interview',
    ),
    DutyCodeDefinition(
      code: 'D3',
      crewplanMeaning: 'Safety Related Incident',
      traincrewUnavailabilityMeaning: 'Safety Related Incident',
    ),
    DutyCodeDefinition(
      code: 'D4',
      crewplanMeaning: 'Welcome Back Interview',
      traincrewUnavailabilityMeaning: 'Welcome Back Interview',
    ),
    DutyCodeDefinition(
      code: 'D5',
      crewplanMeaning: 'Planned Authorised Detachment',
      traincrewUnavailabilityMeaning: 'Planned Authorised Detachment',
    ),
    DutyCodeDefinition(
      code: 'D6',
      crewplanMeaning: 'Interview',
      traincrewUnavailabilityMeaning: 'Interview',
    ),
    DutyCodeDefinition(
      code: 'DI',
      crewplanMeaning: 'Driver Instructor',
      traincrewUnavailabilityMeaning: 'Driver Instructor',
      dutyType: DutyType.working,
    ),
    DutyCodeDefinition(
      code: 'DR2',
      crewplanMeaning: 'Minimum Turn Break Broken',
    ),
    DutyCodeDefinition(
      code: 'DR3',
      crewplanMeaning: 'Minimum Break with a ND Broken',
    ),
    DutyCodeDefinition(code: 'DR4', crewplanMeaning: 'Turn Overtime Exceeded'),
    DutyCodeDefinition(
      code: 'DR5',
      crewplanMeaning: 'Number of Consecutive Turns Exceeded',
    ),
    DutyCodeDefinition(
      code: 'DR7',
      crewplanMeaning: 'Move From Booked Time Exceeded',
    ),
    DutyCodeDefinition(
      code: 'DX',
      crewplanMeaning: 'Disciplinary Hearing',
      traincrewUnavailabilityMeaning: 'Disciplinary Hearing',
    ),
    DutyCodeDefinition(
      code: 'EL',
      crewplanMeaning: 'Education Leave',
      traincrewUnavailabilityMeaning: 'Education Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'FL',
      crewplanMeaning: 'First Aid Leave',
      traincrewUnavailabilityMeaning: 'First Aid Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'HA',
      crewplanMeaning: 'Hospital Appointment',
      traincrewUnavailabilityMeaning: 'Hospital Appointment',
      dutyType: DutyType.medical,
    ),
    DutyCodeDefinition(
      code: 'HG',
      crewplanMeaning: 'Higher Grade Duty',
      traincrewUnavailabilityMeaning: 'Higher Grade Duty',
      dutyType: DutyType.working,
    ),
    DutyCodeDefinition(
      code: 'HR',
      crewplanMeaning: 'Household Removals',
      traincrewUnavailabilityMeaning: 'Household Removals',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'HS',
      crewplanMeaning: 'Booked off sick',
      traincrewUnavailabilityMeaning: 'Booked off Sick',
      dutyType: DutyType.sick,
    ),
    DutyCodeDefinition(
      code: 'JL',
      crewplanMeaning: 'Jury Service',
      traincrewUnavailabilityMeaning: 'Jury Service',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'LA',
      crewplanMeaning: 'Company Council',
      traincrewUnavailabilityMeaning: 'Company Council',
    ),
    DutyCodeDefinition(
      code: 'LC',
      crewplanMeaning: 'LLC Duties',
      traincrewUnavailabilityMeaning: 'LLC Duties',
    ),
    DutyCodeDefinition(
      code: 'LD',
      crewplanMeaning: 'Restricted/Non-core duties/Back to work plan',
      traincrewUnavailabilityMeaning:
          'Restricted/Non-core duties/Back to work plan',
    ),
    DutyCodeDefinition(
      code: 'LH',
      crewplanMeaning: 'Health and Safety',
      traincrewUnavailabilityMeaning: 'Health and Safety',
    ),
    DutyCodeDefinition(
      code: 'MD',
      crewplanMeaning: 'Marriage Day',
      traincrewUnavailabilityMeaning: 'Marriage Day',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'ME',
      crewplanMeaning: 'Medical – Special',
      traincrewUnavailabilityMeaning: 'Medical – Special',
      dutyType: DutyType.medical,
    ),
    DutyCodeDefinition(
      code: 'ML',
      crewplanMeaning: 'Maternity Leave',
      traincrewUnavailabilityMeaning: 'Maternity Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'MP',
      crewplanMeaning: 'Medical – Periodical',
      traincrewUnavailabilityMeaning: 'Medical – Periodical',
      dutyType: DutyType.medical,
    ),
    DutyCodeDefinition(
      code: 'MR',
      crewplanMeaning: 'Medical – Review',
      traincrewUnavailabilityMeaning: 'Medical – Review',
      dutyType: DutyType.medical,
    ),
    DutyCodeDefinition(
      code: 'NL',
      crewplanMeaning: 'Parental Leave – nil pay',
      traincrewUnavailabilityMeaning: 'Parental Leave – nil pay',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'PL',
      crewplanMeaning: 'Paid leave (Authorised only by TOM)',
      traincrewUnavailabilityMeaning: 'Paid leave (Authorised only by TOM)',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'PR',
      crewplanMeaning: 'Suspension – Full Pay',
      traincrewUnavailabilityMeaning: 'Suspension – Full Pay',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'PS',
      crewplanMeaning: 'Suspension – Nil Pay',
      traincrewUnavailabilityMeaning: 'Suspension – Nil Pay',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'PT',
      crewplanMeaning: 'Paternity Leave',
      traincrewUnavailabilityMeaning: 'Paternity Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'RK',
      crewplanMeaning: 'Route Knowledge Failure',
      traincrewUnavailabilityMeaning: 'Route Knowledge Failure',
    ),
    DutyCodeDefinition(
      code: 'RL',
      crewplanMeaning: 'Route Learning',
      traincrewUnavailabilityMeaning: 'Route Learning',
      dutyType: DutyType.training,
    ),
    DutyCodeDefinition(
      code: 'RR',
      crewplanMeaning: 'Route or Traction Refresh',
      traincrewUnavailabilityMeaning: 'Route or Traction Refresh',
      dutyType: DutyType.training,
    ),
    DutyCodeDefinition(
      code: 'RU',
      crewplanMeaning: 'Rules/Summary Day',
      traincrewUnavailabilityMeaning: 'Rules/Summary Day',
      dutyType: DutyType.training,
    ),
    DutyCodeDefinition(
      code: 'RW',
      crewplanMeaning: 'Rest Day Work',
      traincrewUnavailabilityMeaning: 'Rest Day Work',
      dutyType: DutyType.working,
    ),
    DutyCodeDefinition(
      code: 'SF',
      crewplanMeaning: 'Sick',
      traincrewUnavailabilityMeaning: 'Sick',
      dutyType: DutyType.sick,
    ),
    DutyCodeDefinition(
      code: 'SI',
      crewplanMeaning: 'S Conductor Instructing',
      traincrewUnavailabilityMeaning: 'S Conductor Instructing',
      dutyType: DutyType.working,
    ),
    DutyCodeDefinition(
      code: 'SK',
      crewplanMeaning: 'Traction Knowledge Failure',
      traincrewUnavailabilityMeaning: 'Traction Knowledge Failure',
    ),
    DutyCodeDefinition(
      code: 'SP',
      crewplanMeaning: 'Spare',
      traincrewUnavailabilityMeaning: 'Spare',
      dutyType: DutyType.working,
    ),
    DutyCodeDefinition(
      code: 'TA',
      crewplanMeaning: 'Territorial Army',
      traincrewUnavailabilityMeaning: 'Territorial Army',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'TC',
      crewplanMeaning: 'Training Course',
      traincrewUnavailabilityMeaning: 'Training Course',
      dutyType: DutyType.training,
    ),
    DutyCodeDefinition(
      code: 'TS',
      crewplanMeaning: 'Safety Brief/STUD/CA',
      traincrewUnavailabilityMeaning: 'Safety Brief/STUD/CA',
      dutyType: DutyType.training,
    ),
    DutyCodeDefinition(
      code: 'TT',
      crewplanMeaning: 'Traction Training',
      traincrewUnavailabilityMeaning: 'Traction Training',
      dutyType: DutyType.training,
    ),
    DutyCodeDefinition(
      code: 'TW',
      crewplanMeaning: 'Training at Work',
      traincrewUnavailabilityMeaning: 'Training at Work',
      dutyType: DutyType.training,
    ),
    DutyCodeDefinition(
      code: 'UL',
      crewplanMeaning: 'Unpaid Leave',
      traincrewUnavailabilityMeaning: 'Unpaid Leave',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'XD',
      crewplanMeaning: 'Cross Depot Allocated',
      dutyType: DutyType.working,
    ),
    DutyCodeDefinition(
      code: 'ZB',
      crewplanMeaning: 'No Bank Holiday Work',
      traincrewUnavailabilityMeaning: 'No Bank Holiday Work',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'ZC',
      crewplanMeaning: 'Considerate Duties',
      traincrewUnavailabilityMeaning: 'Considerate Duties',
    ),
    DutyCodeDefinition(
      code: 'ZD',
      crewplanMeaning: 'Restricted no work',
      traincrewUnavailabilityMeaning: 'Restricted no work',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'ZF',
      crewplanMeaning: 'Forced Rest Day',
      traincrewUnavailabilityMeaning: 'Forced Rest Day',
      dutyType: DutyType.restDay,
    ),
    DutyCodeDefinition(
      code: 'ZR',
      crewplanMeaning: 'No rest day work',
      dutyType: DutyType.unavailable,
    ),
    DutyCodeDefinition(
      code: 'ZS',
      crewplanMeaning: 'No Sunday work',
      dutyType: DutyType.unavailable,
    ),
  ];

  static final Map<String, DutyCodeDefinition> _byCode = {
    for (final definition in codes) definition.code.toUpperCase(): definition,
  };

  static DutyCodeDefinition? find(String? code) {
    if (code == null) return null;

    final cleaned = normaliseCode(code);
    if (cleaned.isEmpty) return null;

    return _byCode[cleaned];
  }

  static bool contains(String? code) => find(code) != null;

  static String normaliseCode(String value) {
    return value.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static String? meaning(String? code, {DutyCodeContext? context}) {
    final definition = find(code);
    if (definition == null) return null;

    if (context != null) {
      return definition.meaningFor(context) ?? definition.preferredMeaning;
    }

    return definition.preferredMeaning;
  }

  static DutyType dutyTypeFor(String? code) {
    return find(code)?.dutyType ?? DutyType.unknown;
  }

  static List<String> get allCodes =>
      codes.map((definition) => definition.code).toList();

  static List<DutyCodeDefinition> forContext(DutyCodeContext context) {
    return codes.where((definition) {
      switch (context) {
        case DutyCodeContext.crewplan:
          return definition.isCrewplanCode;
        case DutyCodeContext.traincrewUnavailability:
          return definition.isTraincrewUnavailabilityCode;
      }
    }).toList();
  }
}
