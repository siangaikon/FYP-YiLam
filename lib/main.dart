import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'screens/auth/auth_screen.dart';
import 'screens/chat/chat_list_screen.dart';
import 'screens/tasks/task_screen.dart';
import 'screens/threats/threat_screen.dart';
import 'screens/security/security_screen.dart';

import 'firebase_options.dart';

// Tracks whether the user is currently completing registration and OTP verification.
bool registrationInProgress = false;

// Application entry point.
void main() async {
  // Ensures Flutter is ready before initializing Firebase.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase using the configuration for the current platform.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Start the AutoSecureChat application.
  runApp(const AutoSecureChatApp());
}

// Main application widget.
class AutoSecureChatApp extends StatelessWidget {
  const AutoSecureChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Application name.
      title: 'AutoSecureChat',

      // Removes the debug banner from the application.
      debugShowCheckedModeBanner: false,

      // Defines the application theme.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 26, 153, 232),
        ),
        useMaterial3: true,
      ),

      // Start with the authentication state checker.
      home: const AuthGate(),
    );
  }
}

// Controls which screen is displayed based on the user's authentication state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen for changes to the Firebase authentication state.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show a loading indicator while checking authentication.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final firebaseUser = snapshot.data;

        // Show the authentication screen when no user is signed in.
        if (firebaseUser == null) {
          return const AuthScreen();
        }

        // Keep the authentication screen visible during registration and OTP verification.
        if (registrationInProgress) {
          return const AuthScreen();
        }

        // Check whether the authenticated user has a profile in Firestore.
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(firebaseUser.uid)
              .get(),
          builder: (context, userSnap) {
            // Show a loading indicator while retrieving the user profile.
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // Check whether the user's Firestore document exists.
            final userDocExists = userSnap.hasData && userSnap.data!.exists;

            // Sign out if there is no matching user profile.
            if (!userDocExists) {
              FirebaseAuth.instance.signOut();
              return const AuthScreen();
            }

            // Open the main application after successful authentication.
            return MainShell(userId: firebaseUser.uid);
          },
        );
      },
    );
  }
}

// Main application screen containing the four core sections.
class MainShell extends StatefulWidget {
  final String userId;

  const MainShell({super.key, required this.userId});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Stores the currently selected navigation tab.
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;

    // Create the main screens for the logged-in user.
    final screens = [
      ChatListScreen(userId: userId),
      TaskScreen(userId: userId),
      ThreatScreen(userId: userId),
      SecurityScreen(userId: userId),
    ];

    return Scaffold(
      // Display the currently selected screen.
      body: screens[_index],

      // Bottom navigation for the main application sections.
      bottomNavigationBar: NavigationBar(
        // Highlight the currently selected tab.
        selectedIndex: _index,

        // Change the displayed screen when a tab is selected.
        onDestinationSelected: (i) => setState(() => _index = i),

        // Define the four navigation destinations.
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_outlined),
            selectedIcon: Icon(Icons.task),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_outlined),
            selectedIcon: Icon(Icons.warning),
            label: 'Threats',
          ),
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Security',
          ),
        ],
      ),
    );
  }
}
