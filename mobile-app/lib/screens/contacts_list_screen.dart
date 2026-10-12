import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/emergency_service.dart';
import 'add_contact_screen.dart';

class ContactsListScreen extends StatefulWidget {
  const ContactsListScreen({super.key});

  @override
  State<ContactsListScreen> createState() => _ContactsListScreenState();
}

class _ContactsListScreenState extends State<ContactsListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _trustedDetail = [];
  List<String> _trusted = [];
  Map<String, String> _trustedNames = {};
  List<Map<String, dynamic>> _allResults = [];
  final Set<String> _adding = {};
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Timer? _requestsTimer;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadAll();
    // naye friend requests khud aa jayein
    _requestsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
  _loadIncoming();
  _loadTrusted();
});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _requestsTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTrusted(), _loadBrowse(), _loadIncoming()]);
  }

  Future<void> _loadIncoming() async {
    try {
      final reqs = await EmergencyService.getIncomingRequests();
      if (!mounted) return;
      setState(() => _incoming = reqs);
    } catch (_) {}
  }

  Future<void> _respond(String fromUid, bool accept) async {
    try {
      await EmergencyService.respondToRequest(fromUid: fromUid, accept: accept);
      await _loadIncoming();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? 'Request accepted' : 'Request declined'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Try again.')),
      );
    }
  }

  Future<void> _confirmRemove(String contactId) async {
    final name = _trustedNames[contactId] ?? contactId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact?'),
        content: Text('$name will no longer get your emergency alerts.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;

    final myId = FirebaseAuth.instance.currentUser?.uid;
    if (myId == null) return;
    try {
      await EmergencyService.removeContact(
          myUserId: myId, contactId: contactId);
      await _loadTrusted();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to remove contact')),
      );
    }
  }

  Future<void> _loadTrusted() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() {
        _errorMessage = 'User not authenticated.';
        _isLoading = false;
      });
      return;
    }

    try {
      final detail = await EmergencyService.getContactsDetail(userId: userId);
      if (!mounted) return;
      setState(() {
        _trustedDetail = detail;
        _trusted = detail.map((c) => c['uid'].toString()).toList();
        _trustedNames = {
          for (final c in detail)
            c['uid'].toString(): (c['name'] ?? c['uid']).toString(),
        };
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load trusted contacts.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadBrowse() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    try {
      final users = await EmergencyService.browseUsers(excludeUserId: userId);
      if (!mounted) return;
      setState(() {
        _allResults = users;
      });
    } catch (_) {
      // non-fatal for browse
    }
  }

  void _onSearchChanged() {
    setState(() {}); // label/list turant badle
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = _searchController.text.trim();
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      try {
        final users = q.isEmpty
            ? await EmergencyService.browseUsers(excludeUserId: userId)
            : await EmergencyService.searchUsers(
                query: q, excludeUserId: userId);
        if (!mounted) return;
        setState(() {
          _allResults = users;
        });
      } catch (_) {
        // ignore search errors silently
      }
    });
  }

  Future<void> _addTrusted(String contactId) async {
    final myUserId = FirebaseAuth.instance.currentUser?.uid;
    if (myUserId == null) return;

    setState(() {
      _adding.add(contactId);
    });

    try {
      await EmergencyService.addContact(
          myUserId: myUserId, contactId: contactId);
      if (!mounted) return;
      setState(() {
        _adding.remove(contactId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Request sent. Contact must accept first.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adding.remove(contactId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add contact')),
      );
    }
  }

  Future<void> _callNumber(String number) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot place a call on this device')),
      );
    }
  }

  Future<void> _smsNumber(String number) async {
    final ok = await launchUrl(Uri(scheme: 'sms', path: number));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot send SMS on this device')),
      );
    }
  }

  void _openAddScreen() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AddContactScreen()))
        .then((_) => _loadTrusted());
  }

  Widget _buildTrustedList() {
    if (_trustedDetail.isEmpty) {
      return const Center(
        child: Text('No trusted contacts yet. Search a user above to add.'),
      );
    }
    return ListView.separated(
      itemCount: _trustedDetail.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, i) {
        final c = _trustedDetail[i];
        final uid = c['uid'].toString();
        final name = c['name']?.toString() ?? uid;
        final phone = c['phone_number']?.toString() ?? '';
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(name),
          subtitle: Text(phone.isNotEmpty ? phone : 'No phone number'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.message_outlined),
                onPressed: phone.isNotEmpty ? () => _smsNumber(phone) : null,
              ),
              IconButton(
                icon: const Icon(Icons.call_outlined),
                onPressed: phone.isNotEmpty ? () => _callNumber(phone) : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _confirmRemove(uid),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_allResults.isEmpty) {
      return const Center(child: Text('No users found'));
    }
    return ListView.separated(
      itemCount: _allResults.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final user = _allResults[index];
        final uid = user['uid']?.toString() ?? '';
        final name = user['name']?.toString() ?? '';
        final email = user['email']?.toString() ?? '';
        final alreadyTrusted = _trusted.contains(uid);
        final isAdding = _adding.contains(uid);
        return ListTile(
          title: Text(name.isNotEmpty ? name : email),
          subtitle: Text(email),
          trailing: alreadyTrusted
              ? const Icon(Icons.check, color: Colors.green)
              : ElevatedButton(
                  onPressed: isAdding ? null : () => _addTrusted(uid),
                  child: isAdding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _searchController.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search all users',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              if (_incoming.isNotEmpty) ...[
                const Text('Friend requests',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._incoming.map((r) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_add_alt_1),
                        title: Text(r['name']?.toString() ?? ''),
                        subtitle: Text(
                          '${r['email'] ?? ''}\nwants to add you as a trusted contact',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () =>
                                  _respond(r['uid'].toString(), false),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.check, color: Colors.green),
                              onPressed: () =>
                                  _respond(r['uid'].toString(), true),
                            ),
                          ],
                        ),
                      ),
                    )),
                const SizedBox(height: 12),
              ],

              Text(
                searching ? 'Search results' : 'Trusted contacts',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : searching
                        ? _buildSearchResults()
                        : _buildTrustedList(),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddScreen,
        child: const Icon(Icons.add),
      ),
    );
  }
}