import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/emergency_service.dart';
import '../utils/severity_helper.dart';
import 'chat_screen.dart';
import 'level1_screen.dart';
import 'level2_screen.dart';

class EmergencyActiveScreen extends StatefulWidget {
  final int initialSeverity;
  final String userId;
  final Map<String, dynamic>? initialData;
  final VoidCallback? onUserSafe;

  const EmergencyActiveScreen({
    super.key,
    required this.initialSeverity,
    required this.userId,
    this.initialData,
    this.onUserSafe,
  });

  @override
  State<EmergencyActiveScreen> createState() =>
      _EmergencyActiveScreenState();
}

class _EmergencyActiveScreenState extends State<EmergencyActiveScreen> {
  late int _severity;

  String? _userMessage;
  String? _levelLabel;

  List<String> _actionsTaken = [];
  List<String> _contactsNotified = [];
  List<Map<String, dynamic>> _nearbyHelp = [];

  bool _locationShared = false;
  bool _escalating = false;
  bool _resolving = false;

  bool _iAmSafeArmed = false;
  Map<String, String> _contactNames = {};
  bool _loadingHelp = false;

  String _nameOf(String id) => _contactNames[id] ?? id;

  @override
  void initState() {
    super.initState();

    _severity = widget.initialSeverity;

    if (widget.initialData != null) {
      _seedInitialData(widget.initialData!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadContactNames();
      _autoFetchHelp();
    });
  }

