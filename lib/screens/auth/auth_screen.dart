import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../../services/auth_service.dart';
import '../../main.dart';

// Stores the configuration required to communicate with the EmailJS service.
// The configuration values are retrieved from Firebase Remote Config
// instead of being directly written into the application source code.
class _EmailJsConfig {
  // EmailJS service identifier.
  final String serviceId;

  // EmailJS email template identifier.
  final String templateId;

  // Public key used to identify the EmailJS account.
  final String publicKey;

  // Private access token used when sending the email request.
  final String privateKey;

  // Constructor used to create an EmailJS configuration object.
  const _EmailJsConfig({
    required this.serviceId,
    required this.templateId,
    required this.publicKey,
    required this.privateKey,
  });

  // Checks whether all required EmailJS configuration values are available.
  bool get isConfigured =>
      serviceId.isNotEmpty &&
      templateId.isNotEmpty &&
      publicKey.isNotEmpty &&
      privateKey.isNotEmpty;
}

// Loads the EmailJS configuration from Firebase Remote Config.
// This allows the application to retrieve the required configuration
// values at runtime.
Future<_EmailJsConfig> _loadEmailJsConfig() async {
  try {
    // Gets the Firebase Remote Config instance.
    final rc = FirebaseRemoteConfig.instance;

    // Configures the Remote Config fetch timeout and minimum
    // interval between configuration updates.
    await rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ));

    // Fetches the latest configuration values and activates them.
    await rc.fetchAndActivate();

    // Creates the EmailJS configuration using values stored
    // in Firebase Remote Config.
    return _EmailJsConfig(
      serviceId: rc.getString('emailjs_service_id'),
      templateId: rc.getString('emailjs_template_id'),
      publicKey: rc.getString('emailjs_public_key'),
      privateKey: rc.getString('emailjs_private_key'),
    );
  } catch (e) {
    // Logs the error if Remote Config cannot be loaded.
    debugPrint('[EmailJS] Remote Config fetch failed: $e');

    // Returns an empty configuration when loading fails.
    return const _EmailJsConfig(
      serviceId: '',
      templateId: '',
      publicKey: '',
      privateKey: '',
    );
  }
}

// Sends a one-time password (OTP) to the user's email address
// using the EmailJS REST API.
Future<void> _sendOtpEmail({
  required _EmailJsConfig config,
  required String toEmail,
  required String otp,
  required String username,
}) async {
  // Prevents the email request from being sent when the EmailJS
  // configuration is incomplete.
  if (!config.isConfigured) {
    throw Exception('EmailJS is not configured. Check Firebase Remote Config.');
  }

  // Calculates the expiry time of the OTP.
  final expiry = DateTime.now().add(const Duration(minutes: 15));

  // Converts the expiry hour into 12-hour format.
  final hour = expiry.hour % 12 == 0 ? 12 : expiry.hour % 12;

  // Formats the minute value with two digits.
  final minute = expiry.minute.toString().padLeft(2, '0');

  // Determines whether the expiry time is AM or PM.
  final period = expiry.hour >= 12 ? 'PM' : 'AM';

  // Creates a readable expiry time for the email template.
  final timeString = '$hour:$minute $period';

  // EmailJS REST API endpoint used to send the verification email.
  final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

  // Sends the OTP and other template parameters to EmailJS.
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'service_id': config.serviceId,
      'template_id': config.templateId,
      'user_id': config.publicKey,
      'accessToken': config.privateKey,
      'template_params': {
        'to_email': toEmail,
        'username': username,
        'otp': otp,
        'passcode': otp,
        'time': timeString,
      },
    }),
  );

  // Throws an exception when EmailJS does not return a successful response.
  if (response.statusCode != 200) {
    throw Exception('EmailJS error ${response.statusCode}: ${response.body}');
  }
}

// Authentication screen containing the sign-in, registration,
// and email verification interfaces.
class AuthScreen extends StatefulWidget {
  // Constructor for the authentication screen.
  const AuthScreen({super.key});

