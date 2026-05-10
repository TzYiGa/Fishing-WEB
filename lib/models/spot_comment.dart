import "package:cloud_firestore/cloud_firestore.dart";

class SpotComment {
  SpotComment({
    required this.id,
    required this.text,
    required this.userId,
    required this.authorLabel,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String userId;
  final String authorLabel;
  final DateTime createdAt;

  factory SpotComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data()!;
    final ts = (m["createdAt"] as Timestamp?)?.toDate() ?? DateTime.now();
    return SpotComment(
      id: doc.id,
      text: (m["text"] as String?) ?? "",
      userId: (m["userId"] as String?) ?? "",
      authorLabel: (m["authorLabel"] as String?) ?? "匿名",
      createdAt: ts,
    );
  }

  Map<String, dynamic> toCreateMap({
    required String userId,
    required String authorLabel,
  }) =>
      <String, dynamic>{
        "text": text,
        "userId": userId,
        "authorLabel": authorLabel,
        "createdAt": FieldValue.serverTimestamp(),
      };
}