  void _seedInitialData(Map<String, dynamic> data) {
    _userMessage = data['user_message'] as String?;
    _levelLabel = data['level_label'] as String?;

    _actionsTaken =
        ((data['actions_taken'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();

    _contactsNotified =
        ((data['contacts_notified'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();

    _nearbyHelp =
        ((data['nearby_help'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
  }

  void _applyEventData(Map<String, dynamic> data) {
    final newSeverity = data['current_severity'] as int?;
    final levelLabel = data['level_label'] as String?;

    if (newSeverity != null && newSeverity > _severity) {
      setState(() {
        _severity = newSeverity;
      });
    }

    if (levelLabel != null) {
      _levelLabel = levelLabel;
    }

    setState(() {
      if (data['user_message'] != null) {
        _userMessage = data['user_message'] as String;
      }

      if (data['actions_taken'] != null) {
        _actionsTaken =
            (data['actions_taken'] as List)
                .map((e) => e.toString())
                .toList();
      }

      if (data['contacts_notified'] != null) {
        _contactsNotified =
            (data['contacts_notified'] as List)
                .map((e) => e.toString())
                .toList();
      }

      if (data['nearby_help'] != null) {
        _nearbyHelp =
            (data['nearby_help'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
      }
    });
  }

    Future<void> _autoFetchHelp() async {
    if (_nearbyHelp.isNotEmpty) return;
    setState(() => _loadingHelp = true);
    try {
      final result = await EmergencyService.updateCurrentLocation(
        userId: widget.userId,
      );
      if (!mounted) return;
      _applyEventData(result);
    } catch (_) {
      // permission na mile to user manually "Share My Location" daba sakta hai
    } finally {
      if (mounted) setState(() => _loadingHelp = false);
    }
  }

  Future<void> _loadContactNames() async {
    try {
      final detail =
          await EmergencyService.getContactsDetail(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _contactNames = {
          for (final c in detail)
            c['uid'].toString(): (c['name'] ?? c['uid']).toString(),
        };
      });
    } catch (_) {}
  }
  // ------------------------------------------------------------
  // MANUAL ESCALATION
  // ------------------------------------------------------------

  Future<void> _manualEscalate() async {
    if (_escalating) return;

    setState(() {
      _escalating = true;
    });

    try {
      final result = await EmergencyService.escalateEmergency(
        userId: widget.userId,
        reason: 'User requested emergency escalation',
      );

      if (!mounted) return;

      final contacts = result['contacts_notified'] as List?;

      if (contacts != null) {
        setState(() {
          _contactsNotified =
              contacts.map((e) => e.toString()).toList();
        });
      }

      setState(() {
        _severity = 4;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Emergency escalated. Help contacts have been notified.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to escalate the emergency. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _escalating = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // RESOLVE / I AM SAFE
  // ------------------------------------------------------------

  Future<void> _resolveEmergency() async {
    if (_resolving) return;

    setState(() {
      _resolving = true;
    });

    try {
      await EmergencyService.resolveEmergency(
        userId: widget.userId,
      );

      if (!mounted) return;

      widget.onUserSafe?.call();

      if (widget.onUserSafe == null) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to resolve emergency. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _resolving = false;
        });
      }
    }
  }

  Future<void> _tapIAmSafe() async {
    if (_severity == 4) {
      if (!_iAmSafeArmed) {
        setState(() {
          _iAmSafeArmed = true;
        });

        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _iAmSafeArmed = false;
            });
          }
        });

        return;
      }
    }

    await _resolveEmergency();
  }

  // ------------------------------------------------------------
  // LOCATION
  // ------------------------------------------------------------

  Future<void> _shareLocation() async {
    try {
      final result = await EmergencyService.updateCurrentLocation(
        userId: widget.userId,
      );

      if (!mounted) return;

      _applyEventData(result);

      setState(() {
        _locationShared = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your current location has been shared.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to share your location. Please check location permission.',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // NEARBY HELP
  // ------------------------------------------------------------

  Future<void> _callHospital(String? phone) async {
    if (phone == null || phone.isEmpty) return;

    final uri = Uri(
      scheme: 'tel',
      path: phone,
    );

    final ok = await launchUrl(uri);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start the call.'),
        ),
      );
    }
  }
  Future<void> _openHospitalOnMap(
  Map<String, dynamic> place,
) async {
  final lat = place['lat'];
  final lng = place['lng'];

  if (lat == null || lng == null) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Location for this hospital is unavailable.',
        ),
      ),
    );
    return;
  }

  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  );

  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );

  if (!ok && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open Google Maps.',
        ),
      ),
    );
  }
}
  // ------------------------------------------------------------
  // SHARED UI
  // ------------------------------------------------------------

  Widget _buildActionsTaken() {
    if (_actionsTaken.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ..._actionsTaken.map(
          (action) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('• '),
                Expanded(
                  child: Text(
                    action,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContacts() {
    if (_contactsNotified.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contacts Notified',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ..._contactsNotified.map(
          (contact) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person),
            title: Text(_nameOf(contact)),
          ),
        ),
      ],
    );
  }

  Widget _buildNearbyHelp({
    bool withCallButton = false,
  }) {
    if (_nearbyHelp.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nearby Help',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ..._nearbyHelp.take(3).map(
          (place) {
            final name =
                place['name']?.toString() ?? 'Nearby help';

            final distance = place['distance'];

            final address =
                place['address']?.toString() ?? '';

            final phone =
                place['phone']?.toString();

return Card(
  child: ListTile(
    leading: const Icon(
      Icons.local_hospital_outlined,
    ),
    title: Text(name),
    subtitle: Text(
      distance != null
          ? '$distance km\n$address'
          : address,
    ),
    onTap: () => _openHospitalOnMap(place),
    trailing: withCallButton &&
            phone != null &&
            phone.isNotEmpty
        ? IconButton(
            icon: const Icon(Icons.call),
            onPressed: () =>
                _callHospital(phone),
          )
        : null,
  ),
);
          },
        ),
      ],
    );
  }

  Widget _buildChatButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                userId: widget.userId,
              ),
            ),
          );
        },
        icon: const Icon(
          Icons.chat_bubble_outline,
        ),
        label: const Text(
          'Open Chat for Help',
        ),
      ),
    );
  }

  Widget _buildLocationButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed:
            _locationShared ? null : _shareLocation,
        icon: Icon(
          _locationShared
              ? Icons.check_circle
              : Icons.location_on,
        ),
        label: Text(
          _locationShared
              ? 'Location Shared'
              : 'Share My Location',
        ),
      ),
    );
  }

  Widget _buildManualEscalationButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _escalating ? null : _manualEscalate,
        icon: _escalating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.warning_amber_rounded),
        label: Text(
          _escalating
              ? 'Escalating...'
              : 'I Still Need Help — Escalate',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(
            vertical: 16,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // LEVEL 2
  // ------------------------------------------------------------

  Widget _buildLevel2() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: severityBackground(2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userMessage ??
                          'This is a moderate emergency. Stay calm and follow the recommended actions.',
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.4,
                      ),
                    ),

                    const SizedBox(height: 20),

                    _buildActionsTaken(),

                    if (_actionsTaken.isNotEmpty)
                      const SizedBox(height: 20),

                    _buildContacts(),

                    if (_contactsNotified.isNotEmpty)
                      const SizedBox(height: 20),

                    _buildNearbyHelp(),

                    if (_nearbyHelp.isNotEmpty)
                      const SizedBox(height: 20),

                    _buildLocationButton(),

                    const SizedBox(height: 12),

                    _buildChatButton(),

                    const SizedBox(height: 12),

                    _buildManualEscalationButton(),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _resolving ? null : _resolveEmergency,
                        icon: _resolving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.check_circle_outline,
                              ),
                        label: const Text(
                          'I AM SAFE — End Emergency',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // LEVEL 3
  // ------------------------------------------------------------

  Widget _buildLevel3() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              color: severityBackground(3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Mode Active',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: severityColor(3),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _userMessage ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 20),

                    _buildActionsTaken(),

                    const SizedBox(height: 16),

                    _buildContacts(),

                    const SizedBox(height: 16),

                    _buildNearbyHelp(
                      withCallButton: true,
                    ),

                    const SizedBox(height: 16),

                    _buildLocationButton(),

                    const SizedBox(height: 12),

                    _buildChatButton(),

                    const SizedBox(height: 12),

                    _buildManualEscalationButton(),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _resolving
                            ? null
                            : _resolveEmergency,
                        child: const Text(
                          'I AM SAFE — End Emergency',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
// LEVEL 4
// ------------------------------------------------------------

Widget _buildLevel4() {
  return Container(
    color: Colors.red.shade900,
    width: double.infinity,
    height: double.infinity,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),

            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 60,
            ),

            const SizedBox(height: 12),

            const Text(
              'CRITICAL EMERGENCY',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Emergency assistance has been escalated.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 20),

            if (_userMessage != null)
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _userMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 20),

            // ------------------------------------------------
            // AMBULANCE
            // ------------------------------------------------

            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  _callEmergencyNumber('1122');
                },
                icon: const Icon(
                  Icons.local_hospital,
                  size: 28,
                ),
                label: const Text(
                  'CALL AMBULANCE',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ------------------------------------------------
            // POLICE
            // ------------------------------------------------

            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  _callEmergencyNumber('911');
                },
                icon: const Icon(
                  Icons.local_police,
                  size: 28,
                ),
                label: const Text(
                  'CALL EMERGENCY HELPLINE',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ------------------------------------------------
            // CONTACTS NOTIFIED
            // ------------------------------------------------

            if (_contactsNotified.isNotEmpty) ...[
              const Text(
                'Trusted Contacts Notified',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: _contactsNotified
                        .map(
                          (contact) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.person,
                            ),
                            title: Text(_nameOf(contact)),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],

            // ------------------------------------------------
            // NEARBY HOSPITALS
            // ------------------------------------------------

            const Text(
              'Nearby Hospitals',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            if (_nearbyHelp.isNotEmpty)
              _buildNearbyHelp(
                withCallButton: true,
              )
                        else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _loadingHelp
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Text('Finding nearby hospitals...'),
                          ],
                        )
                      : Text(
                          'No nearby hospitals found. Tap "Share My Location" to retry.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                ),
              ),
            const SizedBox(height: 20),

            // ------------------------------------------------
            // LOCATION
            // ------------------------------------------------

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    _locationShared ? null : _shareLocation,
                icon: Icon(
                  _locationShared
                      ? Icons.check_circle
                      : Icons.location_on,
                ),
                label: Text(
                  _locationShared
                      ? 'Location Shared'
                      : 'Share My Location',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(
                    color: Colors.white,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 15,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ------------------------------------------------
            // I AM SAFE
            // ------------------------------------------------

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _tapIAmSafe,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                child: Text(
                  _iAmSafeArmed
                      ? 'TAP AGAIN TO CONFIRM'
                      : 'I AM SAFE',
                ),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _iAmSafeArmed
                  ? 'Tap again within 5 seconds to confirm you are safe.'
                  : 'Double tap required to end a critical emergency.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 10),
          ],
        ),
      ),
    ),
  );
}
Future<void> _callEmergencyNumber(String number) async {
  final uri = Uri(
    scheme: 'tel',
    path: number,
  );

  final ok = await launchUrl(uri);

  if (!ok && mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not start the call.'),
      ),
    );
  }
}
  @override
  Widget build(BuildContext context) {
    if (_severity == 4) {
      return Scaffold(
        body: _buildLevel4(),
      );
    }

    Widget content;

    switch (_severity) {
      case 2:
        content = _buildLevel2();
        break;

      case 3:
        content = _buildLevel3();
        break;

      case 1:
      default:
        content = _buildLevel3();
        break;
    }

    return Scaffold(
      backgroundColor: severityBackground(_severity),
      appBar: AppBar(
        title: Text(
          'Emergency — ${_levelLabel ?? severityLabel(_severity)}',
        ),
        backgroundColor: severityColor(_severity),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: content,
      ),
    );
  }
}