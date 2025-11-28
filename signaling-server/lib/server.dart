import 'dart:convert';
import 'package:dart_firebase_admin/messaging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

class SignalingServer {
  final Map<String, DeviceInfo> _devices = {};
  final Map<String, List<Map<String, dynamic>>> _pendingSignals = {};
  final Messaging? messaging;

  SignalingServer({this.messaging});

  Router get router {
    final router = Router();

    // Add device endpoint
    router.post('/users', (Request request) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final deviceId = data['deviceId'] as String?;
        final deviceName = data['deviceName'] as String?;
        final fcmToken = data['fcmToken'] as String?;

        if (deviceId == null || deviceName == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'deviceId and deviceName are required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final deviceInfo = DeviceInfo(
          deviceId: deviceId,
          deviceName: deviceName,
          fcmToken: fcmToken,
          registeredAt: DateTime.now(),
        );

        _devices[deviceId] = deviceInfo;

        return Response.ok(
          jsonEncode({
            'success': true,
            'deviceId': deviceId,
            'message': 'Device registered successfully',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // List devices endpoint
    router.get('/users', (Request request) async {
      final devicesList = _devices.values
          .map((device) => {
                'deviceId': device.deviceId,
                'deviceName': device.deviceName,
                'registeredAt': device.registeredAt.toIso8601String(),
              })
          .toList();

      return Response.ok(
        jsonEncode({
          'success': true,
          'devices': devicesList,
          'count': devicesList.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    });

    // WebRTC signaling endpoint
    router.post('/webrtc/<deviceId>/signal',
        (Request request, String deviceId) async {
      try {
        final targetDevice = _devices[deviceId];
        if (targetDevice == null) {
          return Response(
            404,
            body: jsonEncode({'error': 'Device not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final fromDeviceId = data['fromDeviceId'] as String?;
        final signalType = data['signalType'] as String?;

        if (fromDeviceId == null || signalType == null) {
          return Response.badRequest(
            body: jsonEncode(
                {'error': 'fromDeviceId and signalType are required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Store signal for the target device
        if (!_pendingSignals.containsKey(deviceId)) {
          _pendingSignals[deviceId] = [];
        }

        final signal = {
          'fromDeviceId': fromDeviceId,
          'signalType': signalType,
          'timestamp': DateTime.now().toIso8601String(),
        };

        if (data.containsKey('sdp') && data.containsKey('type')) {
          signal['sdp'] = data['sdp'] as String;
          signal['type'] = data['type'] as String;
        }

        if (data.containsKey('candidate') &&
            data.containsKey('sdpMid') &&
            data.containsKey('sdpMLineIndex')) {
          signal['candidate'] = data['candidate'] as String;
          signal['sdpMid'] = data['sdpMid'] as String;
          signal['sdpMLineIndex'] = data['sdpMLineIndex'].toString();
        }

        _pendingSignals[deviceId]!.add(signal);

        // Send FCM notification if it's an offer
        if (signalType == 'offer' &&
            targetDevice.fcmToken != null &&
            messaging != null) {
          final fromDevice = _devices[fromDeviceId];
          final fromDeviceName = fromDevice?.deviceName ?? 'Unknown';

          try {
            await _sendFcmNotification(
              fcmToken: targetDevice.fcmToken!,
              fromDeviceId: fromDeviceId,
              fromDeviceName: fromDeviceName,
              signalType: 'webrtc_offer',
            );
          } catch (e) {
            // Ignore FCM failures for offer notifications but log for visibility.
            print('Failed to send offer notification: $e');
          }
        }

        return Response.ok(
          jsonEncode({
            'success': true,
            'message': 'Signal stored',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Get pending WebRTC signals for a device
    router.get('/webrtc/<deviceId>/signals',
        (Request request, String deviceId) async {
      try {
        final signals = _pendingSignals[deviceId] ?? [];

        // Clear signals after retrieving
        _pendingSignals[deviceId] = [];

        return Response.ok(
          jsonEncode({
            'success': true,
            'signals': signals,
            'count': signals.length,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    // Send connection request via FCM
    router.post('/users/<deviceId>/connect',
        (Request request, String deviceId) async {
      try {
        final targetDevice = _devices[deviceId];
        if (targetDevice == null) {
          return Response(
            404,
            body: jsonEncode({'error': 'Device not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        if (targetDevice.fcmToken == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Device has no FCM token'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        if (messaging == null) {
          return Response.internalServerError(
            body: jsonEncode({'error': 'FCM messaging not configured'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final fromDeviceId = data['fromDeviceId'] as String?;
        final fromDeviceName = data['fromDeviceName'] as String?;

        if (fromDeviceId == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'fromDeviceId is required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        try {
          final messageId = await _sendFcmNotification(
            fcmToken: targetDevice.fcmToken!,
            fromDeviceId: fromDeviceId,
            fromDeviceName: fromDeviceName ?? 'Unknown',
          );

          return Response.ok(
            jsonEncode({
              'success': true,
              'message': 'Connection request sent',
              'messageId': messageId,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        } on FirebaseMessagingAdminException catch (e) {
          return Response.internalServerError(
            body: jsonEncode({
              'error': 'Failed to send FCM notification',
              'code': e.errorCode.code,
              'message': e.message,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        } catch (e) {
          return Response.internalServerError(
            body: jsonEncode({
              'error': 'Failed to send FCM notification',
              'message': e.toString(),
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({'error': e.toString()}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    });

    return router;
  }

  Future<String> _sendFcmNotification({
    required String fcmToken,
    required String fromDeviceId,
    required String fromDeviceName,
    String signalType = 'connection_request',
  }) async {
    final messagingClient = messaging;
    if (messagingClient == null) {
      throw StateError('FCM messaging not configured');
    }

    final isOffer = signalType == 'webrtc_offer';
    final notification = Notification(
      title: isOffer ? 'Incoming Call' : 'Connection Request',
      body: isOffer
          ? '$fromDeviceName is calling you'
          : '$fromDeviceName wants to connect',
    );

    final data = <String, String>{
      'type': signalType,
      'fromDeviceId': fromDeviceId,
      'fromDeviceName': fromDeviceName,
    };

    return messagingClient.send(
      TokenMessage(
        token: fcmToken,
        notification: notification,
        data: data,
      ),
    );
  }

  Handler get handler {
    final pipeline = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(corsHeaders())
        .addHandler(router.call);

    return pipeline;
  }
}

class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String? fcmToken;
  final DateTime registeredAt;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    this.fcmToken,
    required this.registeredAt,
  });
}
