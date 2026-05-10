/// 風向／浪向（氣象學：風「來向」，0° = 北）。
String direction16Zh(double? degrees) {
  if (degrees == null || degrees.isNaN) return "—";
  final dirs = [
    "北", "北北東", "東北", "東北東", "東", "東南東",
    "東南", "南南東", "南", "南南西", "西南", "西南西",
    "西", "西北西", "西北", "北北西",
  ];
  final i = ((degrees + 11.25) % 360 ~/ 22.5) % 16;
  return dirs[i];
}
