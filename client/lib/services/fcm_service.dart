import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'api_service.dart';
import 'webrtc_service.dart';
import '../screens/call_screen.dart';

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static Function(String, String, String)? onIncomingCall;
  static Timer? _signalPollTimer;
  static String? _currentDeviceId;

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
    _currentDeviceId = deviceId;
    
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received message: ${message.messageId}');
      print('Notification: ${message.notification?.title}');
      print('Data: ${message.data}');
      
      final type = message.data['type'] as String?;
      final fromDeviceId = message.data['fromDeviceId'] as String?;
      final fromDeviceName = message.data['fromDeviceName'] as String?;

      if (type == 'webrtc_offer' && fromDeviceId != null && fromDeviceName != null) {
        // Start polling for WebRTC signals
        _startSignalPolling(context, fromDeviceId, fromDeviceName);
      } else if (type == 'connection_request') {
        print('Connection request from: $fromDeviceName');
      }
    });

    // Handle background messages (when app is terminated)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notification taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification opened app: ${message.messageId}');
      final type = message.data['type'] as String?;
      final fromDeviceId = message.data['fromDeviceId'] as String?;
      final fromDeviceName = message.data['fromDeviceName'] as String?;

      if (type == 'webrtc_offer' && fromDeviceId != null && fromDeviceName != null) {
        _startSignalPolling(context, fromDeviceId, fromDeviceName);
      }
    });
  }

  static void _startSignalPolling(
    BuildContext context,
    String fromDeviceId,
    String fromDeviceName,
  ) {
    _stopSignalPolling();

    _signalPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        if (_currentDeviceId == null) return;

        final response = await ApiService.getWebRTCSignals(deviceId: _currentDeviceId!);
        final signals = response['signals'] as List?;

        if (signals != null && signals.isNotEmpty) {
          _stopSignalPolling();

          // Find the offer signal
          final offerSignal = signals.firstWhere(
            (signal) => signal['signalType'] == 'offer' && signal['fromDeviceId'] == fromDeviceId,
            orElse: () => null,
          );

          if (offerSignal != null && context.mounted) {
            await _handleIncomingCall(
              context,
              fromDeviceId,
              fromDeviceName,
              offerSignal['sdp'] as String,
              offerSignal['type'] as String,
            );
          }
        }
      } catch (e) {
        print('Error polling signals: $e');
      }
    });
  }

  static void _stopSignalPolling() {
    _signalPollTimer?.cancel();
    _signalPollTimer = null;
  }

  static Future<void> _handleIncomingCall(
    BuildContext context,
    String fromDeviceId,
    String fromDeviceName,
    String sdp,
    String type,
  ) async {
    try {
      // Show dialog to accept/reject file transfer request
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Incoming File Transfer'),
          content: Text('$fromDeviceName wants to send you a file'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Accept'),
            ),
          ],
        ),
      );

      if (accepted == true && context.mounted) {
        // Initialize WebRTC service
        final webrtcService = WebRTCService();
        await webrtcService.initialize();

        // Handle the incoming file transfer offer
        await webrtcService.handleIncomingFileTransfer(
          fromDeviceId: fromDeviceId,
          sdp: sdp,
          type: type,
        );

        // Start polling for answer and ICE candidates
        _startAnswerPolling(context, webrtcService, fromDeviceId);

        // Navigate to file send screen
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FileSendScreen(
                remoteDeviceName: fromDeviceName,
                remoteDeviceId: fromDeviceId,
                isIncoming: true,
                webrtcService: webrtcService,
              ),
            ),
          );
        }
      }
    } catch (e) {
      print('Error handling incoming file transfer: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting file transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static void _startAnswerPolling(
    BuildContext context,
    WebRTCService webrtcService,
    String fromDeviceId,
  ) {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        if (_currentDeviceId == null) {
          timer.cancel();
          return;
        }

        final response = await ApiService.getWebRTCSignals(deviceId: _currentDeviceId!);
        final signals = response['signals'] as List?;

        if (signals != null) {
          for (final signal in signals) {
            final signalType = signal['signalType'] as String;
            final signalFromDeviceId = signal['fromDeviceId'] as String;

            if (signalFromDeviceId == fromDeviceId) {
              if (signalType == 'answer') {
                await webrtcService.handleAnswer(
                  sdp: signal['sdp'] as String,
                  type: signal['type'] as String,
                );
              } else if (signalType == 'ice-candidate') {
                await webrtcService.handleIceCandidate(
                  candidate: signal['candidate'] as String,
                  sdpMid: signal['sdpMid'] as String,
                  sdpMLineIndex: signal['sdpMLineIndex'].toString(),
                );
              }
            }
          }
        }
      } catch (e) {
        print('Error polling answer: $e');
        timer.cancel();
      }
    });
  }

  static void stopPolling() {
    _stopSignalPolling();
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.messageId}');
  print('Data: ${message.data}');
}

