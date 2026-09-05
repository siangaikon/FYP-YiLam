# AutoSecureChat

### AI-Powered Secure Messaging with Real-Time Threat Detection and Task Automation

AutoSecureChat is an Android-based Flutter application that combines **secure one-to-one messaging, AI-powered task extraction, real-time cybersecurity threat detection, security activity monitoring, and end-to-end message encryption**.

The system is designed primarily for students and lecturers who need to communicate securely while automatically identifying actionable tasks and potential cybersecurity threats within conversations.

---

# 1. System Requirements

## 1.1 Real-Time Threat Detection Module

### Objective

The system automatically analyzes every incoming and outgoing message for potential cybersecurity threats before presenting the message as normal content.

### Functional Requirements

The system shall:

* Automatically scan all incoming and outgoing messages in real time.
* Detect suspicious URLs, phishing patterns, malicious keywords, and other potentially unsafe content.
* Classify messages into:

  * **Safe**
  * **Suspicious**
  * **Malicious**
* Display threat warnings directly within the chat interface.
* Highlight suspicious or malicious messages using appropriate warning indicators.
* Display a confirmation indicator for messages classified as safe.
* Allow users to dismiss detected threat notifications.
* Record confirmed threats in the threat monitoring system.
* Continuously monitor new messages throughout an active conversation.

### Threat Detection Pipeline

```text
Message Sent / Received
        ↓
Rule-Based Keyword & Pattern Scan
        ↓
    ┌───────────────┐
    │ Suspicious?   │
    └───────┬───────┘
            │
       No   │   Yes
       ↓    │    ↓
     Safe   │  Gemini AI
            │    ↓
            │  Verdict
            │    ↓
       ┌────┴───────────────┐
       │                    │
     Safe             Suspicious / Malicious
       ↓                    ↓
 Green Indicator       Warning Indicator
                            ↓
                     Threat Record
```

The rule-based engine performs the initial scan without consuming AI API quota. Gemini analysis is performed only when suspicious patterns are detected.

---

# 2. AI Task Extraction Module

## Objective

The system identifies actionable tasks from chat messages and allows users to save them to the Task Dashboard after confirmation.

### Functional Requirements

The system shall:

* Automatically analyze chat messages for task-related content.
* Extract a **clean task title** rather than storing the entire original message.
* Identify the task deadline when one is present.
* Determine the correct task assignee based on the meaning of the message.
* Display a task suggestion card within the conversation.
* Provide an **"Add to list"** button for user confirmation.
* Save the task only after the user approves it.
* Change the suggestion card to **"✓ Added to task dashboard"** after successful saving.
* Keep the confirmation state visible after leaving and reopening the chat.
* Automatically update the Task Dashboard after a task is saved.
* Support the following task statuses:

  * Pending
  * Today
  * Upcoming
  * Overdue
  * Done
* Display the assignee using their **username**, never their Firestore User ID.

### Assignee Resolution

The system determines responsibility from the wording of the message.

For example:

```text
"I'll finish the report by Friday."
        ↓
Sender is responsible
```

```text
"Please finish the report by Friday."
        ↓
Receiver is responsible
```

Gemini returns the assignee as either:

```text
sender
```

or

```text
receiver
```

The application then resolves the responsible participant to their registered username.

### Offline / Fallback Extraction

If Gemini is unavailable, the system uses a local rule-based extractor that can:

* Detect common deadline expressions.
* Recognize first-person task commitments.
* Remove filler phrases such as:

  * "please"
  * "remember to"
  * "don't forget to"
  * "I need to"
* Remove deadline expressions from the task title.
* Generate a concise action-oriented title.

Example:

```text
Original message:
"Please remember to submit the computer security report by Friday."

Extracted task:
Title: Submit the computer security report
Deadline: Friday
Assignee: Receiver
```

---

# 3. Security Centre Module

## Objective

The Security Centre provides an audit trail of authentication and security-related activities performed within the application.

### Functional Requirements

The system shall:

