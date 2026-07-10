import 'dart:convert';

class AssistantTag {
  final String id;
  final String name;
  // Sync metadata
  final int? updatedAt;
  final int? deletedAt;
  final bool localOnly;

  const AssistantTag({
    required this.id,
    required this.name,
    this.updatedAt,
    this.deletedAt,
    this.localOnly = false,
  });

  AssistantTag copyWith({
    String? id,
    String? name,
    int? updatedAt,
    int? deletedAt,
    bool? localOnly,
  }) => AssistantTag(
    id: id ?? this.id,
    name: name ?? this.name,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
    localOnly: localOnly ?? this.localOnly,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'localOnly': localOnly,
  };

  static AssistantTag fromJson(Map<String, dynamic> json) => AssistantTag(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    updatedAt: (json['updatedAt'] as num?)?.toInt(),
    deletedAt: (json['deletedAt'] as num?)?.toInt(),
    localOnly: json['localOnly'] as bool? ?? false,
  );

  static String encodeList(List<AssistantTag> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
  static List<AssistantTag> decodeList(String raw) {
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in arr) AssistantTag.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const <AssistantTag>[];
    }
  }
}
