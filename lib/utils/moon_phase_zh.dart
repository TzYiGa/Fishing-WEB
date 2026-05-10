/// 月相盈虧比例 0–1（0 表新月附近、0.5 表滿月附近），採簡化天文公式。
double moonIlluminationFraction(DateTime local) {
  final y = local.year;
  final m = local.month;
  final d = local.day +
      local.hour / 24.0 +
      local.minute / 1440.0 +
      local.second / 86400.0;
  var yy = y;
  var mm = m.toDouble();
  if (mm < 3) {
    yy--;
    mm += 12;
  }
  ++mm;
  final c = 365.25 * yy;
  final e = 30.6 * mm;
  var jd = c + e + d - 694039.09;
  jd /= 29.5305882;
  final b = jd.floor();
  jd -= b;
  return jd.clamp(0.0, 1.0);
}

/// 繁體簡述月相（娛樂／參考用，非專業潮汐計算）。
String moonPhaseLabelZh(DateTime local) {
  final x = moonIlluminationFraction(local);
  if (x < 0.06 || x > 0.94) return "新月";
  if (x < 0.19) return "眉月（漸盈）";
  if (x < 0.31) return "上弦";
  if (x < 0.44) return "盈凸月";
  if (x < 0.56) return "滿月";
  if (x < 0.69) return "虧凸月";
  if (x < 0.81) return "下弦";
  if (x < 0.94) return "殘月";
  return "新月";
}
