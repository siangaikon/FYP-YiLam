import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../models/message_model.dart';
import '../../models/task_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/task_service.dart';
import '../../services/threat_service.dart';

// Main chat screen for one-to-one messaging.
class ChatScreen extends StatefulWidget {
  // Unique ID of the chat.
  final String chatId;

  // ID of the currently logged-in user.
  final String userId;

  // Optional username/title displayed in the app bar.
  final String? chatTitle;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.userId,
    this.chatTitle,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

// State class responsible for chat messages, tasks, and threat detection.
class _ChatScreenState extends State<ChatScreen> {
  // Controller for the message input field.
  final _controller = TextEditingController();

  // Controller used to control scrolling in the message list.
  final _scrollController = ScrollController();

  // Service used for sending, loading, and managing chat messages.
  final _chatService = ChatService();

  // Service used for extracting and saving tasks.
  final _taskService = TaskService();

  // Service used for detecting suspicious or malicious content.
  final _threatService = ThreatService();

  // Service used to retrieve user information.
  final _authService = AuthService();

  // Generates unique IDs for new messages.
  final _uuid = const Uuid();

  // Gets the user ID of the other participant in the chat.
  String get _otherUserId {
    // The chat ID contains both user IDs separated by "_".
    final parts = widget.chatId.split('_');

    // Returns the ID that is different from the current user's ID.
    return parts.firstWhere(
      (p) => p != widget.userId,
      orElse: () => '',
    );
  }

  // Stores the current threat status of each message.
  //
  // Possible values:
  // safe, suspicious, malicious, scanning.
  //
  // This is mainly used for displaying the threat status in the UI.
  final Map<String, String> _threatStatus = {};

  // Keeps track of messages that are currently being scanned.
  final Set<String> _pendingThreatScanIds = {};

  // Stores message IDs whose threat warning was dismissed by the user.
  final Set<String> _dismissedThreatIds = {};

  // Stores AI-extracted tasks for each message.
  final Map<String, List<TaskModel>> _extractedTasks = {};

  // Stores task IDs that have already been added to the user's dashboard.
  final Set<String> _savedTaskIds = {};

  // Prevents the same message from being processed repeatedly.
  final Set<String> _processedMessageIds = {};

  // Keeps track of messages currently being processed for task extraction.
  final Set<String> _pendingTaskExtractionIds = {};

  // Username of the current user.
  String _myUsername = '';

  // Username of the other participant.
  String _otherUsername = '';

  // Future used to wait for the current user's username to load.
  Future<void>? _myUsernameFuture;

  // Future used to wait for the other user's username to load.
  Future<void>? _otherUsernameFuture;

  // Waits until both usernames have finished loading.
  Future<void> _ensureUsernamesLoaded() => Future.wait([
        if (_myUsernameFuture != null) _myUsernameFuture!,
        if (_otherUsernameFuture != null) _otherUsernameFuture!,
      ]);

  // Stores IDs of messages pinned in this chat.
  Set<String> _pinnedMessageIds = {};

  // Listens for changes to the pinned messages in Firestore.
  StreamSubscription<DocumentSnapshot>? _pinnedSub;

  // Stores the latest list of messages displayed in the chat.
  List<MessageModel> _latestMessages = [];

  // Creates the message stream once and reuses it during rebuilds.
  late final Stream<List<MessageModel>> _messagesStream =
      _chatService.loadHistory(widget.chatId);

  // Initializes the chat screen.
  @override
  void initState() {
    super.initState();

    // Listen for changes to the pinned messages in the chat document.
    _pinnedSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
      // Stop updating the state if the screen has already been removed.
      if (!mounted) return;

      // Get the latest chat document data.
      final data = snap.data();

      // Convert the stored pinned message list into a Set.
      final pinned =
          (data?['pinnedMessages'] as List?)?.cast<String>().toSet() ?? {};

      // Update the pinned messages displayed by the screen.
      setState(() => _pinnedMessageIds = pinned);
    });

    // Mark the chat as read when it is opened.
    _markChatRead();

    // Start loading the current user's username.
    _myUsernameFuture = _loadMyUsername();