* Record successful login events.
* Record logout events.
* Record registration events.
* Record failed login attempts.
* Store timestamps for security events.
* Record device and network information where available.
* Display security events chronologically.
* Categorize events according to their type.
* Display alerts when suspicious authentication activity is detected.
* Prevent normal users from modifying security log records.

### Security Event Types

| Event        | Description                           |
| ------------ | ------------------------------------- |
| Login        | Successful authentication             |
| Logout       | User logout                           |
| Register     | Successful account registration       |
| Failed Login | Unsuccessful authentication attempt   |
| Suspicious   | Security activity requiring attention |

---

# 4. Chat Module

## Objective

The Chat Module provides real-time, secure, one-to-one communication between registered users.

### Functional Requirements

The system shall:

* Support **one-to-one conversations only**.
* Allow users to start a conversation using:

  * User ID
  * Username
* Generate a deterministic Chat ID to prevent duplicate conversations.
* Display the other participant's username in the chat list.
* Display the other participant's username in the chat header.
* Display unread message counts.
* Display the latest message preview.
* Display message timestamps.
* Receive and display messages in real time.
* Integrate threat detection into conversations.
* Integrate AI task extraction into conversations.
* Encrypt messages before storing them in Firebase.

### User Identification

Users can find their User ID from their profile.

```text
Open App
   ↓
Tap Profile Avatar
   ↓
View Username and User ID
   ↓
Share User ID with another registered user
   ↓
Other User enters ID in "New Chat"
```

User identities shown throughout the application use **usernames rather than raw Firebase User IDs**.

---

# 5. Task Dashboard Module

## Objective

The Task Dashboard provides a centralized view of tasks extracted from conversations.

### Functional Requirements

The system shall:

* Display the total number of tasks.
* Display overdue tasks.
* Display upcoming tasks.
* Display completed tasks.
* Organize tasks according to their status.
* Display:

  * Task title
  * Deadline
  * Assignee username
  * Task status
* Allow users to mark tasks as completed.
* Allow users to delete tasks using swipe-to-delete.
* Automatically refresh when a task is saved from a conversation.

### Task Categories

```text
Overdue
Today
Upcoming
Pending
Done
```

---

# 6. Non-Functional Requirements

## 6.1 Performance

The system should:

* Detect threats within a few seconds.
* Perform task extraction in near real time.
* Maintain responsive chat interaction.
* Display Firestore messages with minimal delay.

Target performance:

| Operation              |       Target |
| ---------------------- | -----------: |
| Login                  |  < 2 seconds |
| Registration + OTP     | < 60 seconds |
| Message delivery       |   < 1 second |
| Gemini task extraction |  < 3 seconds |
| Gemini threat analysis |  < 3 seconds |

---

## 6.2 Security

The system shall:

* Encrypt messages before storing them in Firebase.
* Use AES-256-CBC for message encryption.
* Derive encryption keys using SHA-256.
* Use a unique random IV for each encrypted message.
* Protect authentication information.
* Restrict security log modification.
* Prevent unauthorized access to user data.
* Store only necessary task and security information.

> **Implementation note:** Firebase Remote Config is used to provide runtime configuration values. API keys placed in a client application should still be treated as client-side credentials rather than true secrets; production deployments should additionally enforce appropriate API restrictions and server-side controls where required.

---

## 6.3 Usability

The system should:

* Provide clear warning messages.
* Use understandable threat classifications.
* Provide simple task confirmation controls.
* Keep the interface responsive.
* Avoid displaying technical Firebase User IDs to normal users.
* Display usernames consistently across:

  * Chat lists
  * Chat headers
  * Task assignees
  * User-facing interfaces

---

# 7. Overall System Workflow

## 7.1 Message Workflow

```text
User Sends / Receives Message
              ↓
       Message is Stored
              ↓
       Threat Detection
              ↓
       AI Task Extraction
              ↓
    ┌─────────┴─────────┐
    ↓                   ↓
Threat Detected?     Task Detected?
    ↓                   ↓
Show Warning        Show Task Card
    ↓                   ↓
Record Threat       User Reviews
                        ↓
                  "Add to list"
                        ↓
                  Save to Firestore
                        ↓
             "✓ Added to task dashboard"
                        ↓
                Update Dashboard
```

