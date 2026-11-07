/// The largest font size in [min]..[max] for which [fits] holds; [min] when
/// none does. Assumes that a text fitting at one size fits at every smaller
/// one.
double largestFittingFontSize(
  double min,
  double max,
  bool Function(double size) fits,
) {
  if (max <= min || fits(max)) return max;
  if (!fits(min)) return min;
  var lo = min;
  var hi = max;
  for (var i = 0; i < 10; i++) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}
