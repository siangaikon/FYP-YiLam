// Defines the possible statuses of a task based on its deadline
// and completion state.
enum TaskStatus { pending, today, upcoming, overdue, done }

// Represents a task extracted from a chat message.
// The model stores task details, deadline information, assignment details,
// and references to the original chat and message.
class TaskModel {
  // Unique identifier of the task.
  final String taskId;

  // Title or description of the task.
  String title;

  // Deadline of the task. This can be null if no deadline was specified.
  DateTime? deadline;

  // Current status of the task.
  TaskStatus status;

  // ID of the message from which the task was extracted.
  final String sourceMessageId;

  // ID of the chat where the task originated.
  // This is retained for reference and future use.
  final String sourceChatId;

  // UID of the user who owns the task.
  // This is used to associate the task with the correct user in Firestore.
  String userId;

  // Display name of the person the task is assigned to.
  String assignedTo;

  // Display name of the person who assigned the task.
  // This is displayed in the Task Dashboard.
  String assignedBy;

  // Constructor used to create a TaskModel object.
  TaskModel({
    required this.taskId,
    required this.title,
    this.deadline,
    this.status = TaskStatus.pending,
    required this.sourceMessageId,
    this.sourceChatId = '',
    required this.userId,
    this.assignedTo = '',
    this.assignedBy = '',
  });

  // Creates a TaskModel object from data retrieved from Firestore.
  // The stored map values are converted into the appropriate data types.
  factory TaskModel.fromMap(Map<String, dynamic> map) {
    return TaskModel(
      taskId: map['taskId'] ?? '',
      title: map['title'] ?? '',
      deadline:
          map['deadline'] != null ? DateTime.tryParse(map['deadline']) : null,

      // Converts the stored status string back into a TaskStatus value.
      // If the stored value does not match any status, pending is used.
      status: TaskStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => TaskStatus.pending,
      ),

      sourceMessageId: map['sourceMessageId'] ?? '',
      sourceChatId: map['sourceChatId'] ?? '',
      userId: map['userId'] ?? '',
      assignedTo: map['assignedTo'] ?? '',
      assignedBy: map['assignedBy'] ?? '',
    );
  }

  // Converts the TaskModel object into a map so that the task
  // information can be stored in Firestore.
  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'title': title,
      'deadline': deadline?.toIso8601String(),

      // Converts the TaskStatus enum into a string for Firestore storage.
      'status': status.name,

      'sourceMessageId': sourceMessageId,
      'sourceChatId': sourceChatId,
      'userId': userId,
      'assignedTo': assignedTo,
      'assignedBy': assignedBy,
    };
  }

  // Updates the current status of the task.
  void updateStatus(TaskStatus newStatus) => status = newStatus;

  // Sets or updates the deadline of the task.
  void setDeadline(DateTime date) => deadline = date;
}
