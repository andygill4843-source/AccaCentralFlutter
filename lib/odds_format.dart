/// A single point on the standard UK bookmaker price ladder.
class _LadderPrice {
  final int num;
  final int den;
  final double decimal;
  const _LadderPrice(this.num, this.den, this.decimal);
}

/// The standard fractional price ladder used by UK bookmakers — a fixed
/// set of "nice" fractions, not an arbitrary mathematical approximation.
/// Real boards never show odds like "19/20" or "47/23"; they snap to
/// entries like these. Sorted ascending by decimal value.
final List<_LadderPrice> _priceLadder = [
  _LadderPrice(1, 100, 1.01), _LadderPrice(1, 50, 1.02), _LadderPrice(1, 33, 1.0303),
  _LadderPrice(1, 25, 1.04), _LadderPrice(1, 20, 1.05), _LadderPrice(1, 16, 1.0625),
  _LadderPrice(1, 14, 1.0714), _LadderPrice(1, 12, 1.0833), _LadderPrice(1, 10, 1.10),
  _LadderPrice(1, 9, 1.1111), _LadderPrice(1, 8, 1.125), _LadderPrice(2, 15, 1.1333),
  _LadderPrice(1, 7, 1.1429), _LadderPrice(2, 13, 1.1538), _LadderPrice(1, 6, 1.1667),
  _LadderPrice(2, 11, 1.1818), _LadderPrice(1, 5, 1.20), _LadderPrice(2, 9, 1.2222),
  _LadderPrice(1, 4, 1.25), _LadderPrice(2, 7, 1.2857), _LadderPrice(1, 3, 1.3333),
  _LadderPrice(4, 11, 1.3636), _LadderPrice(2, 5, 1.40), _LadderPrice(4, 9, 1.4444),
  _LadderPrice(1, 2, 1.50), _LadderPrice(4, 7, 1.5714), _LadderPrice(8, 13, 1.6154),
  _LadderPrice(4, 6, 1.6667), _LadderPrice(8, 11, 1.7273), _LadderPrice(4, 5, 1.80),
  _LadderPrice(5, 6, 1.8333), _LadderPrice(10, 11, 1.9091), _LadderPrice(20, 21, 1.9524),
  _LadderPrice(1, 1, 2.00), // evens
  _LadderPrice(21, 20, 2.05), _LadderPrice(11, 10, 2.10), _LadderPrice(6, 5, 2.20),
  _LadderPrice(5, 4, 2.25), _LadderPrice(21, 16, 2.3125), _LadderPrice(11, 8, 2.375),
  _LadderPrice(6, 4, 2.50), _LadderPrice(13, 8, 2.625), _LadderPrice(7, 4, 2.75),
  _LadderPrice(15, 8, 2.875), _LadderPrice(2, 1, 3.00), _LadderPrice(9, 4, 3.25),
  _LadderPrice(5, 2, 3.50), _LadderPrice(11, 4, 3.75), _LadderPrice(3, 1, 4.00),
  _LadderPrice(100, 30, 4.3333), _LadderPrice(7, 2, 4.50), _LadderPrice(4, 1, 5.00),
  _LadderPrice(9, 2, 5.50), _LadderPrice(5, 1, 6.00), _LadderPrice(11, 2, 6.50),
  _LadderPrice(6, 1, 7.00), _LadderPrice(13, 2, 7.50), _LadderPrice(7, 1, 8.00),
  _LadderPrice(15, 2, 8.50), _LadderPrice(8, 1, 9.00), _LadderPrice(17, 2, 9.50),
  _LadderPrice(9, 1, 10.00), _LadderPrice(10, 1, 11.00), _LadderPrice(11, 1, 12.00),
  _LadderPrice(12, 1, 13.00), _LadderPrice(14, 1, 15.00), _LadderPrice(16, 1, 17.00),
  _LadderPrice(18, 1, 19.00), _LadderPrice(20, 1, 21.00), _LadderPrice(22, 1, 23.00),
  _LadderPrice(25, 1, 26.00), _LadderPrice(28, 1, 29.00), _LadderPrice(33, 1, 34.00),
  _LadderPrice(40, 1, 41.00), _LadderPrice(50, 1, 51.00), _LadderPrice(66, 1, 67.00),
  _LadderPrice(80, 1, 81.00), _LadderPrice(100, 1, 101.00), _LadderPrice(150, 1, 151.00),
  _LadderPrice(200, 1, 201.00), _LadderPrice(250, 1, 251.00), _LadderPrice(500, 1, 501.00),
  _LadderPrice(1000, 1, 1001.00),
];

/// Converts a SINGLE LEG's decimal price to the nearest standard UK
/// bookmaker fractional price (e.g. 2.5 -> "6/4"), snapped to the real
/// price ladder bookmakers actually use for individual selections — not
/// the mathematically exact fraction, which often produces prices no
/// board would ever show (e.g. 1.95 as "19/20" rather than the real
/// nearby price "10/11").
///
/// This is DISPLAY-ONLY — it never feeds back into any stored value or
/// calculation. bookmakerPrices, decimalOddsAtSelection, and combinedOdds
/// are always computed from the true API decimal prices; this function
/// only formats a number for the user to read.
///
/// DO NOT use this for combined/accumulator odds — see
/// combinedOddsToFractional below for that.
String decimalToFractional(double decimalOdds) {
  if (decimalOdds <= 1.0) return '0/1';

  if (decimalOdds <= _priceLadder.first.decimal) {
    final p = _priceLadder.first;
    return '${p.num}/${p.den}';
  }
  if (decimalOdds >= _priceLadder.last.decimal) {
    final p = _priceLadder.last;
    return '${p.num}/${p.den}';
  }

  _LadderPrice best = _priceLadder.first;
  double bestErr = double.infinity;
  for (final p in _priceLadder) {
    final err = (p.decimal - decimalOdds).abs();
    if (err < bestErr) {
      bestErr = err;
      best = p;
    }
  }
  return '${best.num}/${best.den}';
}

/// Formats COMBINED / ACCUMULATOR decimal odds as "N/1", rounded to the
/// nearest whole number (e.g. 671.168 -> "671/1").
///
/// Deliberately NOT snapped to the singles price ladder above — a
/// combined price is the exact product of several already-ladder-snapped
/// leg prices multiplied together, and real bookmakers display that
/// combined figure as a plain decimal-derived number, never re-snapped
/// to a nearby board price (doing so would misrepresent the actual
/// payout the multiplication promises).
///
/// This is a DISPLAY-ONLY formatter, purely cosmetic. The value passed
/// in must already be the true combined odds — computed by multiplying
/// each leg's raw, un-rounded decimal price together — never the output
/// of this function or of decimalToFractional. Every call site in this
/// app already computes combinedOdds this way (see
/// AccumulatorSummaryScreen.bookmakerOptions), so this function is only
/// ever used at the final point of rendering to the user, and never
/// feeds back into what's actually stored or calculated.
String combinedOddsToFractional(double decimalOdds) {
  if (decimalOdds <= 1.0) return '0/1';
  final profit = (decimalOdds - 1).round();
  return '$profit/1';
}