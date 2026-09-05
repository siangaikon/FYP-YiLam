// Represents one chat message and stores information required for
// messaging, encryption, task extraction, and threat detection.
class MessageModel {
  // Unique identifier of the message.
  final String messageId;

  // Unique identifier of the user who sent the message.
  final String senderId;

  // Display name of the message sender.
  final String senderName;

  // The actual message content.
  final String content;

  // Date and time when the message was sent.
  final DateTime timestamp;

  // Indicates whether the message is stored as encrypted content.
  final bool isEncrypted;

  // Indicates whether the message has been identified as a threat.
  bool isThreat;

  // Stores the current threat classification of the message.
  // Possible values are: 'unscanned', 'safe', 'suspicious', or 'malicious'.
  // The value is stored in Firestore so that the classification is
  // retained when the chat is reopened.
  String threatVerdict;

  // Indicates whether AI task extraction has already been performed
  // for this message. This prevents the same message from being
  // processed repeatedly when the chat is reopened.
  bool tasksExtracted;

  // Stores task IDs that each user has chosen to skip for this message.
  // The map uses the user's ID as the key so that each user's decision
  // is stored independently.
  Map<String, List<String>> skippedTaskIdsByUser;

  // Records whether a threat record has already been created or
  // confirmed for each user. This allows each participant to maintain
  // their own threat dashboard record for the same message.
  Map<String, bool> threatRecordedByUser;

  MessageModel({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.isEncrypted = true,
    this.isThreat = false,
    this.threatVerdict = 'unscanned',
    this.tasksExtracted = false,
    this.skippedTaskIdsByUser = const {},
    this.threatRecordedByUser = const {},
  });

  // Returns the task IDs that the specified user has skipped.
  List<String> skippedTaskIdsFor(String userId) =>
      skippedTaskIdsByUser[userId] ?? const [];

  // Checks whether the specified user already has a threat record
  // associated with this message.
  bool hasThreatRecordedFor(String userId) =>
      threatRecordedByUser[userId] == true;

  // Creates a MessageModel object from data retrieved from Firestore.
  // This converts the stored map data back into the application's
  // message model.
  factory MessageModel.fromMap(Map<String, dynamic> map) {
    // Retrieves the stored skipped task information.
    final rawSkipped = map['skippedTaskIdsByUser'];

    // Creates a map to store skipped task IDs for each user.
    final skippedByUser = <String, List<String>>{};

    // Converts the stored skipped task data into the expected format.
    if (rawSkipped is Map) {
      rawSkipped.forEach((key, value) {
        if (value is List) {
          skippedByUser[key as String] = value.cast<String>();
        }
      });
    }

    // Retrieves the stored threat-recording information.
    final rawRecorded = map['threatRecordedByUser'];

    // Creates a map to store threat-recording status for each user.
    final recordedByUser = <String, bool>{};

    // Converts the stored threat-recording data into the expected format.
    if (rawRecorded is Map) {
      rawRecorded.forEach((key, value) {
        recordedByUser[key as String] = value == true;
      });
    }

    // Creates and returns a MessageModel using the retrieved data.
    return MessageModel(
      messageId: map['messageId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Unknown',
      content: map['content'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
      isEncrypted: map['isEncrypted'] ?? true,
      isThreat: map['isThreat'] ?? false,
      threatVerdict: map['threatVerdict'] ?? 'unscanned',
      tasksExtracted: map['tasksExtracted'] ?? false,
      skippedTaskIdsByUser: skippedByUser,
      threatRecordedByUser: recordedByUser,
    );
  }

  // Converts the MessageModel into a map format so that the message
  // and its related information can be stored in Firestore.
  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderName': senderName,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isEncrypted': isEncrypted,
      'isThreat': isThreat,
      'threatVerdict': threatVerdict,
      'tasksExtracted': tasksExtracted,
      'skippedTaskIdsByUser': skippedTaskIdsByUser,
      'threatRecordedByUser': threatRecordedByUser,
    };
  }

  // Returns the message content with an encryption marker.
  String encrypt() => '[encrypted]$content';

  // Returns the stored message content in decrypted form.
  String decrypt() => content;
}