  // Creates the mutable state associated with AuthScreen.
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

// Manages the state and authentication operations of AuthScreen.
class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  // Controls switching between the Sign In and Register tabs.
  late TabController _tabController;

  // Provides access to authentication operations.
  final _authService = AuthService();

  // Controllers for the login email and password fields.
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  // Controllers for the registration form fields.
  final _regUsernameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();
  final _regConfirmCtrl = TextEditingController();

  // Controls whether the OTP verification interface is displayed.
  bool _showOtpStep = false;

  // Stores the UID of the account being verified.
  String? _pendingUid;

  // Stores the email address associated with the pending registration.
  String? _pendingEmail;

  // Temporarily stores the password required during account verification.
  String? _pendingPassword;

  // Stores the username associated with the pending registration.
  String? _pendingUsername;

  // Controllers for the six OTP input fields.
  final List<TextEditingController> _otpCtrl =
      List.generate(6, (_) => TextEditingController());

  // Focus nodes used to move between OTP input fields.
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  // Indicates whether a login operation is currently running.
  bool _loginLoading = false;

  // Indicates whether a registration operation is currently running.
  bool _regLoading = false;

  // Indicates whether an OTP operation is currently running.
  bool _otpLoading = false;

  // Controls the visibility of the login password.
  bool _loginPasswordVisible = false;

  // Controls the visibility of the registration password.
  bool _regPasswordVisible = false;

  // Stores an error or warning message displayed to the user.
  String? _errorMessage;

  // Stores the EmailJS configuration after it has been loaded.
  // This avoids repeatedly retrieving the same configuration during
  // the current application session.
  _EmailJsConfig? _emailJsConfig;

