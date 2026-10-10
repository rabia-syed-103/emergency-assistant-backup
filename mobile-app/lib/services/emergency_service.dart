import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_header_service.dart';
import 'package:geolocator/geolocator.dart';
import '../config.dart';

class EmergencyService {
   static const String _baseUrl = AppConfig.baseUrl;
  

  static Future<List<Map<String, dynamic>>> getContactsDetail({
  required String userId,
}) async {
  final authHeader = await AuthHeaderService.getAuthHeader();
  final response = await http.get(
    Uri.parse('$_baseUrl/contacts/$userId'),
    headers: {'Content-Type': 'application/json', ...authHeader},
  );
  if (response.statusCode == 200) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['contacts_detail'] as List? ?? [])
        .cast<Map<String, dynamic>>();
  }
  throw Exception('Backend error ${response.statusCode}: ${response.body}');
}
  static Map<String, dynamic> _parseEmergencyResponse(
    Map<String, dynamic> data,
  ) {
    return {
      'event_id': data['event_id'] as String,
      'timestamp': data['timestamp'] as String,
      'current_severity': data['current_severity'] as int,
      'level_label': data['level_label'] as String,
      'actions_taken': (data['actions_taken'] as List)
          .map((action) => action.toString())
          .toList(),
      'user_message': data['user_message'] as String,
      'contacts_notified': (data['contacts_notified'] as List)
          .map((contact) => contact.toString())
          .toList(),
      'nearby_help': (data['nearby_help'] as List)
          .map((help) => Map<String, dynamic>.from(help as Map))
          .toList(),
      'chat_available': data['chat_available'] as bool,
    };
  }

  static Map<String, dynamic> _emergencyFallback({
    required int? currentSeverity,
  }) {
    return {
      'event_id': 'offline-fallback',
      'timestamp': DateTime.now().toIso8601String(),
      'current_severity': currentSeverity,
      'level_label': 'minor',
      'actions_taken': <String>[],
      'user_message': 'Emergency services are temporarily unavailable.',
      'contacts_notified': <String>[],
      'nearby_help': <Map<String, dynamic>>[],
      'chat_available': true,
    };
  }

static Future<Map<String, dynamic>> saveProfile({
  required String name,
  required String phone,
  required String bloodGroup,
  required DateTime dob,
}) async {
  final uri = Uri.parse('$_baseUrl/users/profile'); // <-- /users/profile

  final authHeader = await AuthHeaderService.getAuthHeader();
  if (authHeader.isEmpty) {
    throw Exception('No authenticated user available for profile save.');
  }

  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      ...authHeader,
    },
    body: jsonEncode({
      'name': name,
      'phone_number': phone, // <-- phone_number
      'blood_group': bloodGroup,
      'dob': dob.toIso8601String().split('T').first,
    }),
  );

  if (response.statusCode >= 200 && response.statusCode < 300) {
    return response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
  }

  throw Exception('Backend error ${response.statusCode}: ${response.body}');
}



  static Future<Map<String, dynamic>> updateCurrentLocation({
  required String userId,
}) async {
  final serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    throw Exception('Location services are disabled.');
  }

  LocationPermission permission =
      await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission =
        await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception('Location permission denied.');
  }

  final position =
      await Geolocator.getCurrentPosition(
    locationSettings:
        const LocationSettings(
      accuracy: LocationAccuracy.high,
    ),
  );

  final uri = Uri.parse(
    '$_baseUrl/emergency/event',
  );

  final authHeader =
      await AuthHeaderService.getAuthHeader();

  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      ...authHeader,
    },
    body: jsonEncode({
  'user_id': userId,
  'type': 'location_update',
  'payload': {
    'lat': position.latitude,
    'lng': position.longitude,
    'share_location': true,
  },
}),
  );

  if (response.statusCode == 200) {
    return _parseEmergencyResponse(
      jsonDecode(response.body)
          as Map<String, dynamic>,
    );
  }

  throw Exception(
    'Location update failed: '
    '${response.statusCode}: ${response.body}',
  );
}



static Future<Map<String, dynamic>> getProfile() async {
  final uri = Uri.parse('$_baseUrl/users/profile/me'); // <-- /users/profile/me
  // baqi code same rehne do

    final authHeader = await AuthHeaderService.getAuthHeader();
    if (authHeader.isEmpty) {
      throw Exception('No authenticated user available for profile retrieval.');
    }

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        ...authHeader,
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception('Backend error ${response.statusCode}: ${response.body}');
  }