## 7.2 Security Workflow

```text
Login / Register / Logout / Failed Login
                  ↓
          Security Event Created
                  ↓
          Event Stored in Firestore
                  ↓
          Security Centre
                  ↓
        Chronological Activity Timeline
```

---

# 8. Project Structure

```text
lib/
│
├── main.dart
│   └── Application entry point, authentication routing,
│       and bottom navigation shell
│
├── firebase_options.dart
│   └── Firebase configuration generated by FlutterFire
│
├── models/
│   ├── user_model.dart
│   ├── message_model.dart
│   ├── task_model.dart
│   ├── threat_model.dart
│   └── security_log_model.dart
│
├── screens/
│   ├── auth/
│   │   └── auth_screen.dart
│   │       └── Login, registration and OTP verification
│   │
│   ├── chat/
│   │   ├── chat_list_screen.dart
│   │   │   └── Conversation list, profile, logout
│   │   │       and new-chat search
│   │   │
│   │   └── chat_screen.dart
│   │       └── Real-time encrypted messaging,
│   │           threat detection and task confirmation
│   │
│   ├── tasks/
│   │   └── task_screen.dart
│   │       └── Task Dashboard
│   │
│   ├── threats/
│   │   └── threat_screen.dart
│   │       └── Threat monitoring and threat history
│   │
│   └── security/
│       └── security_screen.dart
│           └── Security activity timeline
│
└── services/
    ├── auth_service.dart
    │   └── Authentication, OTP and user search
    │
    ├── chat_service.dart
    │   └── Firestore messaging and username resolution
    │
    ├── encryption_service.dart
    │   └── AES-256-CBC encryption and decryption
    │
    ├── task_service.dart
    │   └── Task storage and task retrieval
    │
    ├── threat_service.dart
    │   └── Rule-based and AI threat detection
    │
    ├── security_service.dart
    │   └── Security event logging and IP detection
    │
    └── ai_service.dart
        └── Gemini task extraction, threat analysis,
            fallback extraction and assignee resolution
```

---

# 9. Technology Stack

| Technology              | Purpose                                |
| ----------------------- | -------------------------------------- |
| Flutter                 | Mobile application framework           |
| Dart                    | Application programming language       |
| Firebase Authentication | User authentication                    |
| Cloud Firestore         | Real-time database                     |
| Firebase Remote Config  | Runtime configuration                  |
| EmailJS                 | OTP email delivery                     |
| Google Gemini API       | AI task extraction and threat analysis |
| AES-256-CBC             | Message encryption                     |
| SHA-256                 | Encryption key derivation              |
| UUID                    | Supporting unique identifiers          |
| VS Code                 | Development environment                |
| Android Studio          | Android development and testing        |

---

# 10. Firebase Firestore Structure

| Collection / Path         | Purpose                                    |
| ------------------------- | ------------------------------------------ |
| `users`                   | Stores user profiles and usernames         |
| `pending_verifications`   | Temporarily stores OTP verification data   |
| `chats`                   | Stores one-to-one conversation information |
| `chats/{chatId}/messages` | Stores encrypted chat messages             |
| `tasks`                   | Stores approved extracted tasks            |
| `task_extraction_logs`    | Records AI task extraction activities      |
| `threats`                 | Stores detected security threats           |
| `security_logs`           | Stores authentication and security events  |
| `failed_login_attempts`   | Stores failed authentication attempts      |

### Important Task Fields

```text
taskId
title
deadline
status
sourceMessageId
sourceChatId
userId
assignedTo
```

The `assignedTo` field stores the **username of the responsible participant**, rather than the raw Firebase User ID.

---

# 11. OTP Registration Workflow

