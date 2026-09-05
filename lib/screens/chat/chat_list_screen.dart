import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import 'chat_screen.dart';

// Displays the list of conversations belonging to the current user.
class ChatListScreen extends StatefulWidget {
  // Firebase Authentication UID of the currently signed-in user.
  final String userId;

  const ChatListScreen({
    super.key,
    required this.userId,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  // Handles user authentication operations such as retrieving user data
  // and signing out.
  final _authService = AuthService();

  // Handles chat-related operations such as retrieving, creating,
  // pinning, and deleting conversations.
  final _chatService = ChatService();

  // Stores the current user's profile information.
  UserModel? _currentUser;

  // Controls the loading state displayed while signing out.
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();

    // Loads the current user's profile when the screen is initialized.
    _loadCurrentUser();
  }

  // Retrieves the current user's information from Firestore.
  Future<void> _loadCurrentUser() async {
    // Uses the supplied user ID when available.
    // FirebaseAuth provides a fallback ID if the supplied value is empty.
    final uid = widget.userId.isNotEmpty
        ? widget.userId
        : FirebaseAuth.instance.currentUser?.uid ?? '';

    // Stops the operation if no authenticated user is available.
    if (uid.isEmpty) return;

    // Retrieves the user's profile through AuthService.
    final user = await _authService.getUser(uid);

    // Updates the interface only if the screen is still active.
    if (mounted) {
      setState(() => _currentUser = user);
    }
  }

  // Displays a confirmation dialog and signs the current user out.
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          // Closes the dialog without signing out.
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),

