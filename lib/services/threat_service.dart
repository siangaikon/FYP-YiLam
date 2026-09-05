import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/threat_model.dart';
import '../models/message_model.dart';
import 'ai_service.dart';

class ThreatService {
  // Firestore database instance.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // AI service used to analyse message threats.
  final AIService _ai = AIService();

  // ── Scan message for threats ───────────────────────────────────────────────

  // Analyses a message using the AI threat detection pipeline.
  // The result is also saved to Firestore for future reference.
  Future<ThreatAnalysisResult> scanMessage(
    MessageModel message,
    String userId, {
    String chatId = '',
  }) async {
    // Analyse the message content using the AI service.
    final result = await _ai.analyseThreat(
      message.content,
      message.messageId,
      userId,
      chatId: chatId,
      senderUsername: message.senderName,
    );

    // ── Save threat verdict to message ─────────────────────────────────────

    // Stores the threat classification on the message document.
    if (chatId.isNotEmpty) {
      try {
        final updateData = <String, dynamic>{
          'threatVerdict': result.verdict,
        };

        // Mark the message as a threat when a threat is detected.
        if (result.isThreat && result.threat != null) {
          updateData['isThreat'] = true;
        }

        // Update the message with the threat analysis result.
        await _db
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc(message.messageId)
            .update(updateData);
      } catch (_) {
        // Continue if the message document cannot be updated.
      }
    }

    // ── Save threat record ──────────────────────────────────────────────────

    // Store the detected threat in the threats collection.
    if (result.isThreat && result.threat != null) {
      final threatDoc = _db.collection('threats').doc(result.threat!.threatId);

      // Create the threat record only if it does not already exist.
      await _db.runTransaction((tx) async {
        final snap = await tx.get(threatDoc);

        if (!snap.exists) {
          tx.set(threatDoc, result.threat!.toMap());
        }
      });
    }

    // Return the threat analysis result.
    return result;
  }

  // ── Resolve/dismiss a threat ──────────────────────────────────────────────

  // Marks a threat as resolved in Firestore.
  Future<void> dismissThreat(String threatId) async {
    await _db.collection('threats').doc(threatId).update({'isResolved': true});
  }

  // ── Get active threats ────────────────────────────────────────────────────

  // Returns unresolved threats belonging to the user.
  Stream<List<ThreatModel>> getActiveThreats(String userId) {
    return _db
        .collection('threats')
        .where('userId', isEqualTo: userId)
        .where('isResolved', isEqualTo: false)
        .snapshots()
        .map((snap) {
      // Convert Firestore documents into ThreatModel objects.
      final list =
          snap.docs.map((doc) => ThreatModel.fromMap(doc.data())).toList();

      // Sort threats from newest to oldest.
      list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

      return list;
    });
  }

  // ── Get all threats ───────────────────────────────────────────────────────

  // Returns all threats belonging to the user, including resolved threats.
  Stream<List<ThreatModel>> getAllThreats(String userId) {
    return _db
        .collection('threats')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      // Convert Firestore documents into ThreatModel objects.
      final list =
          snap.docs.map((doc) => ThreatModel.fromMap(doc.data())).toList();

      // Sort threats from newest to oldest.
      list.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));

      return list;
    });
  }
}
