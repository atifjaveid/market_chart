/// Writes an exponential moving average into [out] for indexes [start] to
/// [length] - 1.
///
/// The average covers the values from index [first] on (read with
/// [valueAt]). It starts at `first + period - 1` with the simple average of
/// the first [period] values, then each value moves it by
/// `2 / (period + 1)` of the difference. Results before that are null.
void emaInto(
  List<double?> out,
  double Function(int index) valueAt,
  int length,
  int period,
  int start,
  int first,
) {
  final alpha = 2 / (period + 1);
  final seedIndex = first + period - 1;
  for (var i = start; i < length; i++) {
    if (i < seedIndex) {
      out[i] = null;
    } else if (i == seedIndex) {
      var sum = 0.0;
      for (var j = first; j <= seedIndex; j++) {
        sum += valueAt(j);
      }
      out[i] = sum / period;
    } else {
      final previous = out[i - 1]!;
      out[i] = previous + alpha * (valueAt(i) - previous);
    }
  }
}