          // Confirms the sign-out operation.
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    // Continues only when the user confirms the action.
    if (confirmed == true) {
      setState(() => _loggingOut = true);

      try {
        // Signs out the currently authenticated Firebase user.
        await _authService.logout();

        // AuthGate detects the authentication state change
        // and automatically displays the login screen.
      } catch (e) {
        // Displays an error message if sign-out fails.
        if (mounted) {
          setState(() => _loggingOut = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sign out failed: $e'),
            ),
          );
        }
      }
    }
  }

  // Converts a Firestore timestamp into a readable time or date.
  String _formatChatTime(Timestamp? ts) {
    // Returns an empty string when no timestamp is available.
    if (ts == null) return '';

    // Converts the Firestore timestamp to the device's local time.
    final local = ts.toDate().toLocal();

    final now = DateTime.now();

    // Checks whether the message was sent today.
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;

    // Converts the hour into 12-hour format.
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;

    // Ensures minutes always contain two digits.
    final minute = local.minute.toString().padLeft(2, '0');

    // Determines whether the time is AM or PM.
    final period = local.hour >= 12 ? 'PM' : 'AM';

    // Displays only the time for today's conversations.
    if (isToday) {
      return '$hour:$minute $period';
    }

    // Displays the date for older conversations.
    return '${local.month}/${local.day}/${local.year % 100}';
  }

  // Changes the pinned state of a conversation.
  Future<void> _togglePinChat(
    String chatId,
    bool currentlyPinned,
  ) async {
    try {
      // Updates the pinned state in the chat service.
      await _chatService.togglePinChat(
        chatId,
        widget.userId,
        !currentlyPinned,
      );
    } catch (e) {
      // Displays an error if the operation fails.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update pin: $e'),
        ),
      );
    }
  }

  // Displays a confirmation dialog before permanently deleting a chat.
  Future<void> _confirmDeleteChat(
    String chatId,
    String displayName,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text(
          'This deletes your conversation with @$displayName for both people, including all messages. This cannot be undone.',
        ),
        actions: [
          // Cancels the deletion.
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),

          // Confirms and performs the deletion.
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

    // Stops if the user did not confirm.
    if (confirmed != true) return;

    try {
      // Deletes the selected conversation using ChatService.
      await _chatService.deleteChat(chatId);
    } catch (e) {
      // Displays an error message when deletion fails.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete conversation: $e'),
        ),
      );
    }
  }

  // Displays available actions for a selected conversation.
  void _showChatActions(
    String chatId,
    String displayName,
    bool isPinned,
  ) {
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
            // Allows the user to pin or unpin the conversation.
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(
                isPinned ? 'Unpin chat' : 'Pin chat',
              ),
              onTap: () {
                Navigator.pop(ctx);

                _togglePinChat(
                  chatId,
                  isPinned,
                );
              },
            ),

            // Allows the user to delete the conversation.
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.red,
              ),
              title: const Text(
                'Delete chat',
                style: TextStyle(
                  color: Colors.red,
                ),
              ),
              onTap: () {
                Navigator.pop(ctx);

                _confirmDeleteChat(
                  chatId,
                  displayName,
                );
              },
            ),

            // Closes the action menu.
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

  // Opens the interface for starting a new conversation.
  void _openNewChatSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (_) => _NewChatSheet(
        currentUserId: widget.userId,
        authService: _authService,
        chatService: _chatService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Retrieves the application's current colour scheme.
    final scheme = Theme.of(context).colorScheme;

    // Displays the registered username in the application header.
    // A placeholder is shown while the profile is being loaded.
    final displayUsername = _currentUser?.username.isNotEmpty == true
        ? _currentUser!.username
        : '…';

    // Uses the first letter of the username as the profile avatar.
    final avatarLetter = (_currentUser?.username.isNotEmpty == true)
        ? _currentUser!.username[0].toUpperCase()
        : '?';

    return Stack(
      children: [
        Scaffold(
          // Application header containing the logo,
          // username, profile information and sign-out option.
          appBar: AppBar(
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset(
                'assets/logo.png',
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AutoSecureChat',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '@$displayUsername',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
            actions: [
              // Provides profile information and sign-out functionality.
              PopupMenuButton<String>(
                enabled: !_loggingOut,
                offset: const Offset(0, 52),
                onSelected: (v) {
                  if (v == 'logout') {
                    // Waits until the popup menu closes before opening
                    // the sign-out confirmation dialog.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _logout();
                      }
                    });
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                  ),
                  child: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    radius: 18,
                    child: Text(
                      avatarLetter,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                itemBuilder: (_) => [
                  // Displays the current user's profile information.
                  PopupMenuItem(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Displays the registered username.
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '@$displayUsername',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: scheme.onSurface,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Displays the Firebase Authentication UID.
                        // Tapping the UID copies it to the clipboard.
                        GestureDetector(
                          onTap: () {
                            final uid = _currentUser?.userId ?? widget.userId;

                            Clipboard.setData(
                              ClipboardData(text: uid),
                            );

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'User ID copied to clipboard',
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              Icon(
                                Icons.badge_outlined,
                                size: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _currentUser?.userId ?? widget.userId,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.copy,
                                size: 10,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 2),

                        // Displays the email address associated
                        // with the current Firebase account.
                        Row(
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                FirebaseAuth.instance.currentUser?.email ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const Divider(height: 16),
                      ],
                    ),
                  ),

                  // Sign-out menu option.
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout,
                          size: 18,
                        ),
                        SizedBox(width: 10),
                        Text('Sign out'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          // StreamBuilder continuously listens for changes to
          // the user's conversations in Firestore.
          body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _chatService.getUserChats(widget.userId),
            builder: (context, snapshot) {
              // Displays a loading indicator while chats are being retrieved.
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              // Uses an empty list when no chat data is available.
              final chats = snapshot.data ?? [];

              // Displays an empty-state interface when the user
              // has not started any conversations.
              if (chats.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: scheme.outlineVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No conversations yet',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _openNewChatSheet,
                        child: const Text(
                          'Start a conversation',
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Displays all conversations in a scrollable list.
              return ListView.separated(
                itemCount: chats.length,

                // Adds a divider between conversations.
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  indent: 72,
                ),

                itemBuilder: (context, i) {
                  // Retrieves information about the current conversation.
                  final chat = chats[i];

                  final chatId = chat['chatId'] as String? ?? '';

                  final lastMsg = chat['lastMessage'] as String? ?? '';

                  final displayName = chat['displayName'] as String? ?? chatId;

                  final isPinned = chat['isPinned'] as bool? ?? false;

                  final hasUnread = chat['hasUnread'] as bool? ?? false;

                  // Formats the last activity timestamp for display.
                  final timeLabel = _formatChatTime(
                    chat['lastTimestamp'] as Timestamp?,
                  );

                  return ListTile(
                    // Highlights pinned conversations.
                    tileColor: isPinned
                        ? scheme.primaryContainer.withValues(alpha: 0.18)
                        : null,

                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Displays the first letter of the
                        // other user's username.
                        CircleAvatar(
                          backgroundColor: scheme.secondaryContainer,
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),

                        // Displays an unread indicator
                        // when the conversation contains unread messages.
                        if (hasUnread)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.surface,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    // Displays the username and pinned indicator.
                    title: Row(
                      children: [
                        if (isPinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: 13,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            '@$displayName',
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.bold : FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    // Displays the latest message in the conversation.
                    subtitle: Text(
                      lastMsg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight:
                            hasUnread ? FontWeight.w600 : FontWeight.normal,
                        color: hasUnread
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),

                    // Displays the last activity time and
                    // conversation action menu.
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (timeLabel.isNotEmpty)
                          Text(
                            timeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: hasUnread
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: hasUnread
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),

                        const SizedBox(height: 4),

                        // Opens pin and delete actions.
                        GestureDetector(
                          onTap: () => _showChatActions(
                            chatId,
                            displayName,
                            isPinned,
                          ),
                          child: Icon(
                            Icons.more_vert,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),

                    // Long pressing a conversation also opens
                    // the conversation action menu.
                    onLongPress: () => _showChatActions(
                      chatId,
                      displayName,
                      isPinned,
                    ),

                    // Opens the selected conversation.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chatId,
                          userId: widget.userId,
                          chatTitle: displayName,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),

          // Floating button for creating a new conversation.
          floatingActionButton: FloatingActionButton.extended(
            icon: const Icon(
              Icons.person_add_outlined,
            ),
            label: const Text('New Chat'),
            onPressed: _openNewChatSheet,
          ),
        ),

        // Displays a full-screen loading overlay while
        // the sign-out operation is being processed.
        if (_loggingOut)
          Container(
            color: Colors.black.withValues(alpha: 0.35),
            child: const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 22,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Signing out…'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Provides the interface for searching for another user
// and starting a new conversation.
class _NewChatSheet extends StatefulWidget {
  // UID of the current user.
  final String currentUserId;

  // Service used to search for registered users.
  final AuthService authService;

  // Service used to create conversations.
  final ChatService chatService;

  const _NewChatSheet({
    required this.currentUserId,
    required this.authService,
    required this.chatService,
  });

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  // Controller for the user search field.
  final _searchCtrl = TextEditingController();

  // Stores users returned from the search operation.
  List<UserModel> _results = [];

  // Indicates whether a search request is in progress.
  bool _searching = false;

  // Stores an optional search error message.
  String? _error;

  // Stores the UID of the user whose chat is currently being created.
  String? _startingChatUserId;

  // Searches for users by username or Firebase UID.
  Future<void> _search(String query) async {
    // Clears the results when the search field is empty.
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });

    try {
      // Searches for users while excluding the current user.
      final users = await widget.authService.searchUsersFlexible(
        query,
        excludeUserId: widget.currentUserId,
      );

      if (mounted) {
        setState(() {
          _results = users;

          // Displays a message when no matching account exists.
          _error =
              users.isEmpty ? 'No user found with that username or ID.' : null;
        });
      }
    } catch (e) {
      // Displays an error when the search cannot be completed.
      if (mounted) {
        setState(
          () => _error = 'Search failed. Check your connection.',
        );
      }
    } finally {
      // Ends the search loading state.
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  // Creates a conversation with the selected user.
  Future<void> _startChat(UserModel other) async {
    // Prevents multiple chat creation requests at the same time.
    if (_startingChatUserId != null) return;

    setState(
      () => _startingChatUserId = other.userId,
    );

    try {
      // Creates or retrieves the conversation ID.
      final chatId = await widget.chatService.startChat(
        widget.currentUserId,
        other.userId,
        otherUsername: other.username,
      );

      if (!mounted) return;

      // Closes the search sheet.
      Navigator.pop(context);

      // Opens the newly created conversation.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            userId: widget.currentUserId,
            chatTitle: other.username,
          ),
        ),
      );
    } catch (e) {
      // Allows the user to retry if creating the chat fails.
      if (mounted) {
        setState(
          () => _startingChatUserId = null,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not start chat: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Releases the search field controller.
    _searchCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,

        // Moves the sheet above the keyboard when it appears.
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle for the bottom sheet.
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(
                bottom: 16,
              ),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text(
            'New Conversation',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 4),

          // Explains the supported search methods.
          Text(
            'Search by username or User ID',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 16),

          // User search field.
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'e.g. alice1  or paste a User ID',

              prefixIcon: const Icon(
                Icons.search,
              ),

              // Displays a progress indicator while searching.
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : null,

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),

            // Performs a search whenever the text changes.
            onChanged: _search,
          ),

          // Displays search errors or no-result messages.
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                color: scheme.error,
                fontSize: 13,
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Displays all matching users.
          ..._results.map(
            (user) => _UserResultCard(
              user: user,
              scheme: scheme,
              isStarting: _startingChatUserId == user.userId,
              onChat: () => _startChat(user),
            ),
          ),
        ],
      ),
    );
  }
}

// Displays one user returned from the new-chat search.
class _UserResultCard extends StatelessWidget {
  // User information displayed in the result card.
  final UserModel user;

  // Current application colour scheme.
  final ColorScheme scheme;

  // Callback executed when the user selects Chat.
  final VoidCallback onChat;

  // Indicates whether a conversation is currently being created.
  final bool isStarting;

  const _UserResultCard({
    required this.user,
    required this.scheme,
    required this.onChat,
    this.isStarting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        child: Row(
          children: [
            // Displays the first letter of the username.
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              radius: 24,
              child: Text(
                user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),

            const SizedBox(width: 14),

            // Displays the user's account information.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username.
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(height: 3),

                  // Firebase Authentication UID.
                  Row(
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        size: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          user.userId,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 2),

                  // Registered email address.
                  Row(
                    children: [
                      Icon(
                        Icons.email_outlined,
                        size: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Button for starting a conversation with the user.
            FilledButton.tonal(
              onPressed: isStarting ? null : onChat,

              // Shows a loading indicator while
              // the conversation is being created.
              child: isStarting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Chat'),
            ),
          ],
        ),
      ),
    );
  }
}