```text
User enters:
Username + Email + Password
              ↓
       AuthService.register()
              ↓
Validate username
              ↓
Check username uniqueness
              ↓
Create Firebase Auth account
              ↓
Generate 6-digit OTP
              ↓
Store OTP temporarily
              ↓
Sign user out
              ↓
Retrieve EmailJS configuration
              ↓
Send OTP email
              ↓
Display OTP verification screen
              ↓
User enters OTP
              ↓
verifyOtpAndActivate()
              ↓
Check OTP and expiration
              ↓
Create users/{uid}
              ↓
Create registration security log
              ↓
Delete pending verification
              ↓
Return to Sign In
```

### OTP Rules

* OTP contains six digits.
* OTP expires after 10 minutes.
* Users can request a new OTP.
* Resending an OTP updates the OTP and expiration time.
* Users cannot log in until verification is completed.
* OTP verification creates the user's Firestore profile.

---

# 12. EmailJS Configuration

EmailJS is used to send OTP verification emails.

Required configuration values:

```text
emailjs_service_id
emailjs_template_id
emailjs_public_key
emailjs_private_key
gemini_api_key
```

The application retrieves these values through Firebase Remote Config at runtime.

### Email Template

```text
Subject: OTP for your AutoSecureChat authentication

Hi {{username}}, your verification code is: {{otp}}

This OTP will be valid for 15 minutes till {{time}}.

Do not share this OTP with anyone. If you didn't make this request,
you can safely ignore this email.

Thanks for visiting AutoSecureChat!
```

Required variables:

| Variable   | Description               |
| ---------- | ------------------------- |
| `to_email` | Recipient email           |
| `username` | Registered username       |
| `otp`      | Six-digit OTP             |
| `passcode` | Alternative OTP parameter |
| `time`     | OTP expiration time       |

---

# 13. Gemini AI Configuration

The Gemini API is used for:

1. AI task extraction
2. Threat classification

The API key is loaded from Firebase Remote Config rather than being hardcoded in the application source.

### Task Extraction

Gemini receives:

* Message content
* Sender username
* Receiver username

It returns structured task information:

```json
[
  {
    "title": "Submit computer security report",
    "deadline": "2026-07-19",
    "assignee": "sender"
  }
]
```

The application resolves `"sender"` or `"receiver"` to the corresponding username.

### Threat Analysis

Gemini returns:

```text
verdict
threatType
severity
sourceUrl
```

Possible verdicts:

```text
safe
suspicious
malicious
```

---

# 14. Sprint Deliverables

## Sprint 1 — User Authentication ✅

Implemented:

* Firebase email/password authentication
* Unique username registration
* Username validation
* Username uniqueness checking
* Six-digit OTP verification
* OTP resend functionality
* OTP expiration
* EmailJS integration
* Firebase Remote Config configuration
* Password visibility controls
* Login/logout
* Failed login logging
* Online/offline status
* Friendly authentication error messages

**Files:**

```text
auth_screen.dart
auth_service.dart
```

---

## Sprint 2 — One-to-One Chat Messaging ✅

Implemented:

* Real-time Firestore messaging
* One-to-one conversations
* User ID and username search
* Deterministic Chat IDs
* Username resolution
* Unread message counts
* Latest message previews
* Message timestamps
* Automatic scrolling
* Threat integration

**Files:**

```text
chat_list_screen.dart
chat_screen.dart
chat_service.dart
message_model.dart
```

---

## Sprint 3 — AI Task Extraction ✅

Implemented:

* Automatic task detection
* Gemini-powered extraction
* Local fallback extraction
* Clean task title generation
* Deadline extraction
* Sender/receiver assignee resolution
* Username-based assignees
* Task suggestion cards
* User confirmation
* Skip functionality
* Deterministic task IDs
* Persistent saved state
* Task extraction audit logs
* Task Dashboard integration

**Files:**

```text
task_screen.dart
task_service.dart
ai_service.dart
task_model.dart
```

---

## Sprint 4 — Real-Time Threat Detection ✅

Implemented:

* Rule-based threat scanning
* 18 suspicious keywords/patterns
* Gemini threat analysis
* Safe classification
* Suspicious classification
* Malicious classification
* Threat warning indicators
* Threat alert dialogs
* Threat persistence
* Severity classification
* Source URL display
* Threat dismissal
* Active/resolved threat filtering

