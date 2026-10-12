import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardScreen extends StatefulWidget {
  final String userId;
  final String baseUrl;
  final String? userName;
  final String? phoneNumber;
  final String? bloodGroup;

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.baseUrl,
    this.userName,
    this.phoneNumber,
    this.bloodGroup,
  });
 
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}
 
class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _pollTimer;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
 
  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchStatus());
  }
 
  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
 
  Future<void> _fetchStatus() async {
    final url = Uri.parse('${widget.baseUrl}/emergency/${widget.userId}/status');
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _data = decoded;
            _error = null;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Server returned ${response.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection error: could not reach server';
          _loading = false;
        });
      }
    }
  }
 
  // severity is an int 1-4 per contract. Assumption: 4 = most severe
  // (critical), 1 = least severe. Confirm this direction with whoever
  // owns ai-classification — flip the map below if it's reversed.
  static const Map<int, String> _severityLabels = {
    4: 'CRITICAL',
    3: 'HIGH',
    2: 'MEDIUM',
    1: 'LOW',
  };
 
  Color _severityColor(int? severity) {
    switch (severity) {
      case 4:
        return Colors.red.shade700;
      case 3:
        return Colors.deepOrange;
      case 2:
        return Colors.amber.shade800;
      case 1:
        return Colors.green.shade600;
      default:
        return Colors.grey;
    }
  }
 
  Color _statusColor(String status) {
    switch (status) {
      case 'unresponsive':
        return Colors.red.shade400;
      case 'responding':
        return Colors.blueAccent;
      case 'resolved':
        return Colors.green.shade400;
      default:
        return Colors.grey;
    }
  }
 
  IconData _statusIcon(String status) {
    switch (status) {
      case 'unresponsive':
        return Icons.warning_amber_rounded;
      case 'responding':
        return Icons.directions_run;
      case 'resolved':
        return Icons.check_circle_outline;
      default:
        return Icons.help_outline;
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF15181E),
        title: Text(widget.userName != null
    ? 'Emergency — ${widget.userName}'
    : 'Responder — ${widget.userId}'),
        elevation: 0,
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }
 
  Widget _buildBody() {
    if (_data == null && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_data == null && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchStatus, child: const Text('Retry')),
          ],
        ),
      );
    }
 
    final data = _data!;
    final bool active = data['active'] == true;
    final int? severity = (data['severity'] as num?)?.toInt();
    final String emergencyType = data['type']?.toString() ?? 'Unknown';
    final String status = data['status']?.toString() ?? 'unknown';
    final lat = (data['location']?['lat'] as num?)?.toDouble();
    final lng = (data['location']?['lng'] as num?)?.toDouble();
    final List timeline = (data['timeline'] as List?) ?? [];
    // Per Member 2 spec (Step 2.4), backend generates a formatted summary
    // string even though it's not listed in CONTRACT.md's snippet.
    // Confirm the exact field name with backend — assuming "summary" here.
    final String? summary = data['summary']?.toString();
 
    return RefreshIndicator(
      onRefresh: _fetchStatus,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Last update failed — showing cached data. ($_error)',
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
 
          if (!active)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'This emergency is not currently active.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            if (widget.userName != null) ...[
            _sectionCard(
              title: 'Person in emergency',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.userName!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  if ((widget.bloodGroup ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Blood group: ${widget.bloodGroup}',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                  if ((widget.phoneNumber ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () =>
                          launchUrl(Uri(scheme: 'tel', path: widget.phoneNumber)),
                      icon: const Icon(Icons.call),
                      label: Text('Call ${widget.phoneNumber}'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // Severity + type + status row
          Row(
            children: [
              _buildBadge(_severityLabels[severity] ?? 'UNKNOWN', _severityColor(severity)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emergencyType[0].toUpperCase() + emergencyType.substring(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(_statusIcon(status), size: 14, color: _statusColor(status)),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(color: _statusColor(status), fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
 
          // Map
          if (lat != null && lng != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lng),
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.emergency_assistant',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lng),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 40),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.directions),
                  label: const Text('Open in Google Maps'),
                ),
              ),
            const SizedBox(height: 16),
          ] else
            Container(
              height: 100,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1D24),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('No location data yet', style: TextStyle(color: Colors.white38)),
            ),
          const SizedBox(height: 16),
 
          // AI / backend-generated summary — only shown if backend sends it
          if (summary != null && summary.trim().isNotEmpty) ...[
            _sectionCard(
              title: 'Summary',
              child: Text(
                summary,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
          ],
 
          // Timeline
          _sectionCard(
            title: 'Timeline',
            child: timeline.isEmpty
                ? const Text('No events yet.', style: TextStyle(color: Colors.white38))
                : Column(
                    children: timeline.map<Widget>((event) {
                      final time = event['timestamp']?.toString();
                      final label = event['event']?.toString() ?? '';
                      String formattedTime = time ?? '';
                      try {
                        final dt = DateTime.parse(time!).toLocal();
                        formattedTime = DateFormat('HH:mm:ss').format(dt);
                      } catch (_) {}
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(top: 4, right: 10),
                              decoration: const BoxDecoration(
                                color: Colors.blueAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label,
                                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                                  Text(formattedTime,
                                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
 
  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
 