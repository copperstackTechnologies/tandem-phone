String fmtSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  var v = bytes.toDouble();
  const units = ['KB', 'MB', 'GB'];
  var i = -1;
  do {
    v /= 1024;
    i++;
  } while (v >= 1024 && i < units.length - 1);
  return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[i]}';
}

String fmtTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return '${d.inDays} days ago';
  return '${t.day}/${t.month}/${t.year}';
}

String? firstUrl(String text) => RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