static Future<Map<String, dynamic>> triggerEmergency({
  required String userId,
  String description = 'Emergency SOS activated',
}) async {
  final uri = Uri.parse('$_baseUrl/emergency/event');

  try {
    // Try to get current location, but don't block the SOS if it fails
    double? lat;
    double? lng;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
          lat = position.latitude;
          lng = position.longitude;
        }
      }
    } catch (locErr) {
      print('Could not get location for trigger: $locErr');
      // proceed without location — SOS should never be blocked by GPS failure
    }

    final authHeader = await AuthHeaderService.getAuthHeader();
    final payload = <String, dynamic>{
      'description': description,
      if (lat != null && lng != null) 'lat': lat,
      if (lat != null && lng != null) 'lng': lng,
    };

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        ...authHeader,
      },
      body: jsonEncode({
        'user_id': userId,
        'type': 'trigger',
        'payload': payload,
      }),
    );

    if (response.statusCode == 200) {
      return _parseEmergencyResponse(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    throw Exception('Backend error ${response.statusCode}: ${response.body}');
  } catch (e) {
    print('triggerEmergency failed, using fallback: $e');
    return _emergencyFallback(currentSeverity: 2);
  }
}
  static Future<Map<String, dynamic>> submitAssessment({
  required String userId,
  required String description,
  required Map<String, String> answers,
}) async {
  final uri = Uri.parse('$_baseUrl/emergency/event');

  final authHeader = await AuthHeaderService.getAuthHeader();

  final response = await http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      ...authHeader,
    },
    body: jsonEncode({
      'user_id': userId,
      'type': 'trigger',
      'payload': {
        'description': description,
        'assessment_answers': answers,
      },
    }),
  );

  if (response.statusCode == 200) {
    return _parseEmergencyResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  throw Exception(
    'Backend error ${response.statusCode}: ${response.body}',
  );
}
  static Future<Map<String, dynamic>> submitAnswer({
    required String userId,
    required String questionId,
    required String answer,
  }) async {
    final uri = Uri.parse('$_baseUrl/emergency/event');

    try {
      final authHeader = await AuthHeaderService.getAuthHeader();
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...authHeader,
        },
        body: jsonEncode({
          'user_id': userId,
          'type': 'answer',
          'payload': {
            'question_id': questionId,
            'answer': answer,
          },
        }),
      );

      if (response.statusCode == 200) {
        return _parseEmergencyResponse(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }

      throw Exception('Backend error ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('submitAnswer failed, using fallback: $e');
      return _emergencyFallback(currentSeverity: null);
    }
  }

  static Future<Map<String, dynamic>> escalateEmergency({
    required String userId,
    required String reason,
  }) async {
    final uri = Uri.parse('$_baseUrl/emergency/$userId/escalate');

    try {
      final authHeader = await AuthHeaderService.getAuthHeader();
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...authHeader,
        },
        body: jsonEncode({'reason': reason}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      throw Exception('Backend error ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('escalateEmergency failed, using fallback: $e');
      return {
        'escalated': true,
        'contacts_notified': <String>[],
      };
    }
  }

  static Future<void> resolveEmergency({
    required String userId,
  }) async {
    final uri = Uri.parse('$_baseUrl/emergency/$userId/resolve');

    final authHeader = await AuthHeaderService.getAuthHeader();
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        ...authHeader,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Resolve failed: ${response.statusCode}');
    }
  }

static Future<List<Map<String, dynamic>>> searchUsers({
  required String query,
  required String excludeUserId,
}) async {
  final trimmed = query.trim();

  final uri = Uri.parse('$_baseUrl/users/search').replace(
    queryParameters: {
      'q': trimmed,
      'exclude': excludeUserId,
    },
  );

  final authHeader = await AuthHeaderService.getAuthHeader();

  if (authHeader.isEmpty) {
    throw Exception('No authenticated user available for user search.');
  }

  final response = await http.get(
    uri,
    headers: {
      'Content-Type': 'application/json',
      ...authHeader,
    },
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Search failed: ${response.statusCode}: ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body);

  if (decoded is Map<String, dynamic>) {
    final users = decoded['users'];

    if (users is List) {
      return users
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
  }

  return <Map<String, dynamic>>[];
}

  static Future<Map<String, dynamic>> sendChatMessage({
    required String userId,
    required String message,
    required List<Map<String, dynamic>> conversationHistory,
  }) async {
    const fallbackReply =
        "Sorry, I'm having trouble responding right now. If this feels urgent, "
        'please use the SOS button or contact emergency services directly.';
    final uri = Uri.parse('$_baseUrl/emergency/chat');

    try {
      final authHeader = await AuthHeaderService.getAuthHeader();
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...authHeader,
        },
        body: jsonEncode({
          'user_id': userId,
          'message': message,
          'conversation_history': conversationHistory,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      throw Exception('Backend error ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('sendChatMessage failed, using fallback: $e');
      return {'reply': fallbackReply};
    }
  }

  static Future<List<Map<String, dynamic>>> browseUsers({
  required String excludeUserId,
}) async {
  final uri = Uri.parse('$_baseUrl/users').replace(
    queryParameters: {
      'exclude': excludeUserId,
    },
  );

  final authHeader = await AuthHeaderService.getAuthHeader();

  if (authHeader.isEmpty) {
    throw Exception(
      'No authenticated user available for browsing users.',
    );
  }

  final response = await http.get(
    uri,
    headers: {
      'Content-Type': 'application/json',
      ...authHeader,
    },
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Backend error ${response.statusCode}: ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body);

  if (decoded is Map<String, dynamic>) {
    final users = decoded['users'];

    if (users is List) {
      return users
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }
  }

  return <Map<String, dynamic>>[];
}
  static Future<Map<String, dynamic>> addContact({
    required String myUserId,
    required String contactId,
  }) async {
    final uri = Uri.parse('$_baseUrl/contacts/$myUserId/add');

    final authHeader = await AuthHeaderService.getAuthHeader();
    if (authHeader.isEmpty) {
      throw Exception('No authenticated user available for adding contact.');
    }

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        ...authHeader,
      },
      body: jsonEncode({'contact_id': contactId}),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
    }

    throw Exception('Backend error ${response.statusCode}: ${response.body}');
  }

  static Future<List<String>> getContacts({
    required String userId,
  }) async {
    final uri = Uri.parse('$_baseUrl/contacts/$userId');

    final authHeader = await AuthHeaderService.getAuthHeader();
    if (authHeader.isEmpty) {
      throw Exception('No authenticated user available for fetching contacts.');
    }

    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        ...authHeader,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Backend error ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final contacts = decoded['contacts'];
      if (contacts is List) {
        return contacts.map((item) => item.toString()).toList();
      }
    }
    if (decoded is List) {
      return decoded.map((item) => item.toString()).toList();
    }
    return <String>[];
  }
}