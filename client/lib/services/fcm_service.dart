import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'webrtc_service.dart';
import '../screens/connection_screen.dart';

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static WebRTCService? _activeWebRTCService;
  static String? _activeRemoteDeviceId;

  static Future<String?> getToken() async {
    try {
      // Request permission for iOS
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final token = await _messaging.getToken();
        return token;
      }
      return null;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  static void configureMessageHandlers({
    required String deviceId,
    required BuildContext context,
  }) {
    // Handle foreground messages (data-only, no notification)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received FCM data message: ${message.messageId}');
      print('Data: ${message.data}');

      _handleFCMDataMessage(message, context);
    });
  }

  static void _handleFCMDataMessage(
    RemoteMessage message,
    BuildContext context,
  ) {
    final type = message.data['type'] as String?;
    final fromDeviceId = message.data['fromDeviceId'] as String?;
    final fromDeviceName = message.data['fromDeviceName'] as String?;

    if (type == null || fromDeviceId == null || fromDeviceName == null) {
      return;
    }

    // Handle WebRTC offer
    if (type == 'offer') {
      final sdp = message.data['sdp'] as String?;
      final sdpType = message.data['sdpType'] as String?;

      if (sdp != null && sdpType != null && context.mounted) {
        _showIncomingConnectionSnackbar(
          context,
          fromDeviceId,
          fromDeviceName,
          sdp,
          sdpType,
        );
      }
    }
    // Handle WebRTC answer
    else if (type == 'answer') {
      final sdp = message.data['sdp'] as String?;
      final sdpType = message.data['sdpType'] as String?;

      if (sdp != null && sdpType != null && _activeWebRTCService != null) {
        // Verify this answer is for the active connection
        if (_activeRemoteDeviceId == fromDeviceId) {
          _activeWebRTCService!.handleAnswer(sdp: sdp, type: sdpType);
        }
      }
    }
    // Handle ICE candidate
    else if (type == 'ice-candidate') {
      final candidate = message.data['candidate'] as String?;
      final sdpMid = message.data['sdpMid'] as String?;
      final sdpMLineIndex = message.data['sdpMLineIndex'] as String?;

      if (candidate != null &&
          sdpMid != null &&
          sdpMLineIndex != null &&
          _activeWebRTCService != null) {
        // Verify this ICE candidate is for the active connection
        if (_activeRemoteDeviceId == fromDeviceId) {
          _activeWebRTCService!.handleIceCandidate(
            candidate: candidate,
            sdpMid: sdpMid,
            sdpMLineIndex: sdpMLineIndex,
          );
        }
      }
    }
    // Handle connection request (legacy)
    else if (type == 'connection_request') {
      print('Connection request from: $fromDeviceName');
    }
  }

  static void _showIncomingConnectionSnackbar(
    BuildContext context,
    String fromDeviceId,
    String fromDeviceName,
    String sdp,
    String type,
  ) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('$fromDeviceName wants to connect'),
        duration: const Duration(seconds: 10),
        backgroundColor: Colors.blue[700],
        action: SnackBarAction(
          label: 'Accept',
          textColor: Colors.white,
          onPressed: () async {
            scaffoldMessenger.hideCurrentSnackBar();
            await _acceptIncomingConnection(
              context,
              fromDeviceId,
              fromDeviceName,
              sdp,
              type,
            );
          },
        ),
        // Add dismiss callback to handle rejection
        onVisible: () {
          // Auto-dismiss after 10 seconds is rejection
        },
      ),
    );
  }

  static Future<void> _acceptIncomingConnection(
    BuildContext context,
    String fromDeviceId,
    String fromDeviceName,
    String sdp,
    String type,
  ) async {
    try {
      // Initialize WebRTC service
      final webrtcService = WebRTCService();
      await webrtcService.initialize();

      // Store active service for handling answer/ICE candidates
      _activeWebRTCService = webrtcService;
      _activeRemoteDeviceId = fromDeviceId;

      // Handle the incoming connection offer
      await webrtcService.handleIncomingConnection(
        fromDeviceId: fromDeviceId,
        sdp: sdp,
        type: type,
      );

      // Navigate to connection screen
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ConnectionScreen(
              remoteDeviceName: fromDeviceName,
              remoteDeviceId: fromDeviceId,
              isIncoming: true,
              webrtcService: webrtcService,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error accepting incoming connection: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting connection: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static void setActiveWebRTCService(
    WebRTCService? service,
    String? remoteDeviceId,
  ) {
    _activeWebRTCService = service;
    _activeRemoteDeviceId = remoteDeviceId;
  }

  static void clearActiveWebRTCService() {
    _activeWebRTCService = null;
    _activeRemoteDeviceId = null;
  }

  static void stopPolling() {
    // No longer needed - all signaling goes through FCM data messages
    // Kept for compatibility with existing code
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.messageId}');
  print('Data: ${message.data}');
  // Note: In background handler, we can't show UI directly
  // The app will need to handle this when it comes to foreground
}
