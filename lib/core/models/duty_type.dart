enum DutyType {
  working,
  training,
  medical,
  restDay,
  annualLeave,
  sick,
  publicHoliday,
  unavailable,
  unknown,
}

extension DutyTypeExtension on DutyType {
  bool get countsAsWorking {
    switch (this) {
      case DutyType.working:
      case DutyType.training:
      case DutyType.medical:
        return true;
      default:
        return false;
    }
  }
}
