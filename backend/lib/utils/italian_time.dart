/// Utility per ottenere sempre l'orario italiano (Europe/Rome: CET UTC+1 / CEST UTC+2)
/// indipendentemente dal fuso orario del server cloud (es. Render in UTC).
class ItalianTime {
  static DateTime now() {
    final utc = DateTime.now().toUtc();
    return fromUtc(utc);
  }

  static DateTime fromUtc(DateTime utc) {
    final year = utc.year;
    // Ultima domenica di Marzo alle 01:00 UTC (inizio ora legale CEST = UTC+2)
    final march31 = DateTime.utc(year, 3, 31);
    final lastSundayMarch = 31 - (march31.weekday % 7);
    final cestStart = DateTime.utc(year, 3, lastSundayMarch, 1, 0, 0);

    // Ultima domenica di Ottobre alle 01:00 UTC (fine ora legale, ritorno a CET = UTC+1)
    final oct31 = DateTime.utc(year, 10, 31);
    final lastSundayOct = 31 - (oct31.weekday % 7);
    final cestEnd = DateTime.utc(year, 10, lastSundayOct, 1, 0, 0);

    final bool isCest = !utc.isBefore(cestStart) && utc.isBefore(cestEnd);
    final shifted = utc.add(Duration(hours: isCest ? 2 : 1));

    // Restituisce un DateTime "wall-clock" italiano (non-UTC) per confronti omogenei
    // con DateTime.tryParse() delle stringhe ISO prive di suffisso 'Z' inviate dall'app.
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
      shifted.microsecond,
    );
  }
}
