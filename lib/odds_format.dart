/// Converts a decimal price to a fractional display string (e.g. 2.5 -> "3/2").
/// This is a best-fit rational approximation, not the bookmaker's own exact
/// fraction — good enough for display, not authoritative.
String decimalToFractional(double decimalOdds, {int maxDenominator = 100}) {
  final value = decimalOdds - 1;
  if (value <= 0) return '0/1';

  int bestNum = 1, bestDen = 1;
  double bestErr = double.infinity;
  for (int den = 1; den <= maxDenominator; den++) {
    final num = (value * den).round();
    if (num < 1) continue;
    final err = ((num / den) - value).abs();
    if (err < bestErr) {
      bestErr = err;
      bestNum = num;
      bestDen = den;
    }
  }
  final g = _gcd(bestNum, bestDen);
  return '${bestNum ~/ g}/${bestDen ~/ g}';
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);