# WebRTC Peer-to-Peer Communication Test

This monorepo contains a WebRTC peer-to-peer communication test project with a signaling server and client application.

## Project Structure

- `signaling-server/` - Dart-based signaling server
- `client/` - Flutter client application

## Signaling Server

The signaling server handles device registration and WebRTC signaling.

### Features
- Device registration endpoint
- List all registered devices
- FCM integration for sending connection requests

### Setup

```bash
cd signaling-server
dart pub get
dart run bin/main.dart
```

### Testing with curl

Replace `localhost:8080` if you override the server port or host.

```bash
# Register a device
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"device-1","deviceName":"Alice","fcmToken":"optional-fcm-token"}'

# List all registered devices
curl http://129.151.254.155:9000/users

# Send a WebRTC signal (offer/answer/candidate) to another device
curl -X POST http://localhost:8080/webrtc/device-2/signal \
  -H "Content-Type: application/json" \
  -d '{
        "fromDeviceId":"device-1",
        "signalType":"offer",
        "sdp":"<base64-or-plain-sdp>",
        "type":"offer"
      }'

# Fetch pending signals for a device (clears the queue)
curl http://localhost:8080/webrtc/device-2/signals

# Trigger an FCM connection request (requires FCM env vars + token)
curl -X POST http://localhost:8080/users/device-2/connect \
  -H "Content-Type: application/json" \
  -d '{"fromDeviceId":"device-1","fromDeviceName":"Alice"}'
```

## Client App

The Flutter client application for peer-to-peer communication.

### Features
- User sign up
- Automatic user info sending on app start
- List of all registered users

### Setup

```bash
cd client
flutter pub get
flutter run
```

## Configuration

### FCM Setup

1. Create a Firebase project
2. Download `google-services.json` for Android and `GoogleService-Info.plist` for iOS
3. Place them in the appropriate directories in the client app
4. Add your FCM server key to the signaling server configuration

