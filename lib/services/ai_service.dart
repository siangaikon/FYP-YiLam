import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_remote_config/firebase_remote_config.dart';
import '../models/task_model.dart';
import '../models/threat_model.dart';

// Stores the result of the threat detection process.
class ThreatAnalysisResult {
  // Indicates whether the message is considered a threat.
  final bool isThreat;

  // Threat classification: safe, suspicious, or malicious.
  final String verdict;

  // Contains threat details when a malicious threat is detected.
  final ThreatModel? threat;

  const ThreatAnalysisResult({
    required this.isThreat,
    required this.verdict,
    this.threat,
  });
}

// Handles AI-based threat detection and task extraction.
class AIService {
  // Stores the Gemini API key retrieved from Firebase Remote Config.
  static String? _cachedApiKey;

  // Gemini API endpoint used for AI analysis.
  static const String _apiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  // Generates a consistent task ID using the source message ID.
  String _stableTaskId(String sourceMessageId, int index) =>
      '${sourceMessageId}_t$index';

  // Keywords used to identify messages where the sender is responsible.
  static final RegExp _selfCommitmentHint = RegExp(
    r"\b(i\x27ll|i will|i\x27m going to|i am going to|i\x27m gonna|"
    r"i need to|i have to|i\x27ve got to|i got to|i plan to|let me|"
    r"my task|i shall)\b",
    caseSensitive: false,
  );

  // Checks whether the sender is committing to complete the task.
  bool _isSenderResponsible(String text) =>
      _selfCommitmentHint.hasMatch(text.toLowerCase());

  // Retrieves the Gemini API key from Firebase Remote Config.
  Future<String> _getApiKey() async {
    // Return the cached key when it is already available.
    if (_cachedApiKey != null && _cachedApiKey!.isNotEmpty) {
      return _cachedApiKey!;
    }

    try {
      // Access the Firebase Remote Config instance.
      final rc = FirebaseRemoteConfig.instance;

      // Configure Remote Config fetch settings.
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );

      // Fetch and activate the latest configuration.
      await rc.fetchAndActivate();

      // Retrieve the Gemini API key.
      _cachedApiKey = rc.getString('gemini_api_key');
    } catch (e) {
      // Log an error if the API key cannot be retrieved.
      debugPrint('[AIService] Remote Config fetch failed: $e');
      _cachedApiKey = '';
    }

