class QuickPhrase {
  final String id;
  final String title;
  final String content;
  final bool isGlobal; // true = global, false = assistant-specific
  final String? assistantId; // null for global phrases
  // Sync metadata
  final int? updatedAt;
  final int? deletedAt;
  final bool localOnly;

  const QuickPhrase({
    required this.id,
    required this.title,
    required this.content,
    this.isGlobal = true,
    this.assistantId,
    this.updatedAt,
    this.deletedAt,
    this.localOnly = false,
  });

  QuickPhrase copyWith({
    String? id,
    String? title,
    String? content,
    bool? isGlobal,
    String? assistantId,
    int? updatedAt,
    int? deletedAt,
    bool? localOnly,
  }) {
    return QuickPhrase(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      isGlobal: isGlobal ?? this.isGlobal,
      assistantId: assistantId ?? this.assistantId,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      localOnly: localOnly ?? this.localOnly,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'isGlobal': isGlobal,
    'assistantId': assistantId,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'localOnly': localOnly,
  };

  static QuickPhrase fromJson(Map<String, dynamic> json) => QuickPhrase(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    content: (json['content'] as String?) ?? '',
    isGlobal: json['isGlobal'] as bool? ?? true,
    assistantId: json['assistantId'] as String?,
    updatedAt: (json['updatedAt'] as num?)?.toInt(),
    deletedAt: (json['deletedAt'] as num?)?.toInt(),
    localOnly: json['localOnly'] as bool? ?? false,
  );
}
