import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC encryption service used for end-to-end encrypted messaging.
///
/// The encryption key is derived from the two participant UIDs.
/// Both participants can independently generate the same key.
class EncryptionService {
  // Stores the single instance of the encryption service.
  static EncryptionService? _instance;

  // Private constructor used to create the singleton instance.
  EncryptionService._();

  // Returns the existing instance or creates one if needed.
  static EncryptionService get instance => _instance ??= EncryptionService._();

  // ── Derive AES-256 key ────────────────────────────────────────────────────

  // Generates a consistent AES key from the two participant UIDs.
  enc.Key _deriveKey(String uid1, String uid2) {
    // Sort the UIDs so both participants generate the same key.
    final ids = [uid1, uid2]..sort();

    // Convert the combined UIDs into bytes.
    final raw = utf8.encode(ids.join('_'));

    // Generate a SHA-256 hash.
    // SHA-256 produces 32 bytes, which is suitable for AES-256.
    final hash = sha256.convert(raw).bytes;

    // Convert the hash bytes into an AES encryption key.
    return enc.Key(Uint8List.fromList(hash));
  }

  // ── Encrypt message ──────────────────────────────────────────────────────

  // Encrypts plaintext and returns the IV and ciphertext in Base64 format.
  //
  // Output format:
  // "<base64_iv>:<base64_ciphertext>"
  String encrypt(String plaintext, String uid1, String uid2) {
    try {
      // Generate the AES-256 key.
      final key = _deriveKey(uid1, uid2);

      // Generate a random 16-byte initialization vector.
      final iv = enc.IV.fromSecureRandom(16);

      // Create an AES encrypter using CBC mode.
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      // Encrypt the message using the generated IV.
      final encrypted = encrypter.encrypt(plaintext, iv: iv);

      // Store the IV together with the encrypted ciphertext.
      return '${base64.encode(iv.bytes)}:${encrypted.base64}';
    } catch (_) {
      // Return the original message if encryption fails.
      return plaintext;
    }
  }

  // ── Decrypt message ───────────────────────────────────────────────────────

  // Decrypts a message using the same participant-based AES key.
  String decrypt(String ciphertext, String uid1, String uid2) {
    try {
      // Separate the IV and ciphertext.
      final parts = ciphertext.split(':');

      // Return the original value if it is not in encrypted format.
      if (parts.length != 2) return ciphertext;

      // Decode the Base64 IV.
      final iv = enc.IV(base64.decode(parts[0]));

      // Generate the same AES-256 key used during encryption.
      final key = _deriveKey(uid1, uid2);

      // Create an AES decrypter using CBC mode.
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      // Decrypt the Base64 ciphertext.
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (_) {
      // Return a placeholder if the message cannot be decrypted.
      return '[encrypted message]';
    }
  }
}
