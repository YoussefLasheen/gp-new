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

