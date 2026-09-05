import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/threat_model.dart';
import '../../services/threat_service.dart';

// Displays the threat detection records for the current user.
class ThreatScreen extends StatefulWidget {
  final String userId;

  const ThreatScreen({super.key, required this.userId});

  @override
  State<ThreatScreen> createState() => _ThreatScreenState();
}

class _ThreatScreenState extends State<ThreatScreen> {
  // Controls whether active or resolved threats are displayed.
  bool _showActive = true;

  // Service used to retrieve and manage threat records.
  final ThreatService _threatService = ThreatService();

  // Stream that provides threat records in real time.
  late final Stream<List<ThreatModel>> _threatsStream =
      _threatService.getAllThreats(widget.userId);

  @override
  Widget build(BuildContext context) {
    // Get the current theme colour scheme.
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // App bar for the Threat Detection screen.
      appBar: AppBar(
        title: const Text('Threat Detection'),
        centerTitle: false,
      ),

      // Listen for threat records from the threat service.
      body: StreamBuilder<List<ThreatModel>>(
        stream: _threatsStream,
        builder: (context, snapshot) {
          // Show a loading indicator while threat records are being loaded.
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Display an error message if the threat records cannot be loaded.
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: scheme.error),
                    const SizedBox(height: 12),
                    const Text(
                      'Could not load threats.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snapshot.error}',
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

          // Get all threat records from the stream.
          final allThreats = snapshot.data ?? [];

          // Separate threats into active and resolved records.
          final active = allThreats.where((t) => !t.isResolved).toList();
          final resolved = allThreats.where((t) => t.isResolved).toList();

          // Select the list to display based on the selected tab.
          final threats = _showActive ? active : resolved;

          return Column(
            children: [
              // Display the Active and Resolved tabs.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    // Active threats tab.
                    Expanded(
                      child: _TabPill(
                        label: 'Active (${active.length})',
                        selected: _showActive,
                        selectedColor: Colors.red,
                        onTap: () => setState(() => _showActive = true),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Resolved threats tab.
                    Expanded(
                      child: _TabPill(
                        label: 'Resolved (${resolved.length})',
                        selected: !_showActive,
                        selectedColor: scheme.outline,
                        onTap: () => setState(() => _showActive = false),
                      ),
                    ),
                  ],
                ),
              ),

              // Display the selected threat records.
              Expanded(
                child: threats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Display a safe icon when there are no threats.
                            Icon(
                              Icons.verified_user,
                              size: 64,
                              color: Colors.green[400],
                            ),
                            const SizedBox(height: 16),

                            // Display a message based on the selected tab.
                            Text(
                              _showActive
                                  ? 'No active threats detected.'
                                  : 'No resolved threat records yet.',
                              style: const TextStyle(fontSize: 15),
                            ),

                            const SizedBox(height: 8),

                            // Explain that messages are continuously scanned.
                            Text(
                              'All your messages are being scanned in real time.',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: threats.length,
                        itemBuilder: (context, index) {
                          // Get the threat for the current list position.
                          final threat = threats[index];

                          // Display the threat information in a card.
                          return _ThreatCard(
                            threat: threat,
                            scheme: scheme,
                            onResolve: () => _threatService.dismissThreat(
                              threat.threatId,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Displays a selectable tab for active or resolved threats.
class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // Apply rounded corners to the tap area.
      borderRadius: BorderRadius.circular(20),

      // Change the selected tab when tapped.
      onTap: onTap,

      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,

        // Change the background colour based on selection.
        decoration: BoxDecoration(
          color:
              selected ? selectedColor : selectedColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),

        // Display the tab label.
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: selected ? Colors.white : selectedColor,
          ),
        ),
      ),
    );
  }
}

// Displays a circular checkbox for resolving a threat.
class _ResolveCheckbox extends StatelessWidget {
  final bool resolved;
  final Color color;
  final VoidCallback? onTap;

  const _ResolveCheckbox({
    required this.resolved,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Resolve the threat when the checkbox is tapped.
      onTap: onTap,

      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,

          // Show green when the threat has been resolved.
          color: resolved ? Colors.green : Colors.transparent,

          // Change the border colour based on the threat status.
          border: Border.all(
            color: resolved ? Colors.green : color,
            width: 2,
          ),
        ),

        // Display a check icon for resolved threats.
        child: resolved
            ? const Icon(
                Icons.check,
                size: 16,
                color: Colors.white,
              )
            : null,
      ),
    );
  }
}

// Displays the details of an individual threat.
class _ThreatCard extends StatelessWidget {
  final ThreatModel threat;
  final ColorScheme scheme;
  final VoidCallback onResolve;

  const _ThreatCard({
    required this.threat,
    required this.scheme,
    required this.onResolve,
  });

  // Returns a colour based on the threat severity level.
  static Color _severityColor(ThreatLevel level) {
    switch (level) {
      case ThreatLevel.low:
        return Colors.yellow[700]!;
      case ThreatLevel.medium:
        return Colors.orange;
      case ThreatLevel.high:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get the colour associated with the threat severity.
    final color = _severityColor(threat.severity);

    // Convert the detection time to local time.
    final ts = threat.detectedAt.toLocal();

    // Format the date and time for display.
    final formattedDate = '${ts.day.toString().padLeft(2, '0')}/'
        '${ts.month.toString().padLeft(2, '0')}/'
        '${ts.year}  '
        '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),

      // Add a border around the threat card.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: threat.isResolved
              ? scheme.outlineVariant
              : color.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),

      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display the threat type, resolve checkbox and severity.
            Row(
              children: [
                // Checkbox used to mark an active threat as resolved.
                _ResolveCheckbox(
                  resolved: threat.isResolved,
                  color: color,
                  onTap: threat.isResolved ? null : onResolve,
                ),

                const SizedBox(width: 10),

                // Display the type of detected threat.
                Expanded(
                  child: Text(
                    threat.threatType.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: threat.isResolved ? Colors.grey : null,
                    ),
                  ),
                ),

                // Display the threat severity badge.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: (threat.isResolved ? Colors.grey : color)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    threat.severity.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: threat.isResolved ? Colors.grey : color,
                    ),
                  ),
                ),
              ],
            ),

            // Display the sender username and detection time.
            const SizedBox(height: 6),
            Row(
              children: [
                // Display the sender username when available.
                if (threat.senderUsername.isNotEmpty) ...[
                  Text(
                    '@${threat.senderUsername}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '  ·  ',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],

                // Display the date and time when the threat was detected.
                Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            // Display the source URL when one was detected.
            if (threat.sourceUrl.isNotEmpty) ...[
              const SizedBox(height: 6),
              GestureDetector(
                // Copy the URL to the clipboard when tapped.
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: threat.sourceUrl),
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('URL copied to clipboard'),
                    ),
                  );
                },

                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Link icon.
                      Icon(
                        Icons.link,
                        size: 12,
                        color: scheme.onSurfaceVariant,
                      ),

                      const SizedBox(width: 4),

                      // Display the detected URL.
                      Flexible(
                        child: Text(
                          threat.sourceUrl,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Copy icon.
                      Icon(
                        Icons.copy,
                        size: 11,
                        color: scheme.outlineVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Display a confirmation message for resolved threats.
            if (threat.isResolved) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: Colors.green[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Resolved',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green[600],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
