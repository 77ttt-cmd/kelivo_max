import 'package:uuid/uuid.dart';

const _uuid = Uuid();

class AssistantMemory {
  final int id; // 0 for new (not used in store), >0 persisted
  final String uid; // UUID v4 for global uniqueness
  final String assistantId;
  final String content;
  final int? updatedAt; // sync timestamp (ms since epoch)
  final int? deletedAt; // tombstone timestamp (ms since epoch)
  final bool localOnly; // whether this memory is local-only

  AssistantMemory({
    required this.id,
    String? uid,
    required this.assistantId,
    required this.content,
    this.updatedAt,
    this.deletedAt,
    this.localOnly = false,
  }) : uid = (uid != null && uid.isNotEmpty) ? uid : _uuid.v4();

  AssistantMemory copyWith({
    int? id,
    String? uid,
    String? assistantId,
    String? content,
    int? Function()? updatedAt,
    int? Function()? deletedAt,
    bool? localOnly,
  }) => AssistantMemory(
    id: id ?? this.id,
    uid: uid ?? this.uid,
    assistantId: assistantId ?? this.assistantId,
    content: content ?? this.content,
    updatedAt: updatedAt != null ? updatedAt() : this.updatedAt,
    deletedAt: deletedAt != null ? deletedAt() : this.deletedAt,
    localOnly: localOnly ?? this.localOnly,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'uid': uid,
    'assistantId': assistantId,
    'content': content,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'localOnly': localOnly,
  };

  static AssistantMemory fromJson(Map<String, dynamic> json) => AssistantMemory(
    id: (json['id'] as num?)?.toInt() ?? 0,
    uid: (json['uid'] as String?) ?? '',
    assistantId: (json['assistantId'] ?? '').toString(),
    content: (json['content'] ?? '').toString(),
    updatedAt: (json['updatedAt'] as num?)?.toInt(),
    deletedAt: (json['deletedAt'] as num?)?.toInt(),
    localOnly: json['localOnly'] == true,
  );
}
