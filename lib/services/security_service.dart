import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/security_log_model.dart';

class SecurityService {
  // Firestore database instance.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // UUID generator used to create unique log IDs.
  final _uuid = const Uuid();

  // ── IP address ────────────────────────────────────────────────────────────

  // Stores the public IP address for the current session.
  String? _cachedIp;

  // Public IP services used as fallbacks if one service is unavailable.
  static const _ipServices = [
    'https://api.ipify.org',
    'https://api64.ipify.org',
    'https://checkip.amazonaws.com',
    'https://icanhazip.com',
  ];

  // Retrieves the user's public IP address.
  Future<String> _getPublicIp() async {
    // Return the cached IP if it has already been retrieved.
    if (_cachedIp != null) return _cachedIp!;

    // Try each IP service until one responds successfully.
    for (final url in _ipServices) {
      try {
        final response =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));

        // Check whether the request was successful.
        if (response.statusCode == 200) {
          final ip = response.body.trim();

          // Check that the returned value looks like an IP address.
          if (ip.isNotEmpty && (ip.contains('.') || ip.contains(':'))) {
            _cachedIp = ip;
            return _cachedIp!;
          }
        }
      } catch (e) {
        // Try the next IP service if the current one fails.
        continue;
      }
    }

    // Return unknown if no IP service is available.
    return 'unknown';
  }

  // ── Log a security event ──────────────────────────────────────────────────

  // Creates and stores a security event in Firestore.
  Future<void> logEvent(
    String userId,
    String eventType, {
    bool isSuspicious = false,
  }) async {
    // Retrieve the user's public IP address.
    final ip = await _getPublicIp();

    // Create a security log record.
    final log = SecurityLogModel(
      logId: _uuid.v4(),
      userId: userId,
      eventType: eventType,
      ipAddress: ip,
      timestamp: DateTime.now(),
      isSuspicious: isSuspicious,
    );

    // Save the security log to Firestore.
    await _db.collection('security_logs').doc(log.logId).set(log.toMap());
  }

  // ── Log a failed login attempt ────────────────────────────────────────────

  // Stores a failed login attempt before the user is authenticated.
  Future<void> logFailedAttempt(String email) async {
    // Retrieve the user's public IP address.
    final ip = await _getPublicIp();

    // Generate a unique ID for the failed login attempt.
    final attemptId = _uuid.v4();

    // Store the failed login information in Firestore.
    await _db.collection('failed_login_attempts').doc(attemptId).set({
      'attemptId': attemptId,
      'email': email.trim().toLowerCase(),
      'ipAddress': ip,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // ── Get all logs for a user ───────────────────────────────────────────────

  // Returns all security logs belonging to a specific user.
  Stream<List<SecurityLogModel>> getUserLogs(String userId) {
    return _db
        .collection('security_logs')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SecurityLogModel.fromMap(doc.data()))
            .toList());
  }

  // ── Get suspicious logs ───────────────────────────────────────────────────

  // Returns only security logs marked as suspicious.
  Stream<List<SecurityLogModel>> getSuspiciousLogs(String userId) {
    return _db
        .collection('security_logs')
        .where('userId', isEqualTo: userId)
        .where('isSuspicious', isEqualTo: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SecurityLogModel.fromMap(doc.data()))
            .toList());
  }

  // ── Get failed login attempts ─────────────────────────────────────────────

  // Returns failed login attempts associated with the user's email.
  Stream<List<SecurityLogModel>> getFailedLoginAttempts(String email) {
    // Normalize the email before searching Firestore.
    final normalized = email.trim().toLowerCase();

    // Return an empty stream when no email is provided.
    if (normalized.isEmpty) return const Stream.empty();

    return _db
        .collection('failed_login_attempts')
        .where('email', isEqualTo: normalized)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();

              // Convert the failed login record into SecurityLogModel
              // so it can be displayed using the existing security log UI.
              return SecurityLogModel(
                logId: data['attemptId'] ?? doc.id,
                userId: '',
                eventType: 'failed_login',
                ipAddress: data['ipAddress'] ?? 'unknown',
                timestamp: DateTime.tryParse(data['timestamp'] ?? '') ??
                    DateTime.now(),
                isSuspicious: true,
              );
            }).toList());
  }

  // ── Clear all logs for a user ─────────────────────────────────────────────

  // Deletes all security logs belonging to a specific user.
  Future<void> clearLogs(String userId) async {
    // Retrieve all logs for the user.
    final snap = await _db
        .collection('security_logs')
        .where('userId', isEqualTo: userId)
        .get();

    // Create a Firestore batch for deleting multiple documents.
    final batch = _db.batch();

    // Add each log document to the delete batch.
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }

    // Apply all deletions to Firestore.
    await batch.commit();
  }

  // ── Acknowledge suspicious activity ──────────────────────────────────────

  // Stores the time when the user acknowledges suspicious activity.
  Future<void> acknowledgeSuspiciousActivity(String userId) async {
    await _db.collection('users').doc(userId).update({
      'securityAckAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Get suspicious activity acknowledgement time ─────────────────────────

  // Retrieves the last time the user acknowledged suspicious activity.
  Future<DateTime?> getSuspiciousAckTime(String userId) async {
    try {
      // Retrieve the user's Firestore document.
      final doc = await _db.collection('users').doc(userId).get();

      // Get the acknowledgement timestamp.
      final ts = doc.data()?['securityAckAt'];

      // Convert Firestore Timestamp to DateTime.
      if (ts is Timestamp) return ts.toDate();

      // Return null if no acknowledgement time exists.
      return null;
    } catch (_) {
      // Return null if the timestamp cannot be retrieved.
      return null;
    }
  }
}
