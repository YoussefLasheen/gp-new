import 'package:firebase_messaging/firebase_messaging.dart';

class FCMService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

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

  static void configureMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received message: ${message.messageId}');
      print('Notification: ${message.notification?.title}');
      print('Data: ${message.data}');
      
      // Handle connection request
      if (message.data['type'] == 'connection_request') {
        // You can show a dialog or navigate to a connection screen here
        print('Connection request from: ${message.data['fromDeviceName']}');
      }
    });

    // Handle background messages (when app is terminated)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notification taps
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification opened app: ${message.messageId}');
      if (message.data['type'] == 'connection_request') {
        // Navigate to connection screen
        print('Opening connection request from: ${message.data['fromDeviceName']}');
      }
    });
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.messageId}');
}

