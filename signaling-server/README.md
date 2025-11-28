# Signaling Server

Dart-based signaling server for WebRTC peer-to-peer communication.

## Setup

1. Install dependencies:
```bash
dart pub get
```

2. Create a `.env` file from `.env.example`:
```bash
cp .env.example .env
```

3. Edit `.env` and add your FCM server key:
```
PORT=8080
HOST=localhost
FCM_SERVER_KEY=your_fcm_server_key_here
```

4. Run the server:
```bash
dart run bin/main.dart
```

## API Endpoints

### POST /users
Register a new device.

Request body:
```json
{
  "deviceId": "string",
  "deviceName": "string",
  "fcmToken": "string (optional)"
}
```

### GET /users
Get list of all registered devices.

Response:
```json
{
  "success": true,
  "devices": [
    {
      "deviceId": "string",
      "deviceName": "string",
      "registeredAt": "ISO8601 datetime"
    }
  ],
  "count": 0
}
```

### POST /users/:deviceId/connect
Send a connection request to a device via FCM.

Request body:
```json
{
  "fromDeviceId": "string",
  "fromDeviceName": "string"
}
```