**Files:**

```text
threat_screen.dart
threat_service.dart
ai_service.dart
threat_model.dart
```

---

## Sprint 5 — Security Logging & Monitoring ✅

Implemented:

* Login logging
* Registration logging
* Logout logging
* Failed login logging
* Public IP detection
* Multiple IP detection fallbacks
* Chronological security timeline
* Event-specific icons
* Suspicious activity banner
* Log clearing confirmation
* Security log access control

**Files:**

```text
security_screen.dart
security_service.dart
chat_list_screen.dart
main.dart
```

---

## Sprint 6 — End-to-End Encryption ✅

Implemented:

* AES-256-CBC encryption
* SHA-256 key derivation
* Random IV per message
* Base64 encrypted message format
* Encrypted message previews
* E2EE status indicator

### Encryption Process

```text
Sender UID + Receiver UID
          ↓
Sort User IDs
          ↓
Join with "_"
          ↓
SHA-256
          ↓
AES-256 Key
          ↓
Random IV
          ↓
AES-256-CBC Encryption
          ↓
Base64(IV):Base64(Ciphertext)
          ↓
Firestore
```

Stored message format:

```text
base64(iv):base64(ciphertext)
```

---

# 15. Sprint Summary

| Sprint | Module                        | Status      |
| ------ | ----------------------------- | ----------- |
| 1      | User Authentication           | ✅ Completed |
| 2      | One-to-One Chat Messaging     | ✅ Completed |
| 3      | AI Task Extraction            | ✅ Completed |
| 4      | Real-Time Threat Detection    | ✅ Completed |
| 5      | Security Logging & Monitoring | ✅ Completed |
| 6      | End-to-End Encryption         | ✅ Completed |

---

# 16. Fallback and Offline Behaviour

AutoSecureChat includes local fallback mechanisms to maintain core AI-related functionality when Gemini is unavailable.

## Task Extraction Fallback

When Gemini cannot be reached:

```text
Gemini unavailable
       ↓
Local Rule-Based Extractor
       ↓
Detect Task
       ↓
Extract Deadline
       ↓
Clean Task Title
       ↓
Resolve Assignee
       ↓
Display Suggestion Card
```

Example:

```text
"Remember to submit the report by 19 July 2026."

↓
Title: Submit the report
Deadline: 19 July 2026
```

## Threat Detection Fallback

When Gemini is unavailable:

```text
Suspicious Rule Detected
          ↓
Gemini unavailable
          ↓
Classify as Suspicious
```

The fallback does **not** automatically classify a message as malicious.

This prevents the system from making an overly severe threat classification without AI confirmation.

---

# 17. Task Persistence Mechanism

Task suggestion state is persistent across chat sessions.

When a task is extracted:

```text
Message
  ↓
Deterministic Task ID
  ↓
Check Firestore
  ↓
Already Saved?
  ├── Yes → Show "✓ Added to task dashboard"
  │
  └── No  → Show "Add to list"
```

Deterministic task IDs prevent duplicate tasks when extraction runs again after reopening a conversation.

The task suggestion therefore remains consistent across:

* Chat reopening
* Screen recreation
* Re-extraction
* Application navigation

---

# 18. Username Resolution

AutoSecureChat does not expose raw Firebase User IDs as user-facing identities.

### Chat List

```text
Chat ID
   ↓
Find other participant UID
   ↓
Query users collection
   ↓
Retrieve username
   ↓
Display @username
```

### Task Assignee

```text
AI determines:
sender / receiver
       ↓
Resolve participant UID
       ↓
Retrieve username
       ↓
Save username to assignedTo
```

This ensures usernames are displayed consistently throughout the application.

---

# 19. Firestore Security Requirements

The Firestore security rules should enforce the following principles:

