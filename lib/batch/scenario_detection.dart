import '../models/duty.dart';
import '../models/roster_day.dart';

/// Minimum Rest situations the A320/321 Working Conditions distinguish —
/// mirrors the private `_A320RestScenario` enum in
/// `min_rest_input_screen.dart`, made public and standalone so the batch
/// audit engine can reuse the exact same detection logic the manual
/// screen already uses (rather than a second, drifting copy of it).
enum A320RestScenario {
  base,
  outstation,
  throughTheNight,
  postWestboundTransatlantic,
  outstationAfterEastboundTransatlantic,
  postIntercontinentalSameDay,
  afterStandby,
  preIntercontinental,
}

enum A330RestScenario {
  baseContinental,
  outstationContinental,
  throughTheNight,
  postIntercontinentalWestbound,
  outstationAfterEastbound,
  preIntercontinental,
  afterStandby,
}

/// Ported verbatim (01/10) from `MinRestInputScreen._detectA320Scenario` —
/// see that method's comments for the reasoning. Deliberately does NOT
/// cover "day before an Intercontinental" (`preIntercontinental`): that
/// needs the day BEFORE this one too, which the manual screen also never
/// auto-detects — kept consistent here, not a new gap this engine adds.
A320RestScenario? detectA320Scenario(RosterDay day) {
  if (day.legs.isEmpty && day.standbys.isEmpty) return null;
  if (day.standbys.isNotEmpty) return A320RestScenario.afterStandby;
  if (day.intercontinental) {
    final sameDayReturn = day.legs.length >= 2 &&
        day.reportStation == 'DUB' &&
        day.finishStation == 'DUB';
    if (sameDayReturn) return A320RestScenario.postIntercontinentalSameDay;
    if (day.finishStation == 'DUB') {
      return A320RestScenario.postWestboundTransatlantic;
    }
    if (day.finishStation != null) {
      return A320RestScenario.outstationAfterEastboundTransatlantic;
    }
    return null;
  }
  if (isThroughTheNight(day) && day.finishStation == 'DUB') {
    return A320RestScenario.throughTheNight;
  }
  if (day.finishStation == 'DUB') return A320RestScenario.base;
  if (day.finishStation != null) return A320RestScenario.outstation;
  return null;
}

/// Ported verbatim (01/10) from `MinRestInputScreen._detectA330Scenario`.
A330RestScenario? detectA330Scenario(RosterDay day) {
  if (day.legs.isEmpty && day.standbys.isEmpty) return null;
  if (day.standbys.isNotEmpty) return A330RestScenario.afterStandby;
  if (day.intercontinental) {
    final sameDayReturn = day.legs.length >= 2 &&
        day.reportStation == 'DUB' &&
        day.finishStation == 'DUB';
    if (sameDayReturn) return null; // no dedicated A330 scenario, as upstream
    if (day.finishStation == 'DUB') {
      return A330RestScenario.postIntercontinentalWestbound;
    }
    if (day.finishStation != null) {
      return A330RestScenario.outstationAfterEastbound;
    }
    return null;
  }
  if (isThroughTheNight(day) && day.finishStation == 'DUB') {
    return A330RestScenario.throughTheNight;
  }
  if (day.finishStation == 'DUB') return A330RestScenario.baseContinental;
  if (day.finishStation != null) return A330RestScenario.outstationContinental;
  return null;
}

/// Ported verbatim (01/10) from `MinRestInputScreen._isThroughTheNight`.
bool isThroughTheNight(RosterDay day) {
  final suggestion = day.suggestedTimes();
  if (suggestion == null) return false;
  final probe = Duty(
    report: suggestion.report,
    end: suggestion.finish,
    type: DutyType.flight,
  );
  return probe.isThroughTheNight;
}
