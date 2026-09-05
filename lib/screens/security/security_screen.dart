import 'package:flutter/material.dart';
import '../../models/security_log_model.dart';
import '../../services/auth_service.dart';
import '../../services/security_service.dart';

// Screen used to display the user's security activity and login history.
class SecurityScreen extends StatefulWidget {
  // ID of the currently logged-in user.
  final String userId;

  const SecurityScreen({super.key, required this.userId});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

// State class for SecurityScreen.
class _SecurityScreenState extends State<SecurityScreen> {
  // Service used to access security-related Firestore data.
  final SecurityService _securityService = SecurityService();

  // Service used to retrieve user information.
  final AuthService _authService = AuthService();

  // Stream that continuously listens for the user's security logs.
  late final Stream<List<SecurityLogModel>> _logsStream =
      _securityService.getUserLogs(widget.userId);

  // Stream for failed login attempts associated with the user's email.
  Stream<List<SecurityLogModel>>? _failedAttemptsStream;

  // Indicates whether the user's email is still being loaded.
  bool _loadingEmail = true;

  // Stores the time when the user last acknowledged suspicious activity.
  DateTime? _suspiciousAckAt;

  // Indicates whether the suspicious activity acknowledgement is being processed.
  bool _acknowledging = false;

  @override
  void initState() {
    super.initState();

    // Load the user's email and subscribe to failed login attempts.
    _loadEmailAndSubscribe();
  }

  // Retrieves the user's email and creates the failed-login stream.
  Future<void> _loadEmailAndSubscribe() async {
    // Get the current user's information.
    final user = await _authService.getUser(widget.userId);

    // Get the time when suspicious activity was last acknowledged.
    final ackAt = await _securityService.getSuspiciousAckTime(widget.userId);

    // Stop if the screen has already been removed.
    if (!mounted) return;

    setState(() {
      // Listen for failed login attempts using the user's email.
      _failedAttemptsStream =
          _securityService.getFailedLoginAttempts(user?.email ?? '');

      // Store the acknowledgement time.
      _suspiciousAckAt = ackAt;

      // Finish the loading state.
      _loadingEmail = false;
    });
  }

