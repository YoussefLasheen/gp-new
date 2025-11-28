import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiService {
  // Update this to match your server URL
  static const String baseUrl = 'http://localhost:8080';

  static Future<Map<String, dynamic>> registerDevice({
    required String deviceId,
    required String deviceName,
    String? fcmToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': deviceId,
          'deviceName': deviceName,
          'fcmToken': fcmToken,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to register device: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error registering device: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final devices = data['devices'] as List;
        return devices.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to get users: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error getting users: $e');
    }
  }

  static Future<Map<String, dynamic>> sendConnectionRequest({
    required String targetDeviceId,
    required String fromDeviceId,
    required String fromDeviceName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users/$targetDeviceId/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fromDeviceId': fromDeviceId,
          'fromDeviceName': fromDeviceName,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to send connection request: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error sending connection request: $e');
    }
  }
}

