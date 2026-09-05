import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';
import 'encryption_service.dart';

class ChatService {
  // Firestore database instance.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Encryption service used to encrypt and decrypt messages.
  final _enc = EncryptionService.instance;

  // ── Get participants from chat ID ─────────────────────────────────────────

  // Extracts the two participant user IDs from the chat ID.
  List<String> _participantsFromChatId(String chatId) => chatId.split('_');

  // ── Start or resume a chat ────────────────────────────────────────────────

  // Creates a new chat or opens an existing conversation.
  Future<String> startChat(
    String userId,
    String otherUserId, {
    String otherUsername = '',
  }) async {
    // Sort the user IDs so the same pair always produces the same chat ID.
    final ids = [userId, otherUserId]..sort();
    final chatId = ids.join('_');

    final chatRef = _db.collection('chats').doc(chatId);
    final snap = await chatRef.get();

    // Create the chat document if it does not already exist.
    if (!snap.exists) {
      await chatRef.set({
        'chatId': chatId,

        // Store the participants in the same order used to create chatId.
        'participants': ids,

        // Initial chat information.
        'lastMessage': '',
        'lastTimestamp': FieldValue.serverTimestamp(),

        // Store usernames used for displaying the conversation.
        'displayNames': {
          userId: otherUsername,
          otherUserId: '',
        },

        // Indicates that messages in this chat use E2EE.
        'e2ee': true,
      });
    } else {
      // Update the other participant's display name when available.
      await chatRef.update({
        'displayNames.$userId': otherUsername,
      });
    }

    return chatId;
  }

  // ── Send a message ────────────────────────────────────────────────────────

  // Encrypts the message and stores it in Firestore.
  Future<void> sendMessage(String chatId, MessageModel message) async {
    // Get the two participants from the chat ID.
    final parts = _participantsFromChatId(chatId);
    final uid1 = parts.isNotEmpty ? parts[0] : '';
    final uid2 = parts.length > 1 ? parts[1] : '';

    // Encrypt the message content before storing it.
    final cipher = _enc.encrypt(message.content, uid1, uid2);

    // Create a message map containing the encrypted content.
    final encryptedMap = {
      ...message.toMap(),
      'content': cipher,
      'isEncrypted': true,
    };

    // Store the encrypted message in the messages subcollection.
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(message.messageId)
        .set(encryptedMap);

    // Update the chat preview with encrypted message information.
    await _db.collection('chats').doc(chatId).set({
      'lastMessage': '🔒 Encrypted message',
      'lastTimestamp': FieldValue.serverTimestamp(),
      'lastSenderId': message.senderId,

      // Make sure the sender remains in the participants list.
      'participants': FieldValue.arrayUnion([message.senderId]),
    }, SetOptions(merge: true));
  }

  // ── Mark a chat as read ───────────────────────────────────────────────────

  // Stores the time when a user last read the conversation.
  Future<void> markAsRead(String chatId, String userId) async {
    // Update only the current user's read timestamp.
    await _db.collection('chats').doc(chatId).set({
      'lastReadBy.$userId': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Real-time message stream ─────────────────────────────────────────────

  // Loads messages in real time and decrypts encrypted messages.
  Stream<List<MessageModel>> loadHistory(String chatId) {
    // Get the participants needed for encryption and decryption.
    final parts = _participantsFromChatId(chatId);
    final uid1 = parts.isNotEmpty ? parts[0] : '';
    final uid2 = parts.length > 1 ? parts[1] : '';

    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')

        // Display messages from oldest to newest.
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = Map<String, dynamic>.from(doc.data());

              // Decrypt the message when it is marked as encrypted.
              if (data['isEncrypted'] == true) {
                final cipher = data['content'] as String? ?? '';
                data['content'] = _enc.decrypt(cipher, uid1, uid2);
              }

              // Convert the Firestore data into a MessageModel.
              return MessageModel.fromMap(data);
            }).toList());
  }

  // ── Delete a message ──────────────────────────────────────────────────────

