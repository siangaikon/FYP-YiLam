import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'security_service.dart';

class AuthService {
  // Firebase Authentication instance.
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Firestore database instance.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Service used to record security-related events.
  final SecurityService _security = SecurityService();

  // Stream that monitors the current authentication state.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Username validation ───────────────────────────────────────────────────

  // Checks whether the username contains both letters and numbers.
  bool isValidUsername(String username) {
    final value = username.trim();
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasNumber = RegExp(r'[0-9]').hasMatch(value);
    final validChars = RegExp(r'^[A-Za-z0-9]+$').hasMatch(value);

    return hasLetter && hasNumber && validChars;
  }

  // ── Password validation ───────────────────────────────────────────────────

  // Checks whether the password meets the required security rules.
  bool isStrongPassword(String password) {
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial = RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
    final hasMinLength = password.length >= 8;

    return hasUppercase &&
        hasLowercase &&
        hasNumber &&
        hasSpecial &&
        hasMinLength;
  }

  // ── Username uniqueness check ─────────────────────────────────────────────

  // Checks whether the username is already registered.
  Future<bool> isUsernameTaken(String username) async {
    final snap = await _db
        .collection('users')
        .where('usernameLower', isEqualTo: username.toLowerCase().trim())
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  // ── Generate 6-digit OTP ──────────────────────────────────────────────────

  // Generates a secure random six-digit OTP.
  String _generateOtp() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  // ── Store OTP in Firestore ────────────────────────────────────────────────

  // Stores the OTP temporarily for email verification.
  Future<String> _storePendingVerification({
    required String uid,
    required String email,
    required String username,
  }) async {
    final otp = _generateOtp();

    // OTP expires after 10 minutes.
    final expiry = DateTime.now().add(const Duration(minutes: 10));

    await _db.collection('pending_verifications').doc(uid).set({
      'uid': uid,
      'email': email,
      'username': username,
      'otp': otp,
      'expiresAt': expiry.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'verified': false,
    });

    return otp;
  }

  // ── Register ──────────────────────────────────────────────────────────────

  // Creates a Firebase account and stores the OTP for verification.
  Future<Map<String, dynamic>> register(
      String email, String password, String username) async {
    // Validate the username before creating the account.
    if (!isValidUsername(username)) {
      throw Exception('Username must contain letters and numbers only.');
    }

    // Validate the password strength.
    if (!isStrongPassword(password)) {
      throw Exception(
        'Password must contain uppercase, lowercase, number, special symbol, and be at least 8 characters.',
      );
    }

    // Make sure the username is unique.
    if (await isUsernameTaken(username)) {
      throw Exception('username-already-taken');
    }

    // Create the Firebase Authentication account.
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (cred.user == null) throw Exception('Failed to create account.');

    final uid = cred.user!.uid;
    final trimmedUsername = username.trim();

    // Store the OTP before signing the user out.
    final otp = await _storePendingVerification(
      uid: uid,
      email: email,
      username: trimmedUsername,
    );

    // Sign out until the email verification is completed.
    await _auth.signOut();

    return {
      'uid': uid,
      'email': email,
      'username': trimmedUsername,
      // OTP is used by the UI to send the verification email.
      'otp': otp,
    };
  }

  // ── Verify OTP and activate account ──────────────────────────────────────

  // Verifies the OTP and creates the user's Firestore profile.
  Future<void> verifyOtpAndActivate(
    String uid,
    String enteredOtp, {
    String? email,
    String? password,
  }) async {
    // Get the pending verification record.
    final docRef = _db.collection('pending_verifications').doc(uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      throw Exception('No pending verification found. Please register again.');
    }

    final data = doc.data()!;
    final storedOtp = data['otp'] as String? ?? '';
    final expiresAt = DateTime.parse(data['expiresAt'] as String);
    final alreadyVerified = data['verified'] as bool? ?? false;

    // Prevent the same OTP from being used again.
    if (alreadyVerified) {
      throw Exception('already-verified');
    }

    // Check whether the OTP has expired.
    if (DateTime.now().isAfter(expiresAt)) {
      throw Exception('otp-expired');
    }

    // Compare the entered OTP with the stored OTP.
    if (enteredOtp.trim() != storedOtp) {
      throw Exception('invalid-otp');
    }

    final storedEmail = data['email'] as String;
    final username = data['username'] as String;

    // Create the user's Firestore profile.
    final userDocRef = _db.collection('users').doc(uid);
    await userDocRef.set({
      'userId': uid,
      'username': username,
      'usernameLower': username.toLowerCase(),
      'email': storedEmail,
      'isOnline': false,
      'emailVerified': true,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Re-authenticate the user when login details are available.
    bool reAuthed = false;
    if (email != null &&
        password != null &&
        email.isNotEmpty &&
        password.isNotEmpty) {
      try {
        await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        reAuthed = true;
      } catch (e) {
        debugPrint('[AuthService] Re-auth failed during OTP activation: $e');
      }
    }

    // Record the account registration event.
    try {
      await _security.logEvent(uid, 'register');
    } catch (e) {
      debugPrint('[AuthService] security_log write failed: $e');
    }

    // Remove the temporary OTP record after successful verification.
    await docRef.delete();

    // Sign out again so the user can log in normally.
    if (reAuthed) {
      await _auth.signOut();
    }
  }

  // ── Resend OTP ────────────────────────────────────────────────────────────

  // Generates and stores a new OTP for an existing verification request.
  Future<String> resendOtp(String uid) async {
    final docRef = _db.collection('pending_verifications').doc(uid);
    final doc = await docRef.get();

    if (!doc.exists) {
      throw Exception('No pending verification found. Please register again.');
    }

    final newOtp = _generateOtp();

    // Give the new OTP another 10 minutes before it expires.
    final newExpiry = DateTime.now().add(const Duration(minutes: 10));

    await docRef.update({
      'otp': newOtp,
      'expiresAt': newExpiry.toIso8601String(),
    });

    return newOtp;
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  // Authenticates the user and returns their profile information.
  Future<UserModel?> login(String email, String password) async {
    try {
      UserCredential cred;

      try {
        // Sign in using Firebase Authentication.
        cred = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        // Return only the Firebase error code for easier error handling.
        throw Exception(e.code);
      }

      if (cred.user == null) return null;

      final uid = cred.user!.uid;
      final docRef = _db.collection('users').doc(uid);
      final doc = await docRef.get();

      // Make sure the user has completed account activation.
      if (!doc.exists) {
        await _auth.signOut();
        throw Exception('account-not-activated');
      }

      // Get the username from the user's profile.
      final existingUsername =
          (doc.data()?['username'] as String?)?.trim() ?? '';

      // Reject incomplete user profiles.
      if (existingUsername.isEmpty) {
        await _auth.signOut();
        throw Exception('account-not-activated');
      }

      // Update the user's online status.
      await docRef.update({'isOnline': true});

      // Get the updated user profile.
      final updatedDoc = await docRef.get();
      final user = UserModel.fromMap(updatedDoc.data()!);

      // Record the successful login event.
      try {
        await _security.logEvent(user.userId, 'login');
      } catch (e) {
        debugPrint('[AuthService] security_log write failed on login: $e');
      }

      return user;
    } catch (e) {
      final raw = e.toString();

      // Identify errors that should not be treated as suspicious login attempts.
      final isAppError = raw.contains('account-not-activated') ||
          raw.contains('network-request-failed');

      // Record other failed login attempts for security monitoring.
      if (!isAppError) {
        try {
          await _security.logFailedAttempt(email);
        } catch (_) {}
      }

      rethrow;
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  // Logs the logout event, updates the user's status, and signs out.
  Future<void> logout([String? userId]) async {
    final uid = userId?.isNotEmpty == true ? userId! : _auth.currentUser?.uid;

    try {
      if (uid != null && uid.isNotEmpty) {
        // Record the logout event.
        await _security.logEvent(uid, 'logout');

        // Set the user's online status to false.
        await _db.collection('users').doc(uid).update({'isOnline': false});
      }
    } catch (_) {
      // Continue signing out even if logging or Firestore update fails.
    }

    // Sign out from Firebase Authentication.
    await _auth.signOut();
  }

  // ── Get user profile ──────────────────────────────────────────────────────

  // Retrieves a user's profile from Firestore.
  Future<UserModel?> getUser(String userId) async {
    final doc = await _db.collection('users').doc(userId).get();

    if (!doc.exists) return null;

    return UserModel.fromMap(doc.data()!);
  }

  // ── Search users by username prefix ──────────────────────────────────────

  // Searches for users whose usernames start with the given query.
  Future<List<UserModel>> searchByUsername(
    String query, {
    String? excludeUserId,
  }) async {
    final lower = query.toLowerCase().trim();

    if (lower.isEmpty) return [];

    final snap = await _db
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: lower)
        .where('usernameLower', isLessThan: '${lower}z')
        .limit(10)
        .get();

    // Convert Firestore documents into UserModel objects.
    // Exclude the current user's own account when requested.
    return snap.docs
        .map((doc) => UserModel.fromMap(doc.data()))
        .where((u) => u.userId != excludeUserId)
        .toList();
  }

  // ── Search users by exact userId ─────────────────────────────────────────

  // Finds a user using their exact Firebase user ID.
  Future<UserModel?> searchByUserId(
    String userId, {
    String? excludeUserId,
  }) async {
    final trimmed = userId.trim();

    if (trimmed.isEmpty) return null;
    if (trimmed == excludeUserId) return null;

    final doc = await _db.collection('users').doc(trimmed).get();

    if (!doc.exists) return null;

    return UserModel.fromMap(doc.data()!);
  }

  // ── Flexible user search ─────────────────────────────────────────────────

  // Searches by user ID first, then falls back to username search.
  Future<List<UserModel>> searchUsersFlexible(
    String query, {
    String? excludeUserId,
  }) async {
    final trimmed = query.trim();

    if (trimmed.isEmpty) return [];

    // Try an exact user ID search first.
    final byUid = await searchByUserId(
      trimmed,
      excludeUserId: excludeUserId,
    );

    if (byUid != null) return [byUid];

    // If no user ID matches, search by username.
    return searchByUsername(
      trimmed,
      excludeUserId: excludeUserId,
    );
  }
}
