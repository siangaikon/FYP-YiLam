import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import 'ai_service.dart';
import '../models/message_model.dart';

class TaskService {
  // Firestore database instance.
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // AI service used to extract tasks from messages.
  final AIService _ai = AIService();

  // ── Task document ID ──────────────────────────────────────────────────────

  // Creates a unique Firestore document ID for a task and user.
  String _taskDocId(String taskId, String userId) => '${taskId}_$userId';

  // ── Calculate task status ─────────────────────────────────────────────────

  // Determines the task status based on its deadline.
  static TaskStatus computeStatus(DateTime? deadline) {
    // Tasks without a deadline remain pending.
    if (deadline == null) return TaskStatus.pending;

    final now = DateTime.now();

    // Get today's date without the time portion.
    final today = DateTime(now.year, now.month, now.day);

    // Get the deadline date without the time portion.
    final dl = DateTime(deadline.year, deadline.month, deadline.day);

    // Deadline has already passed.
    if (dl.isBefore(today)) return TaskStatus.overdue;

    // Deadline is today.
    if (dl.isAtSameMomentAs(today)) return TaskStatus.today;

    // Deadline is in the future.
    return TaskStatus.upcoming;
  }

  // ── Extract tasks from a message ──────────────────────────────────────────

  // Extracts tasks from a plaintext message without saving the tasks
  // to the user's task collection.
  Future<List<TaskModel>> extractTasksOnly(
    MessageModel message, {
    String chatId = '',
    required String receiverUserId,
    required String receiverName,
  }) async {
    // Send the message content to the AI service for task extraction.
    final raw = await _ai.extractTasks(
      message.content,
      message.messageId,
      senderName: message.senderName,
      receiverName: receiverName,
    );

    // Convert the extracted results into TaskModel objects.
    final tasks = raw
        .map((t) => TaskModel(
              taskId: t.taskId,
              title: t.title,
              deadline: t.deadline,
              status: computeStatus(t.deadline),
              sourceMessageId: t.sourceMessageId,
              sourceChatId: chatId,
              userId: '',
              assignedTo: t.assignedTo,
              assignedBy: t.assignedBy,
            ))
        .toList();

    // ── Store task extraction log ───────────────────────────────────────────

    // Saves the extracted tasks as an audit record.
    if (tasks.isNotEmpty) {
      try {
        await _db
            .collection('task_extraction_logs')
            .doc(message.messageId)
            .set({
          'messageId': message.messageId,
          'chatId': chatId,
          'senderId': message.senderId,
          'receiverUserId': receiverUserId,
          'extractedAt': DateTime.now().toIso8601String(),
          'taskCount': tasks.length,
          'tasks': tasks
              .map((t) => {
                    'taskId': t.taskId,
                    'title': t.title,
                    'deadline': t.deadline?.toIso8601String(),
                    'assignedTo': t.assignedTo,
                    'assignedBy': t.assignedBy,
                  })
              .toList(),
          'messageSummary': message.content.length > 120
              ? '${message.content.substring(0, 120)}…'
              : message.content,
        });
      } catch (_) {
        // Continue even if the audit log cannot be saved.
      }
    }

    // Return the extracted tasks.
    return tasks;
  }

  // ── Get cached task extraction ─────────────────────────────────────────────

  // Retrieves previously extracted tasks for a message.
  Future<List<TaskModel>> getCachedExtraction(
      String messageId, String chatId) async {
    DocumentSnapshot<Map<String, dynamic>> doc;

    try {
      // Retrieve the saved extraction record.
      doc = await _db.collection('task_extraction_logs').doc(messageId).get();
    } catch (_) {
      // Return an empty list if the record cannot be retrieved.
      return [];
    }

    // Return an empty list when no extraction record exists.
    if (!doc.exists) return [];

    final data = doc.data()!;

    // Get the list of previously extracted tasks.
    final rawTasks = (data['tasks'] as List?) ?? [];

    // Convert stored task data back into TaskModel objects.
    return rawTasks.map((t) {
      final map = t as Map<String, dynamic>;

      // Convert the stored deadline string back to DateTime.
      final deadline = map['deadline'] != null
          ? DateTime.tryParse(map['deadline'] as String)
          : null;

      return TaskModel(
        taskId: map['taskId'] ?? '',
        title: map['title'] ?? '',
        deadline: deadline,
        status: computeStatus(deadline),
        sourceMessageId: messageId,
        sourceChatId: chatId,
        userId: '',
        assignedTo: map['assignedTo'] ?? '',
        assignedBy: map['assignedBy'] ?? '',
      );
    }).toList();
  }

  // ── Save a confirmed task ─────────────────────────────────────────────────

  // Saves a confirmed task to the user's task dashboard.
  Future<void> saveTask(
    TaskModel task,
    String userId, {
    String assignedToUsername = '',
  }) async {
    // Create a task record with the current user's information.
    final t = TaskModel(
      taskId: task.taskId,
      title: task.title,
      deadline: task.deadline,
      status: computeStatus(task.deadline),
      sourceMessageId: task.sourceMessageId,
      sourceChatId: task.sourceChatId,
      userId: userId,
      assignedTo: task.assignedTo.isNotEmpty
          ? task.assignedTo
          : (assignedToUsername.isNotEmpty ? assignedToUsername : userId),
      assignedBy: task.assignedBy,
    );

    // Save the task using a user-specific document ID.
    await _db
        .collection('tasks')
        .doc(_taskDocId(t.taskId, userId))
        .set(t.toMap());
  }

  // ── Check existing tasks ──────────────────────────────────────────────────

  // Checks which task IDs have already been saved by the user.
  Future<Set<String>> taskIdsExist(
      List<String> candidateTaskIds, String userId) async {
    // Return an empty set when there are no task IDs to check.
    if (candidateTaskIds.isEmpty) return {};

    final found = <String>{};

    // Check each task document in Firestore.
    final futures = candidateTaskIds.map((id) async {
      final doc =
          await _db.collection('tasks').doc(_taskDocId(id, userId)).get();

      // Add the task ID when the task belongs to the current user.
      if (doc.exists && doc.data()?['userId'] == userId) {
        found.add(id);
      }
    });

    // Wait for all task checks to finish.
    await Future.wait(futures);

    return found;
  }

  // ── Update task status ────────────────────────────────────────────────────

  // Updates the status of a user's task.
  Future<void> updateStatus(
      String taskId, TaskStatus status, String userId) async {
    await _db
        .collection('tasks')
        .doc(_taskDocId(taskId, userId))
        .update({'status': status.name});
  }

  // ── Get all tasks for a user ───────────────────────────────────────────────

  // Provides a real-time stream of tasks belonging to the user.
  Stream<List<TaskModel>> getUserTasks(String userId) {
    return _db
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => TaskModel.fromMap(doc.data())).toList());
  }

  // ── Delete a task ──────────────────────────────────────────────────────────

  // Deletes a specific task belonging to the user.
  Future<void> deleteTask(String taskId, String userId) async {
    await _db.collection('tasks').doc(_taskDocId(taskId, userId)).delete();
  }
}