  // Marks the current suspicious activity as acknowledged by the user.
  Future<void> _acknowledgeSuspicious() async {
    setState(() => _acknowledging = true);

    // Record the current time for the acknowledgement.
    final now = DateTime.now();

    try {
      // Save the acknowledgement time to Firestore.
      await _securityService.acknowledgeSuspiciousActivity(widget.userId);

      // Stop if the screen is no longer active.
      if (!mounted) return;

      // Update the UI immediately.
      setState(() => _suspiciousAckAt = now);
    } catch (_) {
      // Show an error message if the acknowledgement fails.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not dismiss — try again.'),
        ),
      );
    } finally {
      // Stop showing the loading state.
      if (mounted) {
        setState(() => _acknowledging = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Store the security service for easier access.
    final securityService = _securityService;

    // Get the current user's ID.
    final userId = widget.userId;

    // Get the current application's colour scheme.
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Top application bar.
      appBar: AppBar(
        title: const Text('Security Centre'),
        centerTitle: false,

        // Actions displayed on the right side of the AppBar.
        actions: [
          // Button for clearing security logs.
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: () async {
              // Ask the user for confirmation before deleting logs.
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Clear security logs'),
                  content: const Text(
                    'This will permanently delete all your security activity records. Continue?',
                  ),
                  actions: [
                    // Cancel the deletion.
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),

                    // Confirm the deletion.
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );

              // Delete the logs if the user confirmed.
              if (confirmed == true) {
                await securityService.clearLogs(userId);
              }
            },
          ),
        ],
      ),

      // Display a loading indicator while the user's email is being loaded.
      body: _loadingEmail
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : StreamBuilder<List<SecurityLogModel>>(
              // Listen to the normal security log stream.
              stream: _logsStream,

              builder: (context, logsSnapshot) {
                return StreamBuilder<List<SecurityLogModel>>(
                  // Listen to failed login attempts.
                  stream: _failedAttemptsStream,

                  builder: (context, failedSnapshot) {
                    // Show a loading indicator while the security logs
                    // are being retrieved for the first time.
                    if (logsSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !logsSnapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    // Display an error message if the security logs
                    // cannot be loaded.
                    if (logsSnapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Error icon.
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: scheme.error,
                              ),

                              const SizedBox(height: 12),

                              // Error title.
                              const Text(
                                'Could not load security logs.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 6),

                              // Display the error details.
                              Text(
                                '${logsSnapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    // Combine normal security logs and failed login attempts.
                    final logs = [
                      ...(logsSnapshot.data ?? []),
                      ...(failedSnapshot.data ?? []),
                    ]
                      // Sort the logs from newest to oldest.
                      ..sort(
                        (a, b) => b.timestamp.compareTo(a.timestamp),
                      );

                    // Display an empty state when there are no security events.
                    if (logs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Security shield icon.
                            Icon(
                              Icons.shield_outlined,
                              size: 64,
                              color: scheme.outlineVariant,
                            ),

                            const SizedBox(height: 16),

                            // Empty state message.
                            const Text(
                              'No security events recorded.',
                            ),
                          ],
                        ),
                      );
                    }

                    // Check whether there is suspicious activity
                    // that has not been acknowledged yet.
                    final hasSuspicious = logs.any(
                      (l) =>
                          l.isSuspicious &&
                          (_suspiciousAckAt == null ||
                              l.timestamp.isAfter(_suspiciousAckAt!)),
                    );

                    return Column(
                      children: [
                        // Suspicious activity warning banner.
                        if (hasSuspicious)
                          Container(
                            width: double.infinity,
                            color: Colors.red[50],
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                // Warning icon.
                                const Icon(
                                  Icons.warning_amber,
                                  color: Colors.red,
                                  size: 18,
                                ),

                                const SizedBox(width: 8),

                                // Warning message.
                                Expanded(
                                  child: Text(
                                    'Suspicious authentication activity detected. '
                                    'Review the highlighted events below.',
                                    style: TextStyle(
                                      color: Colors.red[700],
                                      fontSize: 13,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // Show a loading indicator while the
                                // acknowledgement is being saved.
                                _acknowledging
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : TextButton(
                                        // Acknowledge the suspicious activity.
                                        onPressed: _acknowledgeSuspicious,
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red[700],
                                          minimumSize: Size.zero,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: const Text(
                                          "It's me",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                              ],
                            ),
                          ),

                        // Security event timeline.
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(16),

                            // Number of security events to display.
                            itemCount: logs.length,

                            // Divider between each security event.
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: 56,
                            ),

                            // Build each security log item.
                            itemBuilder: (context, index) {
                              final log = logs[index];

                              return _SecurityLogTile(
                                log: log,
                                scheme: scheme,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

// Widget used to display one security event in the timeline.
class _SecurityLogTile extends StatelessWidget {
  // Security log data for this item.
  final SecurityLogModel log;

  // Application colour scheme.
  final ColorScheme scheme;

  const _SecurityLogTile({
    required this.log,
    required this.scheme,
  });

  // Returns the appropriate icon, colour and label
  // based on the type of security event.
  static _EventStyle _styleFor(
    String eventType,
    bool isSuspicious,
  ) {
    // Suspicious events use a warning icon and red colour.
    if (isSuspicious && eventType != 'failed_login') {
      return const _EventStyle(
        Icons.gpp_bad,
        Colors.red,
        'Suspicious Activity',
      );
    }

    // Select the display style based on the event type.
    switch (eventType) {
      case 'login':
        // Successful login event.
        return const _EventStyle(
          Icons.login,
          Colors.green,
          'Successful Login',
        );

      case 'logout':
        // Logout event.
        return const _EventStyle(
          Icons.logout,
          Colors.blue,
          'Logout',
        );

      case 'failed_login':
        // Failed login attempt.
        return const _EventStyle(
          Icons.lock_person,
          Colors.orange,
          'Failed Login Attempt',
        );

      case 'registration':
        // New account registration.
        return const _EventStyle(
          Icons.person_add,
          Colors.purple,
          'Registration',
        );

      default:
        // Display a general information icon for unknown event types.
        return _EventStyle(
          Icons.info_outline,
          Colors.grey,
          eventType,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the icon, colour and label for this event.
    final style = _styleFor(
      log.eventType,
      log.isSuspicious,
    );

    // Convert the timestamp to the device's local timezone.
    final ts = log.timestamp.toLocal();

    // Format the date and time for display.
    final formatted = '${ts.day.toString().padLeft(2, '0')}/'
        '${ts.month.toString().padLeft(2, '0')}/'
        '${ts.year}  '
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}';

    return Container(
      // Highlight suspicious events with a light red background.
      color: log.isSuspicious ? Colors.red[50] : null,

      // Add vertical spacing around the event.
      padding: const EdgeInsets.symmetric(vertical: 10),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Security event icon.
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              // Use a transparent version of the event colour
              // as the icon background.
              color: style.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              style.icon,
              size: 18,
              color: style.color,
            ),
          ),

          const SizedBox(width: 12),

          // Security event information.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Event name.
                Text(
                  style.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: log.isSuspicious ? Colors.red : null,
                  ),
                ),

                const SizedBox(height: 2),

                // Date and time of the event.
                Text(
                  formatted,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 2),

                // Display the IP address associated with the event.
                Row(
                  children: [
                    Icon(
                      Icons.language,
                      size: 11,
                      color: scheme.outlineVariant,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'IP: ${log.ipAddress}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.outlineVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Stores the display information for a security event.
class _EventStyle {
  // Icon used for the event.
  final IconData icon;

  // Colour used for the event.
  final Color color;

  // Text label displayed for the event.
  final String label;

  const _EventStyle(
    this.icon,
    this.color,
    this.label,
  );
}
