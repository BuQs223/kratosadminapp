// Pure Dart probes of the exact date/number operations used by Flutter.
// Run: TZ=Europe/Bucharest dart audits/2026-09-13-report-parity/dart-probes.dart
import 'dart:convert';
void main() {
  final local = DateTime(2026, 9, 13);
  final autumn = DateTime(2026, 10, 25);
  final springMonday = DateTime(2026, 3, 23);
  final probe = <String, Object?>{
    'local_midnight_iso': local.toIso8601String(),
    'autumn_next_day_using_duration': autumn.add(const Duration(days: 1)).toIso8601String(),
    'spring_week_end_using_duration': springMonday.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59)).toIso8601String(),
    'price_19_99_truncated_cents': (double.parse('19.99') * 100).toInt(),
    'price_19_99_rounded_cents': (double.parse('19.99') * 100).round(),
    'comma_price_flutter_fallback': double.tryParse('100,50') ?? 0,
    'trailing_text_flutter_fallback': double.tryParse('100abc') ?? 0,
    'expiry_fallback_at_noon': DateTime(2026, 9, 13, 12).isAfter(DateTime.parse('2026-09-13')),
    'utc_profile_date_day': DateTime.parse('2026-09-12T22:30:00Z').day,
    'local_profile_date_day': DateTime.parse('2026-09-12T22:30:00Z').toLocal().day,
  };
  print(const JsonEncoder.withIndent('  ').convert(probe));
}
