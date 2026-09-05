import 'package:flutter_test/flutter_test.dart';

import 'package:autosecurechat/main.dart';

// Main entry point for the test.
void main() {
  // Tests whether the main application widget can be created successfully.
  testWidgets('smoke test', (WidgetTester tester) async {
    // Build the AutoSecureChat application.
    await tester.pumpWidget(const AutoSecureChatApp());

    // Wait for all animations and pending widget updates to complete.
    await tester.pumpAndSettle();
  });
}
