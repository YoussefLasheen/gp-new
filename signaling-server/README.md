# Signaling Server

Dart-based signaling server for WebRTC peer-to-peer communication.

## Setup

1. Install dependencies:
```bash
dart pub get
```

2. Run the server using `--dart-define` values (recommended):
```bash
dart run \
  -DHOST=0.0.0.0 \
  -DPORT=8080 \
  -DFIREBASE_PROJECT_ID=your_project_id \
  -DFIREBASE_SERVICE_ACCOUNT_FILE=/absolute/path/to/serviceAccount.json \
  bin/main.dart
```

   - **HOST**: Interface to bind to (defaults to `localhost` if not provided).
   - **PORT**: Port number (defaults to `8080` if not provided).
   - **FIREBASE_PROJECT_ID**: Firebase project ID used by the Admin SDK.
   - **FIREBASE_SERVICE_ACCOUNT_FILE**: Absolute path to a Firebase service account JSON file.

You can also set these at build/run time with any process manager or container orchestration tool that supports passing `-D` flags to `dart run`.

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

