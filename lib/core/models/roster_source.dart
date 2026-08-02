enum RosterSource {
  baseRoster,
  tenDay,
  sevenDay,
  fortyEightHour,
  annualLeave,
  manual,
}

extension RosterSourceExtension on RosterSource {
  int get priority {
    switch (this) {
      case RosterSource.baseRoster:
        return 1;
      case RosterSource.tenDay:
        return 2;
      case RosterSource.sevenDay:
        return 3;
      case RosterSource.fortyEightHour:
        return 4;
      case RosterSource.annualLeave:
        return 5;
      case RosterSource.manual:
        return 6;
    }
  }
}
