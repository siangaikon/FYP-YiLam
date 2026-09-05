// Represents a user account in the application.
// The model stores basic user information and their current
// online status for use in the messaging system.
class UserModel {
  // Unique identifier of the user.
  final String userId;

  // Username displayed in the application.
  final String username;

  // Email address associated with the user's account.
  final String email;

  // Indicates whether the user is currently online.
  bool isOnline;

  // Constructor used to create a UserModel object.
  UserModel({
    required this.userId,
    required this.username,
    required this.email,
    this.isOnline = false,
  });

  // Creates a UserModel object from data retrieved from Firestore.
  // The stored map values are converted into the corresponding
  // properties of the user model.
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      userId: map['userId'] ?? '',
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      isOnline: map['isOnline'] ?? false,
    );
  }

  // Converts the UserModel object into a map so that the user's
  // information can be stored in Firestore.
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'email': email,
      'isOnline': isOnline,
    };
  }
}
