import 'package:flutter/material.dart';
import '../../models/task_model.dart';
import '../../services/task_service.dart';
import '../../services/auth_service.dart';

// Displays the task dashboard for the current user.
class TaskScreen extends StatelessWidget {
  final String userId;

  const TaskScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    // Create services used to retrieve and manage tasks and user information.
    final taskService = TaskService();
    final authService = AuthService();

    // Get the current theme colour scheme.
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // App bar for the Task Dashboard screen.
      appBar: AppBar(
        title: const Text('Task Dashboard'),
        centerTitle: false,
      ),

      // Retrieve the current user's information.
      body: FutureBuilder(
        future: authService.getUser(userId),
        builder: (context, userSnapshot) {
          // Get the username of the current user.
          final myUsername = userSnapshot.data?.username ?? '';

          // Listen for tasks belonging to the current user.
          return StreamBuilder<List<TaskModel>>(
            stream: taskService.getUserTasks(userId),
            builder: (context, snapshot) {
              // Show a loading indicator while tasks are being retrieved.
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              // Get the list of tasks returned from Firestore.
              final allTasks = snapshot.data ?? [];

              // Get the current date for task status calculation.
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              // Update task status according to its deadline.
              List<TaskModel> recategorised = allTasks.map((t) {
                // Completed tasks keep their completed status.
                if (t.status == TaskStatus.done) return t;

                // Tasks without a deadline keep their current status.
                if (t.deadline == null) return t;

                // Compare the task deadline with today's date.
                final dl = DateTime(
                    t.deadline!.year, t.deadline!.month, t.deadline!.day);

                // Mark tasks based on whether their deadline has passed.
                if (dl.isBefore(today)) {
                  t.status = TaskStatus.overdue;
                } else if (dl.isAtSameMomentAs(today)) {
                  t.status = TaskStatus.today;
                } else {
                  t.status = TaskStatus.upcoming;
                }

                return t;
              }).toList();

              // Separate tasks into different status categories.
              final overdue = recategorised
                  .where((t) => t.status == TaskStatus.overdue)
                  .toList();

              final todayTasks = recategorised
                  .where((t) => t.status == TaskStatus.today)
                  .toList();

              final upcoming = recategorised
                  .where((t) => t.status == TaskStatus.upcoming)
                  .toList();

              final pending = recategorised
                  .where((t) => t.status == TaskStatus.pending)
                  .toList();

              final done = recategorised
                  .where((t) => t.status == TaskStatus.done)
                  .toList();

              // Display an empty state when there are no tasks.
              if (allTasks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.task_alt,
                          size: 64, color: scheme.outlineVariant),
                      const SizedBox(height: 16),
                      Text(
                        'No tasks yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tasks detected in chats will appear here.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Display the task dashboard and task categories.
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Display the task summary counters.
                  _SummaryRow(
                    total: allTasks.length,
                    overdue: overdue.length,
                    upcoming: upcoming.length + todayTasks.length,
                    completed: done.length,
                    scheme: scheme,
                  ),

                  const SizedBox(height: 16),

                  // Display overdue tasks.
                  if (overdue.isNotEmpty) ...[
                    _SectionHeader('Overdue', Colors.red, overdue.length),
                    ..._tiles(overdue, taskService, scheme, myUsername),
                  ],

                  // Display tasks due today.
                  if (todayTasks.isNotEmpty) ...[
                    _SectionHeader('Today', Colors.orange, todayTasks.length),
                    ..._tiles(todayTasks, taskService, scheme, myUsername),
                  ],

                  // Display upcoming tasks.
                  if (upcoming.isNotEmpty) ...[
                    _SectionHeader('Upcoming', Colors.blue, upcoming.length),
                    ..._tiles(upcoming, taskService, scheme, myUsername),
                  ],

                  // Display pending tasks.
                  if (pending.isNotEmpty) ...[
                    _SectionHeader('Pending', Colors.grey, pending.length),
                    ..._tiles(pending, taskService, scheme, myUsername),
                  ],

                  // Display completed tasks.
                  if (done.isNotEmpty) ...[
                    _SectionHeader('Done', Colors.green, done.length),
                    ..._tiles(done, taskService, scheme, myUsername),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  // Create the task tiles for a specific task category.
  List<Widget> _tiles(
    List<TaskModel> tasks,
    TaskService service,
    ColorScheme scheme,
    String myUsername,
  ) {
    return tasks
        .map(
          (task) => Dismissible(
            // Use the task ID as the unique key for each task.
            key: Key(task.taskId),

            // Allow the user to swipe from right to left to delete a task.
            direction: DismissDirection.endToStart,

            // Display the delete background when swiping.
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              color: Colors.red,
              child: const Icon(Icons.delete, color: Colors.white),
            ),

            // Delete the task when the swipe action is completed.
            onDismissed: (_) => service.deleteTask(task.taskId, userId),

            // Display the task inside a card.
            child: Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Builder(
                builder: (context) {
                  // Check whether the current user is the task assignee.
                  final iAmAssignee = myUsername.isNotEmpty &&
                      task.assignedTo.trim().toLowerCase() ==
                          myUsername.trim().toLowerCase();

                  // Show the person who assigned the task when applicable.
                  final showAssignedBy = iAmAssignee &&
                      task.assignedBy.isNotEmpty &&
                      task.assignedBy.trim().toLowerCase() !=
                          myUsername.trim().toLowerCase();

                  // Show the assignee when the current user is not the assignee.
                  final showAssignee =
                      !iAmAssignee && task.assignedTo.isNotEmpty;

                  return ListTile(
                    // Checkbox allows the user to mark a task as completed
                    // or return it to the pending state.
                    leading: Checkbox(
                      value: task.status == TaskStatus.done,
                      onChanged: (val) => service.updateStatus(
                        task.taskId,
                        val == true ? TaskStatus.done : TaskStatus.pending,
                        userId,
                      ),
                    ),

                    // Display the task title.
                    title: Text(
                      task.title,
                      style: TextStyle(
                        // Add a line through completed tasks.
                        decoration: task.status == TaskStatus.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),

                    // Display additional task information.
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Display the task deadline when available.
                        if (task.deadline != null)
                          Text(
                            'Due: ${task.deadline!.toLocal().toString().split(' ')[0]}',
                            style: TextStyle(
                              fontSize: 12,
                              color: task.status == TaskStatus.overdue
                                  ? Colors.red
                                  : scheme.onSurfaceVariant,
                            ),
                          ),

                        // Display who assigned the task.
                        if (showAssignedBy)
                          Text(
                            'Assigned by: ${task.assignedBy}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),

                        // Display the assigned user.
                        if (showAssignee)
                          Text(
                            'Assignee: ${task.assignedTo}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),

                    // Adjust the tile height when additional information
                    // such as the deadline or assignee is displayed.
                    isThreeLine: task.deadline != null &&
                        (showAssignedBy || showAssignee),
                  );
                },
              ),
            ),
          ),
        )
        .toList();
  }
}

// Displays the title and task count for each task section.
class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  final int count;

  const _SectionHeader(this.title, this.color, this.count);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Display the section name.
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),

          const SizedBox(width: 8),

          // Display the number of tasks in the section.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Displays a summary of the user's tasks.
class _SummaryRow extends StatelessWidget {
  final int total, overdue, upcoming, completed;
  final ColorScheme scheme;

  const _SummaryRow({
    required this.total,
    required this.overdue,
    required this.upcoming,
    required this.completed,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Display the total number of tasks.
        _Stat('Total', total, scheme.primary),

        // Display the number of overdue tasks.
        _Stat('Overdue', overdue, Colors.red),

        // Display the number of upcoming tasks.
        _Stat('Upcoming', upcoming, Colors.blue),

        // Display the number of completed tasks.
        _Stat('Done', completed, Colors.green),
      ],
    );
  }
}

// Displays an individual task statistic.
class _Stat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              // Display the statistic value.
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),

              // Display the statistic label.
              Text(
                label,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