  // Initializes the authentication screen.
  @override
  void initState() {
    super.initState();

    // Creates a tab controller for the Sign In and Register tabs.
    _tabController = TabController(length: 2, vsync: this);

    // Clears temporary messages whenever the user changes tabs.
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _showOtpStep = false;
        });
      }
    });

    // Pre-loads the EmailJS configuration so that it is available
    // when the user starts the registration process.
    _loadEmailJsConfig().then((cfg) {
      if (mounted) _emailJsConfig = cfg;
    });
  }

  // Releases controllers and other resources when the screen is removed.
  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _regConfirmCtrl.dispose();

    // Releases all OTP text controllers.
    for (final c in _otpCtrl) {
      c.dispose();
    }

    // Releases all OTP focus nodes.
    for (final f in _otpFocus) {
      f.dispose();
    }

    super.dispose();
  }

  // Validates the username entered during registration.
  String? _validateUsername(String username) {
    // Checks that the username length is between 3 and 20 characters.
    if (username.length < 3 || username.length > 20) {
      return 'Username must be 3–20 characters.';
    }

    // Allows only letters and numbers in the username.
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(username)) {
      return 'Only letters and numbers allowed.';
    }

    // Requires the username to contain at least one letter.
    if (!RegExp(r'[A-Za-z]').hasMatch(username)) {
      return 'Username must contain at least one letter.';
    }

    // Requires the username to contain at least one number.
    if (!RegExp(r'[0-9]').hasMatch(username)) {
      return 'Username must contain at least one number.';
    }

    return null;
  }

  // Validates the password entered during registration.
  String? _validatePassword(String password) {
    // Requires the password to contain at least eight characters.
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    // Requires at least one uppercase letter.
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter.';
    }

    // Requires at least one lowercase letter.
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must contain at least one lowercase letter.';
    }

    // Requires at least one number.
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one number.';
    }

    // Requires at least one special character.
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'Password must contain at least one special symbol.';
    }

    return null;
  }

  // Handles the user login process.
  Future<void> _login() async {
    // Retrieves and removes unnecessary spaces from the input fields.
    final email = _loginEmailCtrl.text.trim();
    final password = _loginPasswordCtrl.text.trim();

    // Checks whether all required login fields have been entered.
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    // Displays the loading state while authentication is being performed.
    setState(() {
      _loginLoading = true;
      _errorMessage = null;
    });

    try {
      // Sends the login credentials to the authentication service.
      await _authService.login(email, password);
    } catch (e) {
      // Displays a user-friendly error when login fails.
      if (mounted) {
        setState(() => _errorMessage = _friendlyError(e.toString()));
      }
    } finally {
      // Removes the login loading state after the operation completes.
      if (mounted) {
        setState(() => _loginLoading = false);
      }
    }
  }

  // Handles the user registration process and starts OTP verification.
  Future<void> _register() async {
    // Retrieves the registration form values.
    final username = _regUsernameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final password = _regPasswordCtrl.text.trim();
    final confirm = _regConfirmCtrl.text.trim();

    // Checks that all registration fields have been completed.
    if (username.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirm.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    // Validates the username format.
    final usernameError = _validateUsername(username);
    if (usernameError != null) {
      setState(() => _errorMessage = usernameError);
      return;
    }

    // Validates the password strength.
    final passwordError = _validatePassword(password);
    if (passwordError != null) {
      setState(() => _errorMessage = passwordError);
      return;
    }

    // Ensures that both password fields contain the same value.
    if (password != confirm) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    // Displays the registration loading state.
    setState(() {
      _regLoading = true;
      _errorMessage = null;
    });

    // Indicates that registration is currently being processed.
    registrationInProgress = true;

    try {
      // Creates the user account through the authentication service.
      final result = await _authService.register(
        email,
        password,
        username,
      );

      // Retrieves the generated OTP and user ID from the registration result.
      final otp = result['otp'] as String;
      final uid = result['uid'] as String;

      // Loads the EmailJS configuration required to send the OTP email.
      _EmailJsConfig config;
      try {
        config = _emailJsConfig ?? await _loadEmailJsConfig();

        // Stores the loaded configuration for later use.
        if (mounted) _emailJsConfig = config;
      } catch (_) {
        // Uses an empty configuration if Remote Config loading fails.
        config = const _EmailJsConfig(
            serviceId: '', templateId: '', publicKey: '', privateKey: '');
      }

      // Attempts to send the generated OTP to the user's email address.
      String? emailSendWarning;
      try {
        await _sendOtpEmail(
          config: config,
          toEmail: email,
          otp: otp,
          username: username,
        );
      } catch (emailErr) {
        // Stores a warning when the OTP email cannot be sent.
        emailSendWarning =
            'Could not send verification email. Please check your spam folder.';

        // Logs the email sending error for debugging purposes.
        debugPrint('[AuthScreen] OTP email send failed: $emailErr');
      }

      // Updates the screen to display the OTP verification interface.
      if (mounted) {
        setState(() {
          _pendingUid = uid;
          _pendingEmail = email;
          _pendingPassword = password;
          _pendingUsername = username;
          _showOtpStep = true;
          _regLoading = false;
          _errorMessage = emailSendWarning;
        });

        // Clears any previous OTP input values.
        for (final c in _otpCtrl) {
          c.clear();
        }

        // Places the cursor in the first OTP input field.
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _otpFocus[0].requestFocus();
        });
      }
    } catch (e) {
      // Resets the registration state when registration fails.
      registrationInProgress = false;

      // Logs the registration error.
      debugPrint('[Register] FAILED: ${e.toString()}');

      // Displays a user-friendly registration error.
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(e.toString());
          _regLoading = false;
        });
      }
    }
  }

  // Verifies the six-digit OTP entered by the user.
  Future<void> _verifyOtp() async {
    // Combines all six OTP input fields into a single code.
    final otp = _otpCtrl.map((c) => c.text.trim()).join();

    // Checks that the complete six-digit OTP has been entered.
    if (otp.length < 6) {
      setState(() => _errorMessage = 'Please enter the full 6-digit code.');
      return;
    }

    // Displays the OTP verification loading state.
    setState(() {
      _otpLoading = true;
      _errorMessage = null;
    });

    try {
      // Sends the OTP to the authentication service for verification.
      await _authService.verifyOtpAndActivate(
        _pendingUid!,
        otp,
        email: _pendingEmail,
        password: _pendingPassword,
      );

      if (mounted) {
        // Clears the registration form after successful verification.
        _regUsernameCtrl.clear();
        _regEmailCtrl.clear();
        _regPasswordCtrl.clear();
        _regConfirmCtrl.clear();

        // Clears the OTP input fields.
        for (final c in _otpCtrl) {
          c.clear();
        }

        // Resets the OTP and pending registration state.
        setState(() {
          _showOtpStep = false;
          _pendingUid = null;
          _pendingEmail = null;
          _pendingPassword = null;
          _pendingUsername = null;
          _otpLoading = false;
        });

        // Marks the registration process as completed.
        registrationInProgress = false;

        // Returns the user to the Sign In tab.
        _tabController.animateTo(0);

        // Displays a confirmation message after successful verification.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Email verified! You can now sign in.'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      // Displays a user-friendly error when OTP verification fails.
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(e.toString());
          _otpLoading = false;
        });
      }
    }
  }

  // Generates and sends a new OTP to the user's registered email.
  Future<void> _resendOtp() async {
    // Stops the operation if there is no pending registration.
    if (_pendingUid == null || _pendingEmail == null) return;

    // Displays the OTP loading state.
    setState(() {
      _otpLoading = true;
      _errorMessage = null;
    });

    try {
      // Requests a new OTP from the authentication service.
      final newOtp = await _authService.resendOtp(_pendingUid!);

      // Loads the cached EmailJS configuration or retrieves it if necessary.
      final config = _emailJsConfig ?? await _loadEmailJsConfig();

      // Sends the new OTP to the user's email address.
      await _sendOtpEmail(
        config: config,
        toEmail: _pendingEmail!,
        otp: newOtp,
        username: _pendingUsername ?? '',
      );

      if (mounted) {
        // Removes the loading state after the new OTP has been sent.
        setState(() => _otpLoading = false);

        // Informs the user that a new verification code was sent.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New verification code sent. Check your inbox.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      // Displays an error when the OTP cannot be resent.
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(e.toString());
          _otpLoading = false;
        });
      }
    }
  }

  // Cancels the OTP verification process and returns to the
  // normal authentication interface.
  void _cancelOtp() {
    // Marks the registration process as no longer active.
    registrationInProgress = false;

    // Clears the pending registration and OTP information.
    setState(() {
      _showOtpStep = false;
      _pendingUid = null;
      _pendingEmail = null;
      _pendingPassword = null;
      _pendingUsername = null;
      _errorMessage = null;

      // Clears all OTP input fields.
      for (final c in _otpCtrl) {
        c.clear();
      }
    });
  }

  // Converts authentication and registration errors into
  // messages that are easier for users to understand.
  String _friendlyError(String raw) {
    // Handles an incorrect OTP.
    if (raw.contains('invalid-otp')) {
      return 'Incorrect code. Please try again.';
    }

    // Handles an expired OTP.
    if (raw.contains('otp-expired')) {
      return 'Code expired. Tap "Resend code" to get a new one.';
    }

    // Handles an account that has already been verified.
    if (raw.contains('already-verified')) {
      return 'Account already verified. Please sign in.';
    }

    // Handles accounts that have not completed verification.
    if (raw.contains('account-not-activated')) {
      return 'Account not activated. Please complete email verification.';
    }

    // Handles usernames that are already registered.
    if (raw.contains('username-already-taken')) {
      return 'That username is already taken.';
    }

    // Handles attempts to sign in with an unregistered email.
    if (raw.contains('user-not-found')) {
      return 'This Gmail/email is not registered. Please check the address or create an account.';
    }

    // Handles incorrect login credentials.
    if (raw.contains('wrong-password') || raw.contains('invalid-credential')) {
      return 'Incorrect email or password. Please try again.';
    }

    // Handles disabled accounts.
    if (raw.contains('user-disabled')) {
      return 'This account has been disabled. Contact support for help.';
    }

    // Handles excessive authentication attempts.
    if (raw.contains('too-many-requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }

    // Handles an email address that is already registered.
    if (raw.contains('email-already-in-use')) {
      return 'This email is already registered.';
    }

    // Handles invalid email addresses.
    if (raw.contains('invalid-email')) {
      return 'Please enter a valid email address.';
    }

    // Handles weak passwords.
    if (raw.contains('weak-password')) {
      return 'Password is too weak.';
    }

    // Handles network connectivity problems.
    if (raw.contains('network-request-failed')) {
      return 'No internet connection. Please check your network and try again.';
    }

    // Displays a general message for unrecognised errors.
    return 'Something went wrong. Please try again.';
  }

  // Builds the main authentication screen.
  @override
  Widget build(BuildContext context) {
    // Retrieves the current application's color scheme.
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,

      // Keeps the authentication content within the safe display area.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Displays the application logo, name, and description.
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: scheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Application name and description.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AutoSecureChat',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      Text(
                        'AI-powered secure messaging',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 36),

              // Displays the OTP verification interface when
              // the user is completing email verification.
              if (_showOtpStep)
                _otpVerificationStep(scheme)
              else ...[
                // Displays the Sign In and Register tabs.
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: scheme.onPrimary,
                    unselectedLabelColor: scheme.onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Sign In'),
                      Tab(text: 'Register'),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Displays authentication errors when available.
                if (_errorMessage != null) _errorBanner(scheme),

                // Displays the login and registration forms
                // inside the tab view.
                SizedBox(
                  height: 450,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _loginForm(scheme),
                      _registerForm(scheme),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Builds the email OTP verification interface.
  Widget _otpVerificationStep(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Provides a button for cancelling the OTP verification process.
        GestureDetector(
          onTap: _cancelOtp,
          child: Row(
            children: [
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Back',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Displays an email verification icon.
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mark_email_read_outlined,
              color: scheme.primary,
              size: 36,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Displays the OTP verification title.
        Text(
          'Verify your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),

        const SizedBox(height: 8),

        // Displays the email address where the OTP was sent.
        Text(
          'We sent a 6-digit code to\n${_pendingEmail ?? ''}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: scheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(height: 28),

        // Displays an error or warning related to OTP verification.
        if (_errorMessage != null) ...[
          _otpMessageBanner(scheme),
          const SizedBox(height: 12),
        ],

        // Creates six separate input fields for the OTP digits.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Container(
              width: 44,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _otpCtrl[i],
                focusNode: _otpFocus[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,

                // Restricts the OTP fields to numeric characters.
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],

                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),

                decoration: InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding: EdgeInsets.zero,
                ),

                // Controls movement between OTP input fields
                // and automatically submits the OTP after the final digit.
                onChanged: (value) {
                  if (value.isNotEmpty && i < 5) {
                    _otpFocus[i + 1].requestFocus();
                  }

                  if (value.isEmpty && i > 0) {
                    _otpFocus[i - 1].requestFocus();
                  }

                  // Automatically verifies the OTP after
                  // the sixth digit has been entered.
                  if (i == 5 && value.isNotEmpty) {
                    _verifyOtp();
                  }
                },
              ),
            );
          }),
        ),

        const SizedBox(height: 24),

        // Button used to submit and verify the entered OTP.
        FilledButton(
          onPressed: _otpLoading ? null : _verifyOtp,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _otpLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Verify Email',
                  style: TextStyle(fontSize: 15),
                ),
        ),

        const SizedBox(height: 16),

        // Button used to request another OTP code.
        Center(
          child: TextButton(
            onPressed: _otpLoading ? null : _resendOtp,
            child: Text(
              'Resend code',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Builds the Sign In form.
  Widget _loginForm(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Email input field for login.
        _field(
          controller: _loginEmailCtrl,
          label: 'Email',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: 14),

        // Password input field for login.
        _field(
          controller: _loginPasswordCtrl,
          label: 'Password',
          icon: Icons.lock_outline,
          obscure: !_loginPasswordVisible,

          // Allows the user to show or hide the password.
          suffixIcon: IconButton(
            icon: Icon(
              _loginPasswordVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => setState(
              () => _loginPasswordVisible = !_loginPasswordVisible,
            ),
          ),

          // Allows login when the user presses the keyboard submit button.
          onSubmitted: (_) => _login(),
        ),

        const SizedBox(height: 16),

        // Sign In button.
        _primaryButton(
          label: 'Sign In',
          loading: _loginLoading,
          onPressed: _login,
        ),
      ],
    );
  }

  // Builds the Register form.
  Widget _registerForm(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Username input field.
        _field(
          controller: _regUsernameCtrl,
          label: 'Username',
          icon: Icons.alternate_email,
          helperText: 'Letters + numbers required (e.g. alice1)',
        ),

        const SizedBox(height: 14),

        // Email input field.
        _field(
          controller: _regEmailCtrl,
          label: 'Email',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: 14),

        // Password input field.
        _field(
          controller: _regPasswordCtrl,
          label: 'Password',
          icon: Icons.lock_outline,
          obscure: !_regPasswordVisible,
          helperText: '8+ chars, uppercase, lowercase, number & symbol',

          // Allows the user to show or hide the registration password.
          suffixIcon: IconButton(
            icon: Icon(
              _regPasswordVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: () => setState(
              () => _regPasswordVisible = !_regPasswordVisible,
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Confirmation field used to verify the entered password.
        _field(
          controller: _regConfirmCtrl,
          label: 'Confirm Password',
          icon: Icons.lock_outline,
          obscure: !_regPasswordVisible,

          // Allows registration when the user submits the form
          // using the keyboard.
          onSubmitted: (_) => _register(),
        ),

        const SizedBox(height: 20),

        // Button used to create a new account.
        _primaryButton(
          label: 'Create Account',
          loading: _regLoading,
          onPressed: _register,
        ),
      ],
    );
  }

  // Builds the error message banner used on the authentication forms.
  Widget _errorBanner(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Error icon.
          Icon(
            Icons.error_outline,
            color: scheme.onErrorContainer,
            size: 18,
          ),

          const SizedBox(width: 8),

          // Displays the error message.
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Builds the message banner displayed during OTP verification.
  // Email sending problems are displayed as warnings, while other
  // OTP errors use the standard error banner.
  Widget _otpMessageBanner(ColorScheme scheme) {
    // Checks whether the current message is related to email delivery.
    final isEmailWarning =
        _errorMessage != null && _errorMessage!.contains('verification email');

    if (isEmailWarning) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: Colors.amber.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.amber.shade400,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Warning icon.
            Icon(
              Icons.warning_amber_outlined,
              color: Colors.amber.shade800,
              size: 18,
            ),

            const SizedBox(width: 8),

            // Displays the email delivery warning.
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Displays other OTP errors using the standard error banner.
    return _errorBanner(scheme);
  }

  // Builds a reusable text input field used by the login
  // and registration forms.
  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    ValueChanged<String>? onSubmitted,
    String? helperText,
  }) {
    return TextField(
      // Connects the field to its corresponding text controller.
      controller: controller,

      // Hides the text when the field is used for a password.
      obscureText: obscure,

      // Defines the keyboard type used for the field.
      keyboardType: keyboardType,

      // Handles keyboard submission when provided.
      onSubmitted: onSubmitted,

      decoration: InputDecoration(
        // Label displayed for the input field.
        labelText: label,

        // Optional helper text displayed below the field.
        helperText: helperText,

        // Icon displayed at the beginning of the field.
        prefixIcon: Icon(icon),

        // Optional icon displayed at the end of the field.
        suffixIcon: suffixIcon,

        // Defines the border appearance of the field.
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),

        // Defines the internal spacing of the input field.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  // Builds a reusable primary button used by the authentication forms.
  Widget _primaryButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      // Disables the button while the related operation is running.
      onPressed: loading ? null : onPressed,

      // Defines the button's padding and rounded shape.
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // Displays a loading indicator during an active operation.
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 15),
            ),
    );
  }
}
