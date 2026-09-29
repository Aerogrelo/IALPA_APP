enum RuleColor { green, amber, red }

/// The outcome of checking a schedule change against a single agreement
/// rule: green (complies with Working Conditions), amber (breaches the
/// agreement but is legal as an Outside Working Conditions duty, with
/// compensation), or red (breaches EASA — a genuine safety/legal issue).
///
/// Optional margin fields (added 29/09), populated only by the Maximum
/// Flight Duty Time rules for now (R-14/R-15 for the A320/321,
/// [verifyA330MaxDuty] for the A330) — every other rule leaves them null,
/// which the UI treats as "nothing to show":
/// - [marginToOwc]: on a GREEN result, how much time is left before this
///   duty would tip into OWC (amber).
/// - [owcOverage]: on an AMBER result, by how much this duty already
///   exceeds the agreement's normal maximum (i.e. how far into OWC it
///   is) — 10 minutes over reads very differently from 75.
/// - [marginToEasaLimit]: on a GREEN or AMBER result, how much time is
///   left before this duty would exceed the EASA limit (red).
class RuleResult {
  final RuleColor color;
  final String clause;
  final String explanation;
  final String? easaReference;
  final Duration? marginToOwc;
  final Duration? owcOverage;
  final Duration? marginToEasaLimit;

  const RuleResult({
    required this.color,
    required this.clause,
    required this.explanation,
    this.easaReference,
    this.marginToOwc,
    this.owcOverage,
    this.marginToEasaLimit,
  });

  @override
  String toString() => '[$color] $clause: $explanation';
}
