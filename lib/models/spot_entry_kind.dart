/// Firestore `spots.entryKind`：區分社群「釣況分享」與地圖固定「釣點」。
enum SpotEntryKind {
  /// 原「新增釣點」流程：照片／氣象快照等，建立後即顯示於地圖。
  conditionShare,

  /// 長期固定標點（哪裡可釣）；會員建立為待審核，核准後才公開。
  fishingPoi;

  String get firestoreValue => name;

  static SpotEntryKind parse(String? raw) {
    if (raw == SpotEntryKind.fishingPoi.name) {
      return SpotEntryKind.fishingPoi;
    }
    return SpotEntryKind.conditionShare;
  }
}
