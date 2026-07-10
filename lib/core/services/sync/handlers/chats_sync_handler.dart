import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/models/conversation.dart';
import 'package:Kelivo/core/models/sync_enums.dart';
import 'package:Kelivo/core/services/sync/sync_category_handler.dart';

/// Sync handler for chat conversations and messages (Hive-backed).
///
/// The payload may represent either a [Conversation] or a [ChatMessage].
/// Presence of a `conversationId` key in the payload distinguishes messages
/// from conversations.
class ChatsSyncHandler extends SyncCategoryHandler {
  static const String _conversationsBoxName = 'conversations';
  static const String _messagesBoxName = 'messages';

  @override
  SyncCategory get category => SyncCategory.chats;

  @override
  Future<List<Map<String, dynamic>>> collectLocalChanges(
    int sinceCursor,
  ) async {
    final results = <Map<String, dynamic>>[];

    if (!Hive.isBoxOpen(_conversationsBoxName) ||
        !Hive.isBoxOpen(_messagesBoxName)) {
      debugPrint(
        '[ChatsSyncHandler] Hive boxes not open — skipping collectLocalChanges',
      );
      return results;
    }

    final conversationsBox = Hive.box<Conversation>(_conversationsBoxName);
    final messagesBox = Hive.box<ChatMessage>(_messagesBoxName);

    // Collect changed conversations.
    for (final key in conversationsBox.keys) {
      try {
        final conv = conversationsBox.get(key);
        if (conv == null) continue;
        if (conv.localOnly) continue;
        final updatedAtMs = conv.updatedAt.millisecondsSinceEpoch;
        if (updatedAtMs <= sinceCursor) continue;
        results.add({
          'recordId': conv.id,
          'payload': conv.toJson(),
          'updatedAt': updatedAtMs,
          if (conv.deletedAt != null) 'deletedAt': conv.deletedAt,
        });
      } catch (e) {
        debugPrint('[ChatsSyncHandler] Error collecting conversation $key: $e');
      }
    }

    // Collect changed messages.
    for (final key in messagesBox.keys) {
      try {
        final msg = messagesBox.get(key);
        if (msg == null) continue;
        if (msg.localOnly) continue;
        if (msg.isStreaming) continue; // never push a live stream
        final updatedAt = msg.updatedAt;
        if (updatedAt == null || updatedAt <= sinceCursor) continue;
        results.add({
          'recordId': msg.id,
          'payload': msg.toJson(),
          'updatedAt': updatedAt,
          if (msg.deletedAt != null) 'deletedAt': msg.deletedAt,
        });
      } catch (e) {
        debugPrint('[ChatsSyncHandler] Error collecting message $key: $e');
      }
    }

    return results;
  }

  @override
  Future<void> applyRemoteChanges(List<Map<String, dynamic>> changes) async {
    if (changes.isEmpty) return;

    // Guard: Hive boxes must already be open (ChatService.init has been called).
    if (!Hive.isBoxOpen(_conversationsBoxName) ||
        !Hive.isBoxOpen(_messagesBoxName)) {
      debugPrint(
        '[ChatsSyncHandler] Hive boxes not open — skipping applyRemoteChanges',
      );
      return;
    }

    final conversationsBox = Hive.box<Conversation>(_conversationsBoxName);
    final messagesBox = Hive.box<ChatMessage>(_messagesBoxName);

    for (final change in changes) {
      try {
        final recordId = change['recordId'] as String;
        final payload = change['payload'] as Map<String, dynamic>?;
        final remoteUpdatedAt = change['updatedAt'] as int;
        final remoteDeletedAt = change['deletedAt'] as int?;

        // Determine whether this is a message or conversation.
        final isMessage =
            payload != null && payload.containsKey('conversationId');

        if (isMessage) {
          await _applyMessageChange(
            messagesBox,
            conversationsBox,
            recordId: recordId,
            payload: payload,
            remoteUpdatedAt: remoteUpdatedAt,
            remoteDeletedAt: remoteDeletedAt,
          );
        } else {
          await _applyConversationChange(
            conversationsBox,
            recordId: recordId,
            payload: payload,
            remoteUpdatedAt: remoteUpdatedAt,
            remoteDeletedAt: remoteDeletedAt,
          );
        }
      } catch (e) {
        debugPrint('[ChatsSyncHandler] Error applying change: $e');
      }
    }
  }

  Future<void> _applyConversationChange(
    Box<Conversation> box, {
    required String recordId,
    required Map<String, dynamic>? payload,
    required int remoteUpdatedAt,
    required int? remoteDeletedAt,
  }) async {
    final local = box.get(recordId);

    if (local == null) {
      // New record from remote
      if (remoteDeletedAt != null) return; // Already deleted remotely — skip
      if (payload == null) return;
      final conversation = Conversation.fromJson(payload);
      await box.put(recordId, conversation);
      return;
    }

    // LWW: remote wins only if strictly newer
    final localUpdatedAt = local.updatedAt.millisecondsSinceEpoch;
    if (remoteUpdatedAt <= localUpdatedAt) return;

    if (remoteDeletedAt != null) {
      // Remote says delete — soft-delete locally
      final deleted = local.copyWith(deletedAt: remoteDeletedAt);
      await box.put(recordId, deleted);
    } else if (payload != null) {
      // Remote is newer — update local from remote payload
      final updated = Conversation.fromJson(payload);
      await box.put(recordId, updated);
    }
  }

  Future<void> _applyMessageChange(
    Box<ChatMessage> messagesBox,
    Box<Conversation> conversationsBox, {
    required String recordId,
    required Map<String, dynamic> payload,
    required int remoteUpdatedAt,
    required int? remoteDeletedAt,
  }) async {
    final local = messagesBox.get(recordId);

    // Skip records that are actively streaming — never overwrite a live stream.
    if (local != null && local.isStreaming) return;

    if (local == null) {
      // New message from remote
      if (remoteDeletedAt != null) return; // Already deleted remotely — skip
      final message = ChatMessage.fromJson(payload);
      await messagesBox.put(recordId, message);

      // Ensure the parent conversation knows about this message.
      _ensureMessageInConversation(
        conversationsBox,
        message.conversationId,
        recordId,
      );
      return;
    }

    // LWW: remote wins only if strictly newer
    final localUpdatedAt = local.updatedAt ?? 0;
    if (remoteUpdatedAt <= localUpdatedAt) return;

    if (remoteDeletedAt != null) {
      // Remote says delete — soft-delete locally
      final deleted = local.copyWith(deletedAt: remoteDeletedAt);
      await messagesBox.put(recordId, deleted);
    } else {
      // Remote is newer — update local from remote payload
      final updated = ChatMessage.fromJson(payload);
      await messagesBox.put(recordId, updated);
    }
  }

  /// Ensure [messageId] is present in the parent conversation's messageIds.
  void _ensureMessageInConversation(
    Box<Conversation> box,
    String conversationId,
    String messageId,
  ) {
    final conversation = box.get(conversationId);
    if (conversation == null) return;
    if (conversation.messageIds.contains(messageId)) return;
    conversation.messageIds.add(messageId);
    box.put(conversationId, conversation);
  }
}
