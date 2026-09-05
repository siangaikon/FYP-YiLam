// Represents a security-related event recorded by the application.
// The model stores information such as the event type, user, IP address,
// timestamp, and whether the event is considered suspicious.
class SecurityLogModel {
  // Unique identifier for the security log.
  final String logId;

  // Unique identifier of the user associated with the security event.
  final String userId;

  // Type of security event being recorded.
  // Examples include 'login', 'logout', and 'failed_login'.
  final String eventType;

  // IP address associated with the security event.
  final String ipAddress;

  // Date and time when the security event occurred.
  final DateTime timestamp;

  // Indicates whether the security event has been identified as suspicious.
  final bool isSuspicious;

  // Constructor used to create a SecurityLogModel object.
  SecurityLogModel({
    required this.logId,
    required this.userId,
    required this.eventType,
    required this.ipAddress,
    required this.timestamp,
    this.isSuspicious = false,
  });

  // Creates a SecurityLogModel object from data retrieved from Firestore.
  // The stored map values are converted into the appropriate data types.
  factory SecurityLogModel.fromMap(Map<String, dynamic> map) {
    return SecurityLogModel(
      logId: map['logId'] ?? '',
      userId: map['userId'] ?? '',
      eventType: map['eventType'] ?? '',
      ipAddress: map['ipAddress'] ?? '',
      timestamp: DateTime.parse(map['timestamp']),
      isSuspicious: map['isSuspicious'] ?? false,
    );
  }

  // Converts the SecurityLogModel object into a map so that the
  // security log information can be stored in Firestore.
  Map<String, dynamic> toMap() {
    return {
      'logId': logId,
      'userId': userId,
      'eventType': eventType,
      'ipAddress': ipAddress,
      'timestamp': timestamp.toIso8601String(),
      'isSuspicious': isSuspicious,
    };
  }
}
