class GenerationTask {
  final String id;
  final int userId;
  final String conversationId;
  final String providerSyncId;
  final List<Map<String, dynamic>> messages;
  final Map<String, dynamic> parameters;
  final String status;
  final List<Map<String, dynamic>> resultChunks;
  final String? finalContent;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  GenerationTask({
    required this.id,
    required this.userId,
    required this.conversationId,
    required this.providerSyncId,
    required this.messages,
    required this.parameters,
    required this.status,
    required this.resultChunks,
    this.finalContent,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'providerSyncId': providerSyncId,
    'status': status,
    'resultChunks': resultChunks,
    'finalContent': finalContent,
    'errorMessage': errorMessage,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
