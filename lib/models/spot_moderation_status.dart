/// Firestore `spots.moderationStatus`；舊資料無此欄位時視為 [approved]。
enum SpotModerationStatus {
  approved,
  pending,
  rejected;

  String get firestoreValue => name;

  static SpotModerationStatus parse(String? raw) {
    switch (raw) {
      case "pending":
        return SpotModerationStatus.pending;
      case "rejected":
        return SpotModerationStatus.rejected;
      default:
        return SpotModerationStatus.approved;
    }
  }
}