| Collection              | Requirement                                             |
| ----------------------- | ------------------------------------------------------- |
| `users`                 | Signed-in users can access required profile information |
| `pending_verifications` | OTP and expiry can be updated during resend             |
| `chats`                 | Access limited to chat participants                     |
| `messages`              | Access limited to chat participants                     |
| `tasks`                 | Users can only access their own tasks                   |
| `task_extraction_logs`  | Authenticated extraction logging allowed                |
| `threats`               | Users can access relevant threat records                |
| `security_logs`         | Users can access their own security activity            |
| `failed_login_attempts` | Access restricted appropriately                         |

For tasks, the security rule should ensure that the stored `userId` belongs to the authenticated user.

---

# 20. Required Firestore Index

Username search requires:

```text
Collection: users
Field: usernameLower
Order: Ascending
```

The chat list username lookup uses Firestore document-ID queries and does not require an additional composite index.

---

# 21. Setup Guide

## Step 1 — Install Development Tools

Install:

* Flutter SDK
* Android Studio
* Visual Studio Code

Install the following VS Code extensions:

* Flutter
* Dart

---

## Step 2 — Configure Firebase

1. Create a Firebase project.
2. Enable Firebase Authentication.
3. Enable Email/Password authentication.
4. Enable Cloud Firestore.
5. Register the Android application.
6. Add the required Firebase configuration files.
7. Deploy the project's Firestore security rules.
8. Create the required Firestore indexes.

---

## Step 3 — Configure EmailJS

1. Create an EmailJS account.
2. Add an email service.
3. Create the OTP email template.
4. Configure the required template variables.
5. Obtain the required EmailJS configuration values.
6. Add the values to Firebase Remote Config.
7. Publish the Remote Config changes.

---

## Step 4 — Configure Gemini

1. Obtain a Gemini API key through Google AI Studio.
2. Enable the required Generative Language API.
3. Add the Gemini API key to Firebase Remote Config.
4. Publish the configuration.
5. Restart the application.

---

## Step 5 — Install Dependencies

Run:

```bash
flutter clean
flutter pub get
flutter run
```

---

# 22. Dependencies

| Package                  | Version | Purpose                    |
| ------------------------ | ------: | -------------------------- |
| `firebase_core`          | ^2.32.0 | Firebase initialization    |
| `firebase_auth`          | ^4.16.0 | Authentication             |
| `cloud_firestore`        | ^4.17.5 | Real-time database         |
| `firebase_remote_config` |  ^4.4.0 | Runtime configuration      |
| `http`                   |  ^1.2.0 | API and HTTP communication |
| `encrypt`                |  ^5.0.3 | AES encryption             |
| `crypto`                 |  ^3.0.3 | SHA-256                    |
| `uuid`                   |  ^4.3.3 | Identifier generation      |

---

# 23. Troubleshooting

## OTP Email Not Received

Check:

1. EmailJS configuration values are published.
2. EmailJS service is connected.
3. Template variables match the application.
4. EmailJS Email History for delivery errors.
5. Firebase Remote Config contains the correct values.

---

## OTP Screen Does Not Appear

The OTP screen is displayed after a successful registration attempt.

If it does not appear:

* Check the registration error message.
* Check Firebase Authentication.
* Check the Flutter debug console.

---

## Remote Config Values Not Updating

Check that:

* Remote Config changes were published.
* The application was restarted.
* The development fetch interval is appropriate.

During development, the fetch interval can be reduced to allow configuration changes to be retrieved immediately.

---

## Chat Shows a Raw User ID

Check:

* The participant UID is correctly identified.
* The `users` collection contains the user's profile.
* `ChatService.getUserChats()` performs the username lookup.
* Firestore rules allow the required profile lookup.

---

## Task Assignee Shows a User ID

Check:

* `AIService.extractTasks()` correctly determines the responsible participant.
* The participant username is resolved before saving.
* `TaskService.saveTask()` stores the username in `assignedTo`.

---

## Task Assignee Is Always the Receiver

The system should determine responsibility from message phrasing.

Examples:

```text
"I'll complete the report."
→ Sender
```

```text
"Please complete the report."
→ Receiver
```

