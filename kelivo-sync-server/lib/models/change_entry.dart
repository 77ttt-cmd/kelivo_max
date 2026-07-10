class ChangeEntry {
  final int id;
  final int userId;
  final String category;
  final String recordId;
  final Map<String, dynamic> payload;
  final int updatedAt;
  final int? deletedAt;
  final int serverSeq;

  ChangeEntry({
    required this.id,
    required this.userId,
    required this.category,
    required this.recordId,
    required this.payload,
    required this.updatedAt,
    this.deletedAt,
    required this.serverSeq,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'recordId': recordId,
    'payload': payload,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'serverSeq': serverSeq,
  };
}
