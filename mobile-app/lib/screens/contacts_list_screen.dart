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
  List<String> _trusted = [];
  Map<String, String> _trustedNames = {};
  List<Map<String, dynamic>> _allResults = [];
  Set<String> _adding = {};
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadAll();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadTrusted(), _loadBrowse()]);
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
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final q = _searchController.text.trim();
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;

      try {
        final users = q.isEmpty
            ? await EmergencyService.browseUsers(excludeUserId: userId)
            : await EmergencyService.searchUsers(query: q, excludeUserId: userId);
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
      await EmergencyService.addContact(myUserId: myUserId, contactId: contactId);
      await _loadTrusted();
      if (!mounted) return;
      setState(() {
        _adding.remove(contactId);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to trusted contacts')));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adding.remove(contactId);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add contact')));
    }
  }

  bool _looksLikePhone(String s) {
    return RegExp(r"^\+?[0-9]{6,15}").hasMatch(s);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Search field for all registered users
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search all users',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Trusted contacts horizontal bar
              if (_trusted.isNotEmpty) ...[
                const Text('Trusted contacts', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _trusted.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final id = _trusted[i];
                      final displayName = _trustedNames[id] ?? id;
                      return Chip(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        label: Text(displayName,style: const TextStyle(fontSize: 12)),
                        avatar: const Icon(Icons.person, size: 18),
                        onDeleted: () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remove isn\'t available yet.')));
                        },
                        deleteIcon: const Icon(Icons.close),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const Text('All users', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _allResults.isEmpty
                        ? const Center(child: Text('No users found'))
                        : ListView.separated(
                            itemCount: _allResults.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final user = _allResults[index];

                            final uid = user['uid']?.toString() ?? '';
                            final name = user['name']?.toString() ?? '';
                            final email = user['email']?.toString() ?? '';
                            final phoneNumber = user['phone_number']?.toString() ?? '';

                            final alreadyTrusted = _trusted.contains(uid);
                            final isAdding = _adding.contains(uid);

                              return ListTile(
                               title: Text(name.isNotEmpty ? name : uid),
                                subtitle: Text(
                                  phoneNumber.isNotEmpty
                                      ? phoneNumber
                                      : (email.isNotEmpty ? email : 'No phone number'),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                    icon: const Icon(Icons.message_outlined),
                                    onPressed: phoneNumber.isNotEmpty
                                        ? () => _smsNumber(phoneNumber)
                                        : () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('No phone number available for this user.'),
                                              ),
                                            );
                                          },
                                  ),
                                    IconButton(
                                      icon: const Icon(Icons.call_outlined),
                                      onPressed: phoneNumber.isNotEmpty
                                          ? () => _callNumber(phoneNumber)
                                          : () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('No phone number available for this user.'),
                                                ),
                                              );
                                            },
                                    ),
                                    const SizedBox(width: 8),
                                    if (alreadyTrusted)
                                      const Icon(Icons.check, color: Colors.green)
                                    else
                                      ElevatedButton(
                                        onPressed: isAdding ? null : () => _addTrusted(uid),
                                        child: isAdding ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
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