Check both the Gemini prompt and the local fallback logic.

---

## Task Title Contains the Entire Message

The fallback extractor should remove:

* "Please"
* "Remember to"
* "Don't forget to"
* Other filler phrases
* Deadline expressions such as:

  * "by Friday"
  * "by 19 July 2026"
  * "on Tuesday"
  * "due next Friday"

Example:

```text
"Please remember to submit the report by this Friday."

↓
"Submit the report"
```

---

## Task Suggestion Reverts to "Add to List"

This can occur if task IDs are regenerated each time extraction runs.

The application uses deterministic task IDs based on the source message so that previously saved tasks can be recognized.

The chat screen should also check Firestore after extraction to restore the saved state.

---

## Task Does Not Appear

Check:

* Gemini API configuration.
* `task_extraction_logs` Firestore permissions.
* Whether the message contains clear actionable content.
* Whether a deadline or recognizable task action is present.

---

## Threat Detection Does Not Update the Message

Check:

* `ThreatService.scanMessage()` receives the correct `chatId`.
* The correct message document is being updated.
* Firestore rules permit the `isThreat` field update.

---

# 24. System Objectives

AutoSecureChat implements four major objectives:

### Objective 1 — Secure Authentication

Provide authenticated access using Firebase Authentication and OTP email verification.

### Objective 2 — Secure Communication

Provide real-time one-to-one messaging protected using AES-256-CBC encryption.

### Objective 3 — AI Productivity and Threat Detection

Use AI to automatically:

* Extract actionable tasks.
* Identify potential cybersecurity threats.
* Assist users in managing tasks and suspicious messages.

### Objective 4 — Security Monitoring

Maintain a security audit trail containing:

```text
Login
Register
Logout
Failed Login
Suspicious Activity
```

These activities are presented through the Security Centre.

---

# 25. Complete System Architecture

```text
                    AutoSecureChat
                          │
             ┌────────────┴────────────┐
             │                         │
       Flutter Application         Firebase
             │                         │
     ┌───────┼────────┐        ┌───────┼────────┐
     │       │        │        │       │        │
   Auth    Chat     Tasks    Auth   Firestore  Remote
     │       │        │               │        Config
     │       │        │               │
     │       ├────────┼───────────────┤
     │       │        │               │
     │   Encryption  AI Processing    │
     │       │        │               │
     │       │    ┌───┴────┐          │
     │       │    │ Gemini │          │
     │       │    └───┬────┘          │
     │       │        │               │
     │       │   ┌────┴─────┐         │
     │       │   │          │         │
     │       │ Threat     Task        │
     │       │ Detection Extraction   │
     │       │   │          │         │
     └───────┴───┴──────────┴─────────┘
                         │
                  AutoSecureChat
                         │
             ┌───────────┼───────────┐
             │           │           │
          Secure      Threat       Task
         Messaging   Monitoring   Automation
```

---

# 26. Final System Summary

AutoSecureChat integrates **secure communication, artificial intelligence, cybersecurity monitoring, and task automation** into a single mobile application.

The completed system provides:

* ✅ Firebase authentication
* ✅ OTP email verification
* ✅ Secure one-to-one messaging
* ✅ AES-256-CBC message encryption
* ✅ SHA-256 key derivation
* ✅ Real-time message delivery
* ✅ AI task extraction
* ✅ Local task extraction fallback
* ✅ Sender/receiver task assignment
* ✅ Username-based identity display
* ✅ Persistent task confirmation
* ✅ Task Dashboard
* ✅ Real-time threat detection
* ✅ Rule-based threat scanning
* ✅ Gemini threat classification
* ✅ Threat logging
* ✅ Security activity monitoring
* ✅ Failed login detection
* ✅ Public IP logging
* ✅ Security audit trail
* ✅ Offline/fallback AI behaviour
* ✅ Firestore-based data management

The six development sprints collectively deliver the core AutoSecureChat objectives: **authentication, secure communication, AI-assisted productivity, real-time threat detection, security monitoring, and end-to-end encryption**.
