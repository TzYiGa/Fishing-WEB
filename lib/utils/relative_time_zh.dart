/// 以繁體中文顯示相對於 [now] 的時間（分／小時為主，較久則顯示具體日期時間）。
String formatCommentTimeZh(DateTime past, DateTime now) {
  if (past.isAfter(now)) return "剛剛";
  final diff = now.difference(past);
  if (diff.inSeconds < 45) return "剛剛";
  final minutes = diff.inMinutes;
  if (minutes < 60) {
    return minutes < 1 ? "1 分鐘前" : "$minutes 分鐘前";
  }
  final totalM = diff.inMinutes;
  final h = totalM ~/ 60;
  final m = totalM % 60;
  if (diff.inHours < 24) {
    if (m == 0) return "$h 小時前";
    return "$h 小時 $m 分鐘前";
  }
  final y = past.year == now.year ? "" : "${past.year}年";
  return "$y${past.month}月${past.day}日 ${past.hour.toString().padLeft(2, "0")}:${past.minute.toString().padLeft(2, "0")}";
}
