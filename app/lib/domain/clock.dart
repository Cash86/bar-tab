/// Source of the current time. The only place allowed to call `DateTime.now()`.
abstract interface class Clock {
  /// Current time in UTC.
  DateTime now();
}

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Controllable clock for tests.
class FixedClock implements Clock {
  FixedClock(DateTime start) : _now = start.toUtc();

  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration duration) => _now = _now.add(duration);
}