  // Deletes a specific message from the conversation.
  Future<void> deleteMessage(String chatId, String messageId) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .delete();
  }

  // ── Mark tasks as extracted ───────────────────────────────────────────────

  // Records that task extraction has already been performed for a message.
  Future<void> markTasksExtracted(String chatId, String messageId) async {
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'tasksExtracted': true,
    });
  }

  // ── Skip a suggested task ─────────────────────────────────────────────────

  // Stores the task ID that a user has chosen to skip.
  Future<void> skipTask(
      String chatId, String messageId, String taskId, String userId) async {
    // Store skipped tasks separately for each user.
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .set({
      'skippedTaskIdsByUser': {
        userId: FieldValue.arrayUnion([taskId]),
      },
    }, SetOptions(merge: true));
  }

  // ── Mark threat as recorded ──────────────────────────────────────────────

  // Records that a user has created or confirmed the threat dashboard record.
  Future<void> markThreatRecorded(
      String chatId, String messageId, String userId) async {
    // Store the threat record status separately for each user.
    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .set({
      'threatRecordedByUser': {
        userId: true,
      },
    }, SetOptions(merge: true));
  }

  // ── Pin / unpin a message ─────────────────────────────────────────────────

  // Pins a message so it can be identified as an important message.
  Future<void> pinMessage(String chatId, String messageId) async {
    await _db.collection('chats').doc(chatId).set({
      'pinnedMessages': FieldValue.arrayUnion([messageId]),
    }, SetOptions(merge: true));
  }

  // Removes a message from the pinned message list.
  Future<void> unpinMessage(String chatId, String messageId) async {
    await _db.collection('chats').doc(chatId).set({
      'pinnedMessages': FieldValue.arrayRemove([messageId]),
    }, SetOptions(merge: true));
  }

  // ── Pin / unpin an entire conversation ────────────────────────────────────

  // Adds or removes a chat from the user's pinned conversations.
  Future<void> togglePinChat(String chatId, String userId, bool pin) async {
    await _db.collection('chats').doc(chatId).set({
      'pinnedBy': pin
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    }, SetOptions(merge: true));
  }

  // ── Delete an entire conversation ─────────────────────────────────────────

  // Deletes all messages and then removes the chat document.
  Future<void> deleteChat(String chatId) async {
    final messagesRef =
        _db.collection('chats').doc(chatId).collection('messages');

    // Firestore does not automatically delete subcollections.
    // Delete messages in batches to avoid processing too many at once.
    while (true) {
      final snap = await messagesRef.limit(300).get();

      // Stop when there are no messages remaining.
      if (snap.docs.isEmpty) break;

      final batch = _db.batch();

      // Add each message deletion to the batch.
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      // Stop when the final batch contains fewer than 300 messages.
      if (snap.docs.length < 300) break;
    }

    // Delete the main chat document.
    await _db.collection('chats').doc(chatId).delete();
  }

  // ── Get all chats for a user ──────────────────────────────────────────────

  // Returns the conversations belonging to the specified user.
  Stream<List<Map<String, dynamic>>> getUserChats(String userId) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: userId)
        .snapshots()
        .asyncMap((snap) async {
      final docs = snap.docs;

      // Collect the IDs of the other participants.
      final otherIds = <String>{};

      for (final doc in docs) {
        final data = doc.data();

        final participants =
            (data['participants'] as List?)?.cast<String>() ?? [];

        // Find the participant who is not the current user.
        final otherId =
            participants.firstWhere((p) => p != userId, orElse: () => '');

        if (otherId.isNotEmpty) {
          otherIds.add(otherId);
        }
      }

      // Store usernames using their user IDs.
      final usernames = <String, String>{};
      final idList = otherIds.toList();

      // Retrieve usernames in small groups.
      for (var i = 0; i < idList.length; i += 10) {
        final end = (i + 10 > idList.length) ? idList.length : i + 10;

        final chunk = idList.sublist(i, end);

        if (chunk.isEmpty) continue;

        try {
          final userSnap = await _db
              .collection('users')
              .where(
                FieldPath.documentId,
                whereIn: chunk,
              )
              .get();

          // Store each user's username.
          for (final u in userSnap.docs) {
            usernames[u.id] = (u.data()['username'] as String?) ?? '';
          }
        } catch (_) {
          // Use stored display names if the username lookup fails.
        }
      }

      // Build the chat list for the current user.
      final chats = docs.map((doc) {
        final data = doc.data();

        // Check whether this chat document has a pending local update.
        final isPendingLocalWrite = doc.metadata.hasPendingWrites;

        final participants =
            (data['participants'] as List?)?.cast<String>() ?? [];

        // Find the other participant.
        final otherId =
            participants.firstWhere((p) => p != userId, orElse: () => '');

        // Get the username from the users collection.
        final liveUsername = usernames[otherId];

        // Get the stored display name as a fallback.
        final displayNames =
            (data['displayNames'] as Map<String, dynamic>?) ?? {};

        final storedName = displayNames[userId] as String?;

        // Select the best available name for the chat.
        final displayName = (liveUsername != null && liveUsername.isNotEmpty)
            ? liveUsername
            : ((storedName != null && storedName.isNotEmpty)
                ? storedName
                : doc.id);

        // Get the list of users who pinned the conversation.
        final pinnedBy = (data['pinnedBy'] as List?)?.cast<String>() ?? [];

        // ── Unread state ─────────────────────────────────────────────────

        // Get information about the latest message.
        final lastSenderId = data['lastSenderId'] as String?;
        final lastTimestamp = data['lastTimestamp'] as Timestamp?;

        // Get the last-read timestamp for each user.
        final lastReadBy = (data['lastReadBy'] as Map<String, dynamic>?) ?? {};

        // Get this user's last-read timestamp.
        final myLastRead = lastReadBy[userId] as Timestamp?;

        bool hasUnread = false;

        // A chat is unread when another user sent the latest message
        // after this user last read the conversation.
        if (lastSenderId != null &&
            lastSenderId != userId &&
            lastTimestamp != null) {
          if (myLastRead == null && isPendingLocalWrite) {
            // Treat the chat as read while the local update is waiting
            // for confirmation from the Firestore server.
            hasUnread = false;
          } else {
            hasUnread =
                myLastRead == null || lastTimestamp.compareTo(myLastRead) > 0;
          }
        }

        // Return the chat information used by the chat list UI.
        return {
          ...data,
          'chatId': doc.id,
          'displayName': displayName,
          'isPinned': pinnedBy.contains(userId),
          'hasUnread': hasUnread,
        };
      }).toList();

      // Sort pinned chats first, then sort by latest activity.
      chats.sort((a, b) {
        final aPinned = a['isPinned'] as bool? ?? false;
        final bPinned = b['isPinned'] as bool? ?? false;

        if (aPinned != bPinned) {
          return aPinned ? -1 : 1;
        }

        final aTime = a['lastTimestamp'] as Timestamp?;
        final bTime = b['lastTimestamp'] as Timestamp?;

        // Chats without messages are placed at the bottom.
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;

        // Most recently active chats appear first.
        return bTime.compareTo(aTime);
      });

      return chats;
    });
  }
}