    return _cachedApiKey!;
  }

  // List of keywords commonly associated with suspicious messages.
  static const List<String> _suspiciousKeywords = [
    'password',
    'click here',
    'verify your account',
    'urgent',
    'you have won',
    'free gift',
    'limited time offer',
    'act now',
    'wire transfer',
    'bank details',
    'social security',
    'confirm your identity',
    'update your information',
    'account suspended',
    'unusual activity',
    'http://',
    'bit.ly',
    'tinyurl',
  ];

  // Checks whether a message contains any suspicious keywords.
  bool _isSuspiciousByRules(String text) {
    final lower = text.toLowerCase();
    return _suspiciousKeywords.any((kw) => lower.contains(kw));
  }

  // Detects threats using a combination of rule-based scanning and Gemini.
  //
  // The process first checks for suspicious keywords.
  // Suspicious messages are then analysed by Gemini.
  // Malicious messages are converted into ThreatModel objects.
  //
  // A local fallback is used when Gemini is unavailable.
  static final RegExp _urlHint =
      RegExp(r'(https?://\S+)', caseSensitive: false);

  // Phrases that indicate a higher risk when combined with a URL.
  static const List<String> _highRiskPhrases = [
    'verify your account',
    'account suspended',
    'account has been locked',
    'unusual activity',
    'confirm your identity',
    'bank details',
    'wire transfer',
    'social security',
    'update your information',
  ];

  // Performs local threat detection when Gemini is unavailable.
  ThreatAnalysisResult _fallbackThreatCheck(
    String text,
    String messageId,
    String userId,
    String chatId,
    String senderUsername,
  ) {
    final lower = text.toLowerCase();

    // Find a URL in the message.
    final urlMatch = _urlHint.firstMatch(text);

    // Check whether the message contains a high-risk phrase.
    final hasHighRiskPhrase = _highRiskPhrases.any((p) => lower.contains(p));

    // A URL combined with a high-risk phrase is treated as malicious.
    if (urlMatch != null && hasHighRiskPhrase) {
      final threat = ThreatModel(
        // Create a unique threat ID for the message and user.
        threatId: '${messageId}_$userId',
        userId: userId,
        threatType: 'phishing',
        severity: ThreatLevel.high,
        detectedAt: DateTime.now(),

        // Store the detected URL.
        sourceUrl: urlMatch.group(0) ?? '',

        // Store the chat and sender information.
        sourceChatId: chatId,
        senderUsername: senderUsername,
      );

      return ThreatAnalysisResult(
        isThreat: true,
        verdict: 'malicious',
        threat: threat,
      );
    }

    // Return suspicious when a rule matches but the message is not
    // sufficiently severe to be classified as malicious.
    return const ThreatAnalysisResult(
      isThreat: false,
      verdict: 'suspicious',
    );
  }

  // Analyses a message using the threat detection pipeline.
  Future<ThreatAnalysisResult> analyseThreat(
    String messageContent,
    String messageId,
    String userId, {
    String chatId = '',
    String senderUsername = '',
  }) async {
    // First check the message using the local rule engine.
    if (!_isSuspiciousByRules(messageContent)) {
      return const ThreatAnalysisResult(
        isThreat: false,
        verdict: 'safe',
      );
    }

    // Send suspicious messages to Gemini for further analysis.
    final geminiResult = await _callGeminiThreat(
      messageContent,
      messageId,
      userId,
      chatId,
      senderUsername,
    );

    return geminiResult;
  }

  // Sends a suspicious message to Gemini for classification.
  Future<ThreatAnalysisResult> _callGeminiThreat(
    String messageContent,
    String messageId,
    String userId,
    String chatId,
    String senderUsername,
  ) async {
    // Prompt used to classify the message.
    final prompt = '''
Analyse this chat message for phishing, scam, spam, or malicious intent.

Respond ONLY with valid JSON (no markdown):
{
  "verdict": "safe" | "suspicious" | "malicious",
  "threatType": "phishing" | "spam" | "malware" | "scam" | "none",
  "severity": "low" | "medium" | "high",
  "sourceUrl": "<URL found in message, or empty string>"
}

Message:
$messageContent
''';

    // Send the prompt to the Gemini API.
    final response = await _callAPI(prompt);

    // Use the local fallback when Gemini is unavailable.
    if (response == null) {
      debugPrint(
        '[AIService] Gemini call failed/unavailable — using local fallback for "$messageContent"',
      );

      return _fallbackThreatCheck(
        messageContent,
        messageId,
        userId,
        chatId,
        senderUsername,
      );
    }

    try {
      // Convert the Gemini JSON response into a Dart map.
      final Map<String, dynamic> data = jsonDecode(response);

      // Retrieve the threat verdict.
      final verdict = data['verdict'] as String? ?? 'safe';

      debugPrint(
        '[AIService] Gemini returned verdict="$verdict" for "$messageContent"',
      );

      // Create a threat record when Gemini identifies malicious content.
      if (verdict == 'malicious') {
        final threat = ThreatModel(
          threatId: '${messageId}_$userId',
          userId: userId,

          // Store the detected threat type.
          threatType: data['threatType'] ?? 'unknown',

          // Convert the severity value into the ThreatLevel enum.
          severity: ThreatLevel.values.firstWhere(
            (e) => e.name == data['severity'],
            orElse: () => ThreatLevel.medium,
          ),

          detectedAt: DateTime.now(),

          // Store the detected source URL.
          sourceUrl: data['sourceUrl'] ?? '',

          // Store the source chat and sender information.
          sourceChatId: chatId,
          senderUsername: senderUsername,
        );

        return ThreatAnalysisResult(
          isThreat: true,
          verdict: 'malicious',
          threat: threat,
        );
      }

      // Return safe or suspicious when no malicious threat is found.
      return ThreatAnalysisResult(
        isThreat: false,
        verdict: verdict,
      );
    } catch (_) {
      // Return a safe result if the Gemini response cannot be processed.
      return const ThreatAnalysisResult(
        isThreat: false,
        verdict: 'safe',
      );
    }
  }

  // Provides compatibility for older code that expects a ThreatModel.
  Future<ThreatModel?> detectPhishing(
    String messageContent,
    String messageId,
    String userId,
  ) async {
    final result = await analyseThreat(messageContent, messageId, userId);

    return result.threat;
  }

  // List of words that may indicate a task or action item.
  static const List<String> _taskHints = [
    'deadline',
    'tomorrow',
    'yesterday',
    'tonight',
    'today',
    'by ',
    'due',
    'need to',
    'have to',
    'please',
    'remind',
    'reminder',
    'task',
    'todo',
    'to-do',
    'meeting',
    'schedule',
    'submit',
    'finish',
    'complete',
    'assign',
    'urgent',
    'asap',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  // Detects common date and time patterns in a message.
  static final RegExp _dateOrTimeHint = RegExp(
    r'(\d{1,2}[/-]\d{1,2})|(\d{1,2}(:\d{2})?\s?(am|pm))|next week',
    caseSensitive: false,
  );

  // Checks whether a message may contain an actionable task.
  bool _mightHaveTask(String text) {
    final lower = text.toLowerCase();

    // Check for task-related keywords.
    if (_taskHints.any((h) => lower.contains(h))) return true;

    // Check for date or time information.
    if (_dateOrTimeHint.hasMatch(lower)) return true;

    return false;
  }

  // Extracts tasks from a chat message using Gemini or a local fallback.
  Future<List<TaskModel>> extractTasks(
    String messageContent,
    String sourceMessageId, {
    required String senderName,
    required String receiverName,
    String userId = '',
  }) async {
    // Skip AI processing when the message does not appear to contain a task.
    if (!_mightHaveTask(messageContent)) return [];

    // Prompt used to extract task information from the message.
    final prompt = '''
Extract all tasks, action items, or to-dos from this message, and decide
who is responsible for completing each one.

Sender of this message: $senderName
Receiver of this message: $receiverName

Rules for deciding the assignee:
- If the sender is describing something THEY will do
  (e.g. "I'll send the report", "I need to finish X"), the assignee is the sender.
- If the sender is asking the receiver to do something
  (e.g. "can you send me X", "please finish Y", "finish X by Friday"),
  the assignee is the receiver.

Return ONLY valid JSON array (no markdown):
[
  {"title": "...", "deadline": "ISO8601 or null", "assignee": "sender" | "receiver"}
]

For "title": write a short, action-first task description (roughly 3-8
words). Strip greetings/names ("Hey John,"), filler phrasing ("could you
please", "remember to", "just wanted to say"), and sign-offs ("thanks",
"regards"). Do not include the deadline in the title — it's captured
separately in the "deadline" field.
Example: "Hey John, could you please remember to upload the final report
by Friday? Thanks!" → title: "Upload the final report"

Message:
$messageContent
''';

    // Send the task extraction prompt to Gemini.
    final response = await _callAPI(prompt);

    // Use the local extractor when Gemini is unavailable.
    if (response == null) {
      return _extractTasksFallback(
        messageContent,
        sourceMessageId,
        senderName,
        receiverName,
        userId: userId,
      );
    }

    try {
      // Convert the Gemini response into a list of task data.
      final List<dynamic> items = jsonDecode(response);

      // Convert each extracted item into a TaskModel.
      final parsed = items.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;

        // Determine whether the sender or receiver is responsible.
        final role = item['assignee'] == 'sender' ? senderName : receiverName;

        // Clean the task title before displaying it.
        var title = _cleanTitle(
          (item['title'] ?? '').toString(),
        );

        // Limit the task title length.
        if (title.length > 140) {
          title = '${title.substring(0, 140)}…';
        }

        return TaskModel(
          // Generate a consistent ID for the extracted task.
          taskId: _stableTaskId(sourceMessageId, i),

          title: title,

          // Convert the deadline string into a DateTime.
          deadline: item['deadline'] != null
              ? DateTime.tryParse(item['deadline'])
              : null,

          // Store the source message ID.
          sourceMessageId: sourceMessageId,

          // Store the assigned user and task creator.
          assignedTo: role,
          assignedBy: senderName,

          // Store the user associated with the task.
          userId: userId,
        );
      }).toList();

      // Use the local extractor if Gemini did not return usable tasks.
      if (parsed.isEmpty) {
        return _extractTasksFallback(
          messageContent,
          sourceMessageId,
          senderName,
          receiverName,
          userId: userId,
        );
      }

      return parsed;
    } catch (_) {
      // Use the local extractor when the Gemini response cannot be parsed.
      return _extractTasksFallback(
        messageContent,
        sourceMessageId,
        senderName,
        receiverName,
        userId: userId,
      );
    }
  }

  // List of month names used when extracting dates from messages.
  static const List<String> _months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december'
  ];

  // Matches long date formats such as "19 July 2026" or "July 19 2026".
  static final RegExp _longDate = RegExp(
    r'(\d{1,2})(st|nd|rd|th)?\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{4})'
    r'|'
    r'(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})(st|nd|rd|th)?,?\s+(\d{4})',
    caseSensitive: false,
  );

  // Matches numeric dates such as "12/25/2026" or "12-25".
  static final RegExp _numericDate =
      RegExp(r'(\d{1,2})[/-](\d{1,2})([/-](\d{2,4}))?');

  // List of weekdays used when detecting relative deadlines.
  static const List<String> _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday'
  ];

  // Extracts a deadline from common date expressions.
  DateTime? _parseDeadline(String text) {
    final lower = text.toLowerCase();
    final now = DateTime.now();

    // Handle today's date.
    if (lower.contains('today')) {
      return DateTime(now.year, now.month, now.day);
    }

    // Handle tomorrow's date.
    if (lower.contains('tomorrow')) {
      final d = now.add(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day);
    }

    // Handle yesterday's date.
    if (lower.contains('yesterday')) {
      final d = now.subtract(const Duration(days: 1));
      return DateTime(d.year, d.month, d.day);
    }

    // Try to find a long date format.
    final longMatch = _longDate.firstMatch(lower);

    if (longMatch != null) {
      String? dayStr, monthStr, yearStr;

      if (longMatch.group(1) != null) {
        // Format: "19 July 2026".
        dayStr = longMatch.group(1);
        monthStr = longMatch.group(3);
        yearStr = longMatch.group(4);
      } else {
        // Format: "July 19, 2026".
        monthStr = longMatch.group(5);
        dayStr = longMatch.group(6);
        yearStr = longMatch.group(8);
      }

      // Convert the month name into a month number.
      final month = _months.indexOf(monthStr!.toLowerCase()) + 1;

      final day = int.tryParse(dayStr ?? '');
      final year = int.tryParse(yearStr ?? '');

      if (month > 0 && day != null && year != null) {
        try {
          return DateTime(year, month, day);
        } catch (_) {}
      }
    }

    // Check whether the message contains a weekday.
    final weekdayIdx = _weekdays.indexWhere((w) => lower.contains(w));

    if (weekdayIdx != -1) {
      var d = now;

      // Find the next occurrence of the specified weekday.
      for (int i = 1; i <= 7; i++) {
        final candidate = now.add(Duration(days: i));

        if (candidate.weekday - 1 == weekdayIdx) {
          d = candidate;
          break;
        }
      }

      return DateTime(d.year, d.month, d.day);
    }

    // Try to find a numeric date.
    final numMatch = _numericDate.firstMatch(lower);

    if (numMatch != null) {
      final a = int.tryParse(numMatch.group(1) ?? '');
      final b = int.tryParse(numMatch.group(2) ?? '');
      final yStr = numMatch.group(4);

      if (a != null && b != null) {
        // Use the current year when no year is provided.
        final year = yStr != null
            ? (yStr.length == 2 ? 2000 + int.parse(yStr) : int.parse(yStr))
            : now.year;

        try {
          // Assume the date uses month/day ordering.
          return DateTime(year, a, b);
        } catch (_) {}
      }
    }

    // Return null when no deadline can be detected.
    return null;
  }

  // Removes common filler phrases from the beginning of a task message.
  static final RegExp _leadingFiller = RegExp(
    r'^(remember to|reminder to|reminder[:\-]?|don\x27t forget to|do not forget to|'
    r'please remember to|please don\x27t forget to|please|need to|needs to|'
    r'have to|has to|make sure to|make sure you|make sure|'
    r'could you please|could you|can you please|can you|'
    r'would you please|would you mind|would you|kindly|'
    r'to-?do[:\-]?|task[:\-]?|note[:\-]?)\s+',
    caseSensitive: false,
  );

  // Removes greetings and names from the beginning of a message.
  static final RegExp _leadingGreeting = RegExp(
    r'^(hi|hello|hey|dear)\b[\s,!:.\-]*([a-z]+[\s,!:.\-]+)?',
    caseSensitive: false,
  );

  // Removes common sign-offs from the end of a message.
  static final RegExp _trailingSignoff = RegExp(
    r'[\s,.\-!?]*(thanks( you)?( a lot| so much| very much)?|'
    r'thank you( so much| very much)?|cheers|regards|best regards|'
    r'many thanks)[.!\s]*$',
    caseSensitive: false,
  );

  // Removes the deadline phrase from the task title.
  static final RegExp _trailingDeadlinePhrase = RegExp(
    r'\s*[,;]?\s*(by|on|before|due|until)\s+(this\s+|next\s+|coming\s+)?'
    r'('
    r'(\d{1,2})(st|nd|rd|th)?\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{4})'
    r'|(january|february|march|april|may|june|july|august|september|october|november|december)\s+(\d{1,2})(st|nd|rd|th)?,?\s+(\d{4})'
    r'|(monday|tuesday|wednesday|thursday|friday|saturday|sunday)'
    r'|today|tomorrow|yesterday'
    r'|(\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?)'
    r')\s*$',
    caseSensitive: false,
  );

  // Cleans a message so that only the main task action is used as the title.
  String _cleanTitle(String text) {
    var title = text.trim();

    // Remove greetings and names.
    title = title.replaceFirst(_leadingGreeting, '').trim();

    // Remove sign-offs from the end of the message.
    var noSignoff = title.replaceFirst(_trailingSignoff, '').trim();

    while (noSignoff != title && noSignoff.isNotEmpty) {
      title = noSignoff;
      noSignoff = title.replaceFirst(_trailingSignoff, '').trim();
    }

    // Remove the deadline because it is stored separately.
    title = title.replaceFirst(_trailingDeadlinePhrase, '').trim();

    // Remove filler phrases from the beginning.
    var stripped = title.replaceFirst(_leadingFiller, '').trim();

    while (stripped != title && stripped.isNotEmpty) {
      title = stripped;
      stripped = title.replaceFirst(_leadingFiller, '').trim();
    }

    // Remove unnecessary punctuation from the end.
    title = title.replaceFirst(RegExp(r'[\s,;.:!?]+$'), '').trim();

    // Use the original message if cleaning removed everything.
    if (title.isEmpty) {
      title = text.trim();
    } else if (title.isNotEmpty) {
      // Capitalise the first letter of the title.
      title = title[0].toUpperCase() + title.substring(1);
    }

    return title;
  }

  // Extracts a task locally without using Gemini.
  List<TaskModel> _extractTasksFallback(
    String text,
    String sourceMessageId,
    String senderName,
    String receiverName, {
    String userId = '',
  }) {
    // Try to detect a deadline from the message.
    final deadline = _parseDeadline(text);

    // Clean the message and use it as the task title.
    var title = _cleanTitle(text);

    // Limit the title length.
    if (title.length > 140) {
      title = '${title.substring(0, 140)}…';
    }

    // Return no task if there is no usable title.
    if (title.isEmpty) return [];

    // Determine who is responsible for the task.
    final assignedTo = _isSenderResponsible(text) ? senderName : receiverName;

    return [
      TaskModel(
        // Generate a consistent task ID.
        taskId: _stableTaskId(sourceMessageId, 0),

        title: title,
        deadline: deadline,

        // Store the source message and assigned users.
        sourceMessageId: sourceMessageId,
        assignedTo: assignedTo,
        assignedBy: senderName,
        userId: userId,
      ),
    ];
  }

  // Sends a prompt to the Gemini API and returns the response text.
  Future<String?> _callAPI(String prompt) async {
    // Retrieve the Gemini API key.
    final apiKey = await _getApiKey();

    // Stop if no API key is configured.
    if (apiKey.isEmpty) {
      debugPrint(
        '[AIService] gemini_api_key not set in Remote Config.',
      );
      return null;
    }

    try {
      // Send the request to the Gemini API.
      final res = await http.post(
        Uri.parse('$_apiUrl?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt}
              ]
            }
          ]
        }),
      );

      // Process a successful API response.
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        // Extract the generated text from the response.
        final text =
            data["candidates"][0]["content"]["parts"][0]["text"] as String;

        // Remove markdown code block formatting from the response.
        return text.replaceAll("```json", "").replaceAll("```", "").trim();
      }
    } catch (_) {
      // Return null when the API request fails.
    }

    return null;
  }
}
