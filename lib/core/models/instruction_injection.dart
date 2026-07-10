class InstructionInjection {
  final String id;
  final String title;
  final String prompt;
  final String group;
  // Sync metadata
  final int? updatedAt;
  final int? deletedAt;
  final bool localOnly;

  const InstructionInjection({
    required this.id,
    required this.title,
    required this.prompt,
    this.group = '',
    this.updatedAt,
    this.deletedAt,
    this.localOnly = false,
  });

  InstructionInjection copyWith({
    String? id,
    String? title,
    String? prompt,
    String? group,
    int? updatedAt,
    int? deletedAt,
    bool? localOnly,
  }) {
    return InstructionInjection(
      id: id ?? this.id,
      title: title ?? this.title,
      prompt: prompt ?? this.prompt,
      group: group ?? this.group,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      localOnly: localOnly ?? this.localOnly,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'prompt': prompt,
    'group': group,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'localOnly': localOnly,
  };

  static InstructionInjection fromJson(Map<String, dynamic> json) =>
      InstructionInjection(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        prompt: (json['prompt'] as String?) ?? '',
        group: (json['group'] as String?) ?? '',
        updatedAt: (json['updatedAt'] as num?)?.toInt(),
        deletedAt: (json['deletedAt'] as num?)?.toInt(),
        localOnly: json['localOnly'] as bool? ?? false,
      );
}
