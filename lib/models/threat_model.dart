// Defines the severity levels that can be assigned to a detected threat.
enum ThreatLevel { low, medium, high }

// Represents a security threat detected by the application.
// The model stores information about the threat, its severity,
// detection time, source, and resolution status.
class ThreatModel {
  // Unique identifier of the detected threat.
  final String threatId;

  // UID of the user associated with the threat.
  // Used to associate the threat with the correct user in Firestore.
  final String userId;

  // Type of threat detected.
  // Examples include 'phishing', 'spam', and 'malicious_url'.
  final String threatType;

  // Severity level assigned to the detected threat.
  final ThreatLevel severity;

  // Date and time when the threat was detected.
  final DateTime detectedAt;

  // URL associated with the detected threat, if available.
  final String sourceUrl;

  // Indicates whether the threat has been resolved by the user.
  bool isResolved;

  // ID of the chat where the threat was detected.
  final String sourceChatId;

  // Username of the person who sent the message containing
  // the detected threat.
  final String senderUsername;

  // Constructor used to create a ThreatModel object.
  ThreatModel({
    required this.threatId,
    required this.userId,
    required this.threatType,
    required this.severity,
    required this.detectedAt,
    required this.sourceUrl,
    this.isResolved = false,
    this.sourceChatId = '',
    this.senderUsername = '',
  });

  // Creates a ThreatModel object from data retrieved from Firestore.
  // The stored map values are converted into the appropriate data types.
  factory ThreatModel.fromMap(Map<String, dynamic> map) {
    return ThreatModel(
      threatId: map['threatId'] ?? '',
      userId: map['userId'] ?? '',
      threatType: map['threatType'] ?? '',

      // Converts the stored severity string into a ThreatLevel enum.
      // If the stored value is invalid, low severity is used by default.
      severity: ThreatLevel.values.firstWhere(
        (e) => e.name == map['severity'],
        orElse: () => ThreatLevel.low,
      ),

      detectedAt: DateTime.parse(map['detectedAt']),
      sourceUrl: map['sourceUrl'] ?? '',
      isResolved: map['isResolved'] ?? false,
      sourceChatId: map['sourceChatId'] ?? '',
      senderUsername: map['senderUsername'] ?? '',
    );
  }

  // Converts the ThreatModel object into a map so that the threat
  // information can be stored in Firestore.
  Map<String, dynamic> toMap() {
    return {
      'threatId': threatId,
      'userId': userId,
      'threatType': threatType,
      'severity': severity.name,
      'detectedAt': detectedAt.toIso8601String(),
      'sourceUrl': sourceUrl,
      'isResolved': isResolved,
      'sourceChatId': sourceChatId,
      'senderUsername': senderUsername,
    };
  }
}