    // Start loading the other participant's username.
    _otherUsernameFuture = _loadOtherUsername();
  }

  // Loads the current user's username from Firestore.
  Future<void> _loadMyUsername() async {
    try {
      // Retrieve the current user's profile.
      final user = await _authService.getUser(widget.userId);

      // Update the username when the user exists and the widget is active.
      if (mounted && user != null) {
        setState(() => _myUsername = user.username);
      }
    } catch (_) {
      // Username loading is non-critical.
    }
  }

  // Loads the other participant's username from Firestore.
  Future<void> _loadOtherUsername() async {
    // Get the other participant's user ID.
    final otherUserId = _otherUserId;

    // Stop if no other user ID can be found.
    if (otherUserId.isEmpty) return;

    try {
      // Retrieve the other user's profile.
      final user = await _authService.getUser(otherUserId);

      // Store the username when the user exists.
      if (mounted && user != null) {
        setState(() => _otherUsername = user.username);
      }
    } catch (_) {
      // Username loading is non-critical.
    }
  }

  // Determines the person who should receive the task.
  String _resolveReceiverName(MessageModel message) {
    // Check whether the current user sent the message.
    final iAmSender = message.senderId == widget.userId;

    if (iAmSender) {
      // If I sent it, the other participant is the receiver.
      return _otherUsername.isNotEmpty ? _otherUsername : _otherUserId;
    }

    // If I received it, I am the receiver.
    return _myUsername.isNotEmpty ? _myUsername : widget.userId;
  }

  // Marks the current chat as read.
  Future<void> _markChatRead() async {
    try {
      // Update the read status in Firestore.
      await _chatService.markAsRead(widget.chatId, widget.userId);
    } catch (_) {
      // Failure to mark as read does not stop the chat from working.
    }
  }

  // Displays the other participant's profile.
  void _showUserProfile() async {
    // Get the other participant's ID.
    final otherUserId = _otherUserId;

    // Stop if the ID is unavailable.
    if (otherUserId.isEmpty) return;

    // Display the profile as a bottom sheet.
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (ctx) => FutureBuilder<UserModel?>(
        // Load the other user's profile.
        future: _authService.getUser(otherUserId),

        // Build the profile based on the loading state.
        builder: (ctx, snapshot) {
          final scheme = Theme.of(ctx).colorScheme;

          // Display a loading indicator while retrieving the profile.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            );
          }

          // Get the retrieved user.
          final user = snapshot.data;

          // Display an error message if the profile could not be loaded.
          if (user == null) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Could not load this user\'s profile.',
                ),
              ),
            );
          }

          // Display the user's profile information.
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Small handle at the top of the bottom sheet.
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // User avatar.
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      user.username.isNotEmpty
                          ? user.username[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Username.
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Online/offline status.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 9,
                        color: user.isOnline ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        user.isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),

                  const Divider(height: 28),

                  // User email.
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.email_outlined,
                      color: scheme.primary,
                    ),
                    title: const Text('Email'),
                    subtitle: Text(
                      user.email.isNotEmpty ? user.email : '—',
                    ),
                  ),

                  // User ID and copy button.
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.badge_outlined,
                      color: scheme.primary,
                    ),
                    title: const Text('User ID'),
                    subtitle: Text(
                      user.userId,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy User ID',
                      onPressed: () {
                        // Copy the user ID to the clipboard.
                        Clipboard.setData(
                          ClipboardData(text: user.userId),
                        );

                        // Inform the user that the ID was copied.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'User ID copied to clipboard',
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Formats a UTC timestamp into a user-friendly local date/time.
  String _formatTimestamp(DateTime utcTime) {
    // Convert the timestamp to the device's local timezone.
    final local = utcTime.toLocal();

    // Get the current date.
    final now = DateTime.now();

    // Check whether the message was sent today.
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;

    // Convert the hour to 12-hour format.
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;

    // Add a leading zero to the minutes.
    final minute = local.minute.toString().padLeft(2, '0');

    // Determine AM or PM.
    final period = local.hour >= 12 ? 'PM' : 'AM';

    // Create the time string.
    final time = '$hour:$minute $period';

    // Show only the time for today's messages.
    if (isToday) return time;

    // Month names used for older messages.
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    // Show month, day, and time for older messages.
    return '${months[local.month - 1]} ${local.day}, $time';
  }

  // Displays available actions when a message is long-pressed.
  void _showMessageActions(MessageModel msg, bool isMe) {
    // Check whether the selected message is currently pinned.
    final isPinned = _pinnedMessageIds.contains(msg.messageId);

    // Display the action menu.
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pin or unpin the message.
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(
                isPinned ? 'Unpin message' : 'Pin message',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _togglePinMessage(
                  msg.messageId,
                  isPinned,
                );
              },
            ),

            // Only allow the sender to delete their message.
            if (isMe)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
                title: const Text(
                  'Delete message',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteMessage(msg.messageId);
                },
              ),

            // Close the action menu.
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  // Displays all currently pinned messages.
  void _showPinnedMessagesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (ctx) {
        // Filter the latest messages to only pinned messages.
        final pinned = _latestMessages
            .where(
              (m) => _pinnedMessageIds.contains(m.messageId),
            )
            .toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bottom sheet title.
                const Text(
                  'Pinned messages',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                // Display a message when there are no pinned messages.
                if (pinned.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No pinned messages.'),
                  ),

                // Display each pinned message.
                ...pinned.map(
                  (m) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.push_pin),
                    title: Text(
                      m.senderName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      m.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.push_pin_outlined,
                      ),
                      tooltip: 'Unpin',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _togglePinMessage(
                          m.messageId,
                          true,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Pins or unpins a message.
  Future<void> _togglePinMessage(
    String messageId,
    bool currentlyPinned,
  ) async {
    try {
      if (currentlyPinned) {
        // Remove the message from the pinned list.
        await _chatService.unpinMessage(
          widget.chatId,
          messageId,
        );
      } else {
        // Add the message to the pinned list.
        await _chatService.pinMessage(
          widget.chatId,
          messageId,
        );
      }
    } catch (e) {
      // Display an error if the operation fails.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update pin: $e'),
        ),
      );
    }
  }

  // Shows a confirmation dialog before deleting a message.
  Future<void> _confirmDeleteMessage(String messageId) async {
    // Ask the user to confirm the deletion.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This message will be deleted for everyone.',
        ),
        actions: [
          // Cancel deletion.
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),

          // Confirm deletion.
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    // Stop if the user did not confirm.
    if (confirmed != true) return;

    try {
      // Delete the message from Firestore.
      await _chatService.deleteMessage(
        widget.chatId,
        messageId,
      );

      // Remove the deleted message from the pinned set.
      _pinnedMessageIds.remove(messageId);
    } catch (e) {
      // Display an error when deletion fails.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete message: $e'),
        ),
      );
    }
  }

  // Sends a new message.
  Future<void> _sendMessage() async {
    // Get the message text and remove unnecessary spaces.
    final text = _controller.text.trim();

    // Do nothing when the input is empty.
    if (text.isEmpty) return;

    // Clear the input field after reading the text.
    _controller.clear();

    // Retrieve the sender's profile.
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();

    // Get the sender's username.
    final senderName = userDoc.data()?['username'] ?? 'Unknown';

    // Create a new message using plaintext content.
    final message = MessageModel(
      messageId: _uuid.v4(),
      senderId: widget.userId,
      senderName: senderName,
      content: text,
      timestamp: DateTime.now().toUtc(),
      isEncrypted: true,
    );

    // Mark the message as being scanned and processed.
    setState(() {
      _threatStatus[message.messageId] = 'scanning';
      _processedMessageIds.add(message.messageId);
    });

    // Track the pending threat scan.
    _pendingThreatScanIds.add(message.messageId);

    // Track the pending task extraction.
    _pendingTaskExtractionIds.add(message.messageId);

    // Send and encrypt the message through ChatService.
    await _chatService.sendMessage(
      widget.chatId,
      message,
    );

    // Run threat detection after the message is stored.
    _runThreatScan(
      message,
      isSender: true,
    );

    // Run AI task extraction on the message.
    _runTaskExtraction(message);

    // Scroll to the newest message after the frame is rendered.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Runs threat detection for a message.
  Future<void> _runThreatScan(
    MessageModel message, {
    bool isSender = false,
  }) async {
    // Mark this message as currently being scanned.
    _pendingThreatScanIds.add(message.messageId);

    // Scan the message using the threat detection service.
    final result = await _threatService.scanMessage(
      message,
      widget.userId,
      chatId: widget.chatId,
    );

    // Stop if the widget has been removed.
    if (!mounted) return;

    // Update the threat status displayed in the UI.
    setState(() {
      _threatStatus[message.messageId] = result.verdict;
    });

    // Show an alert when malicious content is detected.
    if (result.isThreat && result.verdict == 'malicious') {
      _showThreatAlert(
        result.threat!.threatType,
        result.threat!.severity,
        isSender: isSender,
      );
    }

    // Record that this user has completed the threat scan.
    unawaited(
      _chatService
          .markThreatRecorded(
            widget.chatId,
            message.messageId,
            widget.userId,
          )
          .catchError((_) {}),
    );
  }

  // Extracts tasks from a message using the task service and AI.
  Future<void> _runTaskExtraction(MessageModel message) async {
    // Mark the message as currently being processed.
    _pendingTaskExtractionIds.add(message.messageId);

    try {
      // Wait until both usernames are available.
      await _ensureUsernamesLoaded();

      // First check whether the extraction result is already cached.
      var tasks = await _taskService.getCachedExtraction(
        message.messageId,
        widget.chatId,
      );

      // If no cached result exists, perform a new AI extraction.
      if (tasks.isEmpty) {
        tasks = await _taskService.extractTasksOnly(
          message,
          chatId: widget.chatId,
          receiverUserId: widget.userId,
          receiverName: _resolveReceiverName(message),
        );
      }

      // Mark the message as having completed task extraction.
      try {
        await _chatService.markTasksExtracted(
          widget.chatId,
          message.messageId,
        );
      } catch (_) {
        // Continue even if the status update fails.
      }

      // Stop if the widget is no longer active or no tasks were found.
      if (!mounted || tasks.isEmpty) return;

      // Store the extracted tasks in the current screen state.
      setState(() {
        _extractedTasks[message.messageId] = tasks;
      });

      // Restore tasks that were previously added to the dashboard.
      _restoreSavedTaskState(
        tasks.map((t) => t.taskId).toList(),
      );
    } finally {
      // Remove the message from the pending extraction set.
      _pendingTaskExtractionIds.remove(message.messageId);
    }
  }

  // Reloads previously extracted tasks without unnecessarily repeating AI
  // extraction when possible.
  Future<void> _reloadPendingTasksForMessage(
    MessageModel msg,
  ) async {
    // Mark the message as being processed.
    _pendingTaskExtractionIds.add(msg.messageId);

    try {
      // Ensure usernames are available before resolving the receiver.
      await _ensureUsernamesLoaded();

      // Try to retrieve the previous extraction result.
      var tasks = await _taskService.getCachedExtraction(
        msg.messageId,
        widget.chatId,
      );

      // Perform extraction if no cached result is available.
      if (tasks.isEmpty) {
        tasks = await _taskService.extractTasksOnly(
          msg,
          chatId: widget.chatId,
          receiverUserId: widget.userId,
          receiverName: _resolveReceiverName(msg),
        );
      }

      // Stop if there are no tasks or the screen is no longer active.
      if (!mounted || tasks.isEmpty) return;

      // Restore the extracted tasks into the UI.
      setState(() {
        _extractedTasks[msg.messageId] = tasks;
      });

      // Restore previously saved task states.
      _restoreSavedTaskState(
        tasks.map((t) => t.taskId).toList(),
      );
    } catch (_) {
      // Task restoration is non-critical.
    } finally {
      // Remove the message from the pending set.
      _pendingTaskExtractionIds.remove(msg.messageId);
    }
  }

  // Restores tasks that were already saved to the dashboard.
  Future<void> _restoreSavedTaskState(
    List<String> candidateTaskIds,
  ) async {
    // Nothing needs to be restored if there are no task IDs.
    if (candidateTaskIds.isEmpty) return;

    try {
      // Check which task IDs already exist for this user.
      final existing = await _taskService.taskIdsExist(
        candidateTaskIds,
        widget.userId,
      );

      // Stop if the screen is inactive or no saved tasks exist.
      if (!mounted || existing.isEmpty) return;

      // Mark the existing tasks as saved.
      setState(() {
        _savedTaskIds.addAll(existing);
      });
    } catch (_) {
      // Task state restoration is non-critical.
    }
  }

  // Saves a confirmed task to the user's task dashboard.
  Future<void> _saveTask(TaskModel task) async {
    // Save the task using the current user's ID and username.
    await _taskService.saveTask(
      task,
      widget.userId,
      assignedToUsername: _myUsername,
    );

    // Stop if the screen has been removed.
    if (!mounted) return;

    // Mark the task as saved in the current screen.
    setState(() {
      _savedTaskIds.add(task.taskId);
    });
  }

  // Skips a suggested task.
  Future<void> _dismissTask(
    String messageId,
    TaskModel task,
  ) async {
    try {
      // Store the skipped task decision.
      await _chatService.skipTask(
        widget.chatId,
        messageId,
        task.taskId,
        widget.userId,
      );
    } catch (e) {
      // Show an error if the skip operation fails.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not skip task: $e'),
        ),
      );

      return;
    }

    // Stop if the widget is no longer active.
    if (!mounted) return;

    // Remove the skipped task from the current UI.
    setState(() {
      _extractedTasks[messageId]?.remove(task);
    });
  }

  // Displays an alert when malicious content is detected.
  void _showThreatAlert(
    String threatType,
    dynamic severity, {
    bool isSender = false,
  }) {
    // Convert the severity value into uppercase text.
    final severityLabel = severity.name.toUpperCase();

    // Describe whether the message was outgoing or incoming.
    final who = isSender ? 'outgoing message' : 'incoming message';

    // Display the warning dialog.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.red,
          size: 40,
        ),

        // Dialog title.
        title: const Text(
          '⚠️ Malicious Message Detected',
          textAlign: TextAlign.center,
        ),

        // Dialog content.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Your $who was flagged as $threatType '
              '(severity: $severityLabel).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Do not click any links or provide personal information.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),

        // Close button.
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }

  // Releases controllers and subscriptions when the screen is removed.
  @override
  void dispose() {
    // Stop listening for pinned-message updates.
    _pinnedSub?.cancel();

    // Dispose the text input controller.
    _controller.dispose();

    // Dispose the scroll controller.
    _scrollController.dispose();

    super.dispose();
  }

  // Builds the chat screen UI.
  @override
  Widget build(BuildContext context) {
    // Get the application's current color scheme.
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Top navigation bar.
      appBar: AppBar(
        // Tapping the title opens the other user's profile.
        title: InkWell(
          onTap: _showUserProfile,
          child: Row(
            children: [
              // User avatar.
              CircleAvatar(
                radius: 15,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  (widget.chatTitle?.isNotEmpty ?? false)
                      ? widget.chatTitle![0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // Display chat title and profile hint.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Chat username.
                    Text(
                      widget.chatTitle != null
                          ? '@${widget.chatTitle}'
                          : 'Chat',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Profile hint.
                    Text(
                      'Tap to view profile',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Back button.
        leading: const BackButton(),

        // App bar actions.
        actions: [
          // Show pinned messages button when at least one message is pinned.
          if (_pinnedMessageIds.isNotEmpty)
            IconButton(
              tooltip: 'Pinned messages',
              icon: Badge(
                label: Text(
                  '${_pinnedMessageIds.length}',
                ),
                child: const Icon(
                  Icons.push_pin_outlined,
                ),
              ),
              onPressed: _showPinnedMessagesSheet,
            ),

          // Display the end-to-end encryption indicator.
          Tooltip(
            message: 'End-to-end encrypted',
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                Icons.lock,
                size: 18,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),

      // Main chat content.
      body: Column(
        children: [
          // Banner showing that messages use end-to-end encryption.
          Container(
            width: double.infinity,
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 12,
                  color: scheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Messages are end-to-end encrypted',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),

          // Message list area.
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              // Listen to the cached Firestore message stream.
              stream: _messagesStream,

              // Build the UI whenever the message stream changes.
              builder: (context, snapshot) {
                // Get the latest messages.
                final messages = snapshot.data ?? [];

                // Keep a local copy for the pinned-message sheet.
                _latestMessages = messages;

                // Incoming messages that need to be marked as read.
                final newIncoming = <MessageModel>[];

                // Messages that require threat detection.
                final needsThreatScan = <MessageModel>[];

                // Messages that have never been processed for task extraction.
                final needsTaskExtraction = <MessageModel>[];

                // Messages whose existing task results need to be reloaded.
                final needsPendingTaskReload = <MessageModel>[];

                // Process each message in the current snapshot.
                for (final msg in messages) {
                  // Check whether this message has already been processed.
                  if (!_processedMessageIds.contains(msg.messageId)) {
                    _processedMessageIds.add(msg.messageId);

                    // Record newly received messages.
                    if (msg.senderId != widget.userId) {
                      newIncoming.add(msg);
                    }
                  }

                  // Restore the stored threat verdict for display.
                  if (!_dismissedThreatIds.contains(msg.messageId) &&
                      msg.threatVerdict != 'unscanned' &&
                      !_threatStatus.containsKey(msg.messageId)) {
                    _threatStatus[msg.messageId] = msg.threatVerdict;
                  }

                  // Check whether this user still needs to scan the message.
                  if (!msg.hasThreatRecordedFor(widget.userId) &&
                      !_pendingThreatScanIds.contains(msg.messageId)) {
                    needsThreatScan.add(msg);
                  }

                  // Check whether task extraction is required.
                  if (!_pendingTaskExtractionIds.contains(msg.messageId) &&
                      !_extractedTasks.containsKey(msg.messageId)) {
                    if (!msg.tasksExtracted) {
                      // Perform the initial task extraction.
                      needsTaskExtraction.add(msg);
                    } else {
                      // Reload an existing extraction result.
                      needsPendingTaskReload.add(msg);
                    }
                  }
                }

                // Perform processing after the current build has completed.
                if (newIncoming.isNotEmpty ||
                    needsThreatScan.isNotEmpty ||
                    needsTaskExtraction.isNotEmpty ||
                    needsPendingTaskReload.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;

                    // Update threat scanning indicators.
                    setState(() {
                      for (final msg in needsThreatScan) {
                        _threatStatus[msg.messageId] = 'scanning';
                      }
                    });

                    // Mark incoming messages as read.
                    if (newIncoming.any(
                      (m) => m.senderId != widget.userId,
                    )) {
                      _markChatRead();
                    }

                    // Run threat detection for required messages.
                    for (final msg in needsThreatScan) {
                      _runThreatScan(
                        msg,
                        isSender: msg.senderId == widget.userId,
                      );
                    }

                    // Run task extraction for new messages.
                    for (final msg in needsTaskExtraction) {
                      _runTaskExtraction(msg);
                    }

                    // Reload existing task suggestions.
                    for (final msg in needsPendingTaskReload) {
                      _reloadPendingTasksForMessage(msg);
                    }
                  });
                }

                // Display all messages using a scrolling list.
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    // Get the current message.
                    final msg = messages[index];

                    // Determine whether the message belongs to the current user.
                    final isMe = msg.senderId == widget.userId;

                    // Get the threat verdict for the message.
                    final verdict = _threatStatus[msg.messageId];

                    // Get extracted tasks that have not been skipped by this user.
                    final tasks = (_extractedTasks[msg.messageId] ?? [])
                        .where(
                          (t) => !msg
                              .skippedTaskIdsFor(widget.userId)
                              .contains(t.taskId),
                        )
                        .toList();

                    // Check whether the message is pinned.
                    final isPinned = _pinnedMessageIds.contains(msg.messageId);

                    // Display the message, threat label, and task card.
                    return Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        // Message bubble with long-press actions.
                        GestureDetector(
                          onLongPress: () => _showMessageActions(msg, isMe),
                          child: _MessageBubble(
                            msg: msg,
                            isMe: isMe,
                            scheme: scheme,
                            isPinned: isPinned,
                            timestampLabel: _formatTimestamp(msg.timestamp),
                          ),
                        ),

                        // Display the threat status when available.
                        if (verdict != null)
                          _ThreatLabel(
                            verdict: verdict,
                            scheme: scheme,
                            onDismiss: verdict == 'suspicious' ||
                                    verdict == 'malicious'
                                ? () => setState(() {
                                      // Remove the warning from the UI.
                                      _threatStatus.remove(
                                        msg.messageId,
                                      );

                                      // Remember that the user dismissed it.
                                      _dismissedThreatIds.add(
                                        msg.messageId,
                                      );
                                    })
                                : null,
                          ),

                        // Display AI-extracted tasks when available.
                        if (tasks.isNotEmpty)
                          _TaskCard(
                            messageId: msg.messageId,
                            tasks: tasks,
                            savedTaskIds: _savedTaskIds,
                            scheme: scheme,
                            onSave: _saveTask,
                            onDismiss: (task) =>
                                _dismissTask(msg.messageId, task),
                            isMe: isMe,
                            senderName: msg.senderName,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Separator between messages and input area.
          const Divider(height: 1),

          // Message input area.
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Text field for entering messages.
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'Message (encrypted)...',
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        size: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),

                    // Send the message when the user presses Enter.
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),

                const SizedBox(width: 8),

                // Send button.
                FilledButton(
                  onPressed: _sendMessage,
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(14),
                  ),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Displays the threat detection status below a message.
class _ThreatLabel extends StatelessWidget {
  // Threat verdict to display.
  final String verdict;

  // Current application color scheme.
  final ColorScheme scheme;

  // Optional callback for dismissing the warning.
  final VoidCallback? onDismiss;

  const _ThreatLabel({
    required this.verdict,
    required this.scheme,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Display scanning status.
    if (verdict == 'scanning') {
      return Padding(
        padding: const EdgeInsets.only(
          bottom: 4,
          left: 8,
          right: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Loading indicator.
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: scheme.outline,
              ),
            ),
            const SizedBox(width: 4),

            // Scanning text.
            Text(
              'Scanning…',
              style: TextStyle(
                fontSize: 10,
                color: scheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    // Display safe status.
    if (verdict == 'safe') {
      return Padding(
        padding: const EdgeInsets.only(
          bottom: 4,
          left: 8,
          right: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 12,
              color: Colors.green,
            ),
            const SizedBox(width: 3),
            Text(
              'Message scanned — no threats detected',
              style: TextStyle(
                fontSize: 10,
                color: Colors.green[700],
              ),
            ),
          ],
        ),
      );
    }

    // Display suspicious content warning.
    if (verdict == 'suspicious') {
      return Padding(
        padding: const EdgeInsets.only(
          bottom: 4,
          left: 8,
          right: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber,
              size: 12,
              color: Colors.orange,
            ),
            const SizedBox(width: 3),
            const Text(
              'Suspicious content detected',
              style: TextStyle(
                fontSize: 10,
                color: Colors.orange,
              ),
            ),

            // Display a dismiss button when available.
            if (onDismiss != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.orange,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Display malicious content warning.
    if (verdict == 'malicious') {
      return Padding(
        padding: const EdgeInsets.only(
          bottom: 4,
          left: 8,
          right: 8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.dangerous,
              size: 12,
              color: Colors.red,
            ),
            const SizedBox(width: 3),
            const Text(
              'Phishing / malicious content detected',
              style: TextStyle(
                fontSize: 10,
                color: Colors.red,
              ),
            ),

            // Display a dismiss button when available.
            if (onDismiss != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onDismiss,
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.red,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Return an empty widget for unknown verdicts.
    return const SizedBox.shrink();
  }
}

// Displays AI-extracted tasks below a message.
class _TaskCard extends StatelessWidget {
  // ID of the message that produced the tasks.
  final String messageId;

  // List of extracted tasks.
  final List<TaskModel> tasks;

  // IDs of tasks already saved to the dashboard.
  final Set<String> savedTaskIds;

  // Application color scheme.
  final ColorScheme scheme;

  // Callback used to save a task.
  final Future<void> Function(TaskModel) onSave;

  // Callback used to skip a task.
  final void Function(TaskModel) onDismiss;

  // Indicates whether the current user sent the source message.
  final bool isMe;

  // Name of the person who sent the message.
  final String senderName;

  const _TaskCard({
    required this.messageId,
    required this.tasks,
    required this.savedTaskIds,
    required this.scheme,
    required this.onSave,
    required this.onDismiss,
    required this.isMe,
    required this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Space around the task card.
      margin: const EdgeInsets.only(
        bottom: 8,
        left: 8,
        right: 8,
      ),

      // Internal spacing.
      padding: const EdgeInsets.all(12),

      // Card appearance.
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.secondary.withValues(alpha: 0.3),
        ),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI task detection heading.
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 13,
                color: scheme.secondary,
              ),
              const SizedBox(width: 4),
              Text(
                'AI detected task(s) — add to your to-do list?',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Display every extracted task.
          ...tasks.map((task) {
            // Check whether this task has already been saved.
            final isSaved = savedTaskIds.contains(task.taskId);

            // Display confirmation when the task has already been saved.
            if (isSaved) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 15,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),

                    // Confirmation message.
                    Expanded(
                      child: Text(
                        'Added to task dashboard',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Display the task details and action buttons.
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  // Task information.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Task title.
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        // Task deadline.
                        if (task.deadline != null)
                          Text(
                            'Deadline: ${task.deadline!.toLocal().toString().split(' ')[0]}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),

                        // Show assignee when the current user is the sender.
                        if (isMe && task.assignedTo.isNotEmpty)
                          Text(
                            'Assignee: ${task.assignedTo}',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),

                        // Show the sender when the current user is the receiver.
                        if (!isMe && senderName.isNotEmpty)
                          Text(
                            'Assigned by: $senderName',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 6),

                  // Button for adding the task to the dashboard.
                  FilledButton.tonal(
                    onPressed: () => onSave(task),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Add to list',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),

                  const SizedBox(width: 4),

                  // Button for skipping the task.
                  OutlinedButton(
                    onPressed: () => onDismiss(task),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Skip',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// Displays an individual chat message.
class _MessageBubble extends StatelessWidget {
  // Message data.
  final MessageModel msg;

  // Indicates whether the message belongs to the current user.
  final bool isMe;

  // Application color scheme.
  final ColorScheme scheme;

  // Indicates whether the message is pinned.
  final bool isPinned;

  // Formatted timestamp displayed below the message.
  final String timestampLabel;

  const _MessageBubble({
    required this.msg,
    required this.isMe,
    required this.scheme,
    this.isPinned = false,
    this.timestampLabel = '',
  });

  @override
  Widget build(BuildContext context) {
    // Determine the message bubble color.
    Color bubbleColor;

    if (msg.isThreat) {
      // Use a red background for messages flagged as threats.
      bubbleColor = Colors.red[100]!;
    } else if (isMe) {
      // Use the primary application color for sent messages.
      bubbleColor = scheme.primary;
    } else {
      // Use a light grey background for received messages.
      bubbleColor = Colors.grey[200]!;
    }

    // Determine the color of timestamp and metadata.
    final metaColor = isMe && !msg.isThreat ? Colors.white70 : Colors.grey[600];

    return Align(
      // Align sent messages to the right and received messages to the left.
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,

      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Display a pinned indicator above pinned messages.
          if (isPinned)
            Padding(
              padding: const EdgeInsets.only(
                bottom: 2,
                left: 4,
                right: 4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.push_pin,
                    size: 11,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Pinned',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),

          // Main message bubble.
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),

            // Limit the width of the message bubble.
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),

            // Style the message bubble.
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(12),
            ),

            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Display the sender name for received messages.
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      msg.senderName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),

                // Display the message content.
                Text(
                  msg.content,
                  style: TextStyle(
                    color:
                        isMe && !msg.isThreat ? Colors.white : Colors.black87,
                  ),
                ),

                const SizedBox(height: 4),

                // Display timestamp, encryption, and threat information.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Message timestamp.
                    if (timestampLabel.isNotEmpty) ...[
                      Text(
                        timestampLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: metaColor,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],

                    // Encryption indicator.
                    if (msg.isEncrypted)
                      Icon(
                        Icons.lock,
                        size: 10,
                        color: isMe && !msg.isThreat
                            ? Colors.white70
                            : Colors.grey,
                      ),

                    // Threat indicator.
                    if (msg.isThreat) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.warning_amber,
                        size: 12,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 2),
                      const Text(
                        'Threat detected',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red,
                        ),
                      ),
                    ],
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
