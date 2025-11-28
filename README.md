# WebRTC Peer-to-Peer File Transfer Application

This monorepo contains a WebRTC-based peer-to-peer file transfer system with a signaling server and Flutter client application. The system enables direct device-to-device file transfers without routing data through a central server.

## Project Overview

The application consists of two main components:
- **Signaling Server**: A Dart-based HTTP server that facilitates WebRTC signaling and device discovery
- **Client App**: A Flutter mobile application that enables users to discover peers and transfer files directly

## Architecture

### High-Level Flow

```
┌─────────────┐                    ┌──────────────┐                    ┌─────────────┐
│   Device A  │                    │   Signaling │                    │   Device B  │
│  (Flutter)  │                    │    Server   │                    │  (Flutter)  │
└──────┬──────┘                    └──────┬───────┘                    └──────┬──────┘
       │                                   │                                   │
       │ 1. Register Device                │                                   │
       ├──────────────────────────────────>│                                   │
       │                                   │                                   │
       │ 2. List Users                    │                                   │
       ├──────────────────────────────────>│                                   │
       │<──────────────────────────────────┤                                   │
       │                                   │                                   │
       │ 3. Initiate File Transfer         │                                   │
       │    (Create Offer)                 │                                   │
       ├──────────────────────────────────>│                                   │
       │                                   │ 4. Send FCM Data Message          │
       │                                   │    (Offer + SDP in payload)       │
       │                                   ├──────────────────────────────────>│
       │                                   │                                   │
       │                                   │ 5. Show Snackbar                  │
       │                                   │    (Accept/Reject)                │
       │                                   │                                   │
       │                                   │ 6. Send Answer via FCM            │
       │                                   ├──────────────────────────────────>│
       │                                   │                                   │
       │ 7. Receive Answer via FCM         │                                   │
       │<──────────────────────────────────┤                                   │
       │                                   │                                   │
       │ 8. Exchange ICE Candidates        │                                   │
       │    (via FCM Data Messages)        │                                   │
       │<──────────────────────────────────>│<─────────────────────────────────>│
       │                                   │                                   │
       │ 9. Direct P2P Connection          │                                   │
       │<══════════════════════════════════>│                                   │
       │     (WebRTC Data Channel)         │                                   │
       │                                   │                                   │
       │ 10. Transfer File Data           │                                   │
       │<══════════════════════════════════>│                                   │
       │     (Direct, no server)           │                                   │
```

## How It Works

### 1. Device Registration

When a user first opens the app:
1. The app checks if a device ID exists in local storage
2. If not, it generates a unique UUID for the device
3. User enters their name and signs up
4. The app requests an FCM token from Firebase
5. Device information (ID, name, FCM token) is sent to the signaling server via `POST /users`
6. The server stores this information in memory (in a `Map<String, DeviceInfo>`)

**Key Files:**
- `client/lib/screens/sign_up_screen.dart` - Handles user registration UI
- `client/lib/services/api_service.dart` - `registerDevice()` method
- `signaling-server/lib/server.dart` - `POST /users` endpoint

### 2. User Discovery

After registration, the app displays a list of all registered users:
1. App calls `GET /users` to fetch all registered devices
2. Server returns a list of all devices with their IDs, names, and registration timestamps
3. The current user is highlighted in the list
4. Users can refresh the list to see newly registered devices

**Key Files:**
- `client/lib/screens/users_list_screen.dart` - Displays user list
- `signaling-server/lib/server.dart` - `GET /users` endpoint

### 3. Initiating a File Transfer

When User A wants to send a file to User B:

#### Step 3.1: Create WebRTC Peer Connection
1. User A taps the "Send File" button next to User B
2. The app creates a WebRTC `RTCPeerConnection` with STUN servers (Google's public STUN)
3. A data channel is created for file transfer (not media streams)
4. An SDP offer is generated and set as the local description

**Key Files:**
- `client/lib/services/webrtc_service.dart` - `startFileTransfer()` method

#### Step 3.2: Send Offer to Signaling Server
1. The offer (SDP and type) is sent to the server via `POST /webrtc/{targetDeviceId}/signal`
2. Server immediately sends an FCM data-only message to the target device
3. The FCM payload includes the complete SDP offer, eliminating the need for polling

**Key Files:**
- `client/lib/services/api_service.dart` - `sendWebRTCSignal()` method
- `signaling-server/lib/server.dart` - `POST /webrtc/<deviceId>/signal` endpoint and `_sendFcmDataMessage()` method

### 4. Receiving a File Transfer Request

When User B receives a file transfer request:

#### Step 4.1: FCM Data Message
1. The server sends an FCM data-only message (no visible notification) to User B's device
2. The FCM payload contains:
   - `type: "offer"`
   - `fromDeviceId`: ID of the initiator
   - `fromDeviceName`: Name of the initiator
   - `sdp`: The complete SDP offer
   - `sdpType`: The SDP type ("offer")
3. If the app is in the foreground, `FirebaseMessaging.onMessage` fires immediately
4. If the app is in the background, the message is handled when the app comes to foreground

**Key Files:**
- `client/lib/services/fcm_service.dart` - `configureMessageHandlers()` and `_handleFCMDataMessage()` methods
- `signaling-server/lib/server.dart` - `_sendFcmDataMessage()` method

#### Step 4.2: Show Connection Request
1. Upon receiving the FCM data message, a snackbar appears at the bottom of the screen
2. The snackbar displays: "[DeviceName] wants to send you a file"
3. User can tap "Accept" to proceed or dismiss the snackbar to reject
4. The snackbar auto-dismisses after 10 seconds if not interacted with (rejection)

**Key Files:**
- `client/lib/services/fcm_service.dart` - `_showIncomingConnectionSnackbar()` method

#### Step 4.3: Accept and Create Answer
1. If User B taps "Accept", a new `RTCPeerConnection` is created
2. The remote description (offer from FCM) is set
3. An SDP answer is generated and set as the local description
4. The answer is sent back to the server via `POST /webrtc/{fromDeviceId}/signal`
5. The server immediately forwards the answer to User A via FCM data message

**Key Files:**
- `client/lib/services/webrtc_service.dart` - `handleIncomingFileTransfer()` method
- `client/lib/services/fcm_service.dart` - `_acceptIncomingConnection()` method

### 5. ICE Candidate Exchange

Both devices exchange ICE (Interactive Connectivity Establishment) candidates:
1. As each device discovers network paths, it generates ICE candidates
2. Candidates are sent to the server via `POST /webrtc/{targetDeviceId}/signal` with `signalType: "ice-candidate"`
3. The server immediately forwards each candidate to the target device via FCM data message
4. The receiving device processes the FCM message and adds the candidate to the peer connection
5. This continues until a direct connection is established

**Key Files:**
- `client/lib/services/webrtc_service.dart` - `_sendIceCandidate()` and `handleIceCandidate()` methods
- `client/lib/services/fcm_service.dart` - Handles ICE candidate FCM messages

### 6. Direct Peer-to-Peer Connection

Once ICE negotiation completes:
1. The WebRTC connection state changes to `Connected`
2. The data channel opens (`RTCDataChannelOpen`)
3. Both devices can now communicate directly without the server
4. The signaling server is no longer involved in data transfer

**Key Files:**
- `client/lib/services/webrtc_service.dart` - Connection state handlers

### 7. File Transfer via Data Channel

#### Sending a File:
1. User selects a file using the file picker
2. File is read into memory as `Uint8List`
3. Metadata is sent first: `{"type":"file_start","fileName":"...","fileSize":...}`
4. File data is sent in 16KB chunks as binary messages
5. Progress is tracked and displayed to the user
6. Completion message is sent: `{"type":"file_complete"}`

#### Receiving a File:
1. Receiver listens for data channel messages
2. When `file_start` is received, it initializes file reception
3. Binary chunks are accumulated in memory
4. Progress is tracked and displayed
5. When `file_complete` is received, all chunks are combined
6. File is saved to the device's documents directory

**Key Files:**
- `client/lib/services/webrtc_service.dart` - `sendFile()` and `_handleDataChannelMessage()` methods
- `client/lib/screens/call_screen.dart` - UI for file transfer with progress indicators

## Component Breakdown

### Signaling Server (`signaling-server/`)

**Purpose**: Facilitates WebRTC signaling and device discovery. Does NOT handle file data.

**Key Components:**
- **Device Registry**: In-memory storage of registered devices (`Map<String, DeviceInfo>`)
- **Signal Queue**: Stores pending WebRTC signals per device (legacy, used for HTTP polling fallback)
- **FCM Integration**: Sends data-only FCM messages for real-time WebRTC signaling
- **REST API**: HTTP endpoints for device management and signaling

**Endpoints:**
- `POST /users` - Register a device
- `GET /users` - List all registered devices
- `POST /webrtc/<deviceId>/signal` - Send a WebRTC signal (offer/answer/ICE candidate)
- `GET /webrtc/<deviceId>/signals` - Fetch and clear pending signals for a device
- `POST /users/<deviceId>/connect` - Send an FCM connection request

**Key Files:**
- `signaling-server/lib/server.dart` - Main server logic
- `signaling-server/bin/main.dart` - Server entry point with Firebase initialization

### Client App (`client/`)

**Purpose**: Mobile application for discovering peers and transferring files.

**Key Components:**

#### Services:
- **ApiService**: HTTP client for communicating with the signaling server
- **WebRTCService**: Manages WebRTC peer connections and data channels
- **FCMService**: Handles Firebase Cloud Messaging for push notifications

#### Screens:
- **SignUpScreen**: Initial registration and device setup
- **UsersListScreen**: Displays all registered users with ability to initiate transfers
- **FileSendScreen** (CallScreen): UI for file transfer with progress tracking

**Key Files:**
- `client/lib/main.dart` - App entry point, checks registration status
- `client/lib/services/api_service.dart` - API communication
- `client/lib/services/webrtc_service.dart` - WebRTC logic
- `client/lib/services/fcm_service.dart` - FCM notification handling
- `client/lib/screens/*.dart` - UI screens

## Communication Flow Details

### FCM Data-Only Messaging

The system uses FCM data-only messages (no visible notifications) for all WebRTC signaling. This provides real-time, efficient communication without polling:

1. **Offer**: When an offer is created, it's sent to the server which immediately forwards it via FCM data message with the complete SDP offer in the payload
2. **Answer**: When an answer is created, it's sent to the server which immediately forwards it via FCM data message
3. **ICE Candidates**: Each ICE candidate is immediately forwarded via FCM data message as it's generated
4. **No Polling**: All signaling happens in real-time through FCM, eliminating the need for HTTP polling

This approach is more efficient than polling and provides near-instantaneous signaling delivery.

### FCM Message Types

The system uses FCM data-only messages with the following types:

1. **`offer`**: WebRTC offer signal
   - Includes: `fromDeviceId`, `fromDeviceName`, `sdp`, `sdpType`
   - Triggers snackbar with accept button on receiver

2. **`answer`**: WebRTC answer signal
   - Includes: `fromDeviceId`, `fromDeviceName`, `sdp`, `sdpType`
   - Processed automatically by the initiator

3. **`ice-candidate`**: ICE candidate for NAT traversal
   - Includes: `fromDeviceId`, `candidate`, `sdpMid`, `sdpMLineIndex`
   - Processed automatically by both peers

4. **`connection_request`**: General connection request (legacy, not heavily used)
   - Includes: `fromDeviceId`, `fromDeviceName`

All FCM messages are data-only (no visible notifications) to provide silent, real-time signaling.

### Data Channel Protocol

The file transfer uses a simple protocol over the WebRTC data channel:

**Control Messages (JSON text):**
- `{"type":"file_start","fileName":"example.txt","fileSize":12345}`
- `{"type":"file_complete"}`

**Data Messages (Binary):**
- Raw file chunks (16KB each)

The receiver distinguishes between text and binary messages to handle them appropriately.

## Project Structure

```
gp-new/
├── signaling-server/          # Dart HTTP signaling server
│   ├── bin/
│   │   └── main.dart          # Server entry point
│   ├── lib/
│   │   └── server.dart        # Server logic and routes
│   └── pubspec.yaml           # Dependencies
│
└── client/                    # Flutter mobile app
    ├── lib/
    │   ├── main.dart          # App entry point
    │   ├── screens/           # UI screens
    │   │   ├── sign_up_screen.dart
    │   │   ├── users_list_screen.dart
    │   │   └── call_screen.dart
    │   └── services/          # Business logic
    │       ├── api_service.dart
    │       ├── webrtc_service.dart
    │       └── fcm_service.dart
    ├── android/               # Android configuration
    ├── macos/                 # macOS configuration
    └── pubspec.yaml           # Dependencies
```

## Setup Instructions

### Signaling Server

1. **Install Dependencies:**
   ```bash
   cd signaling-server
   dart pub get
   ```

2. **Configure Firebase:**
   - Create a Firebase project
   - Download the service account JSON file
   - Set environment variables:
     ```bash
     export PORT=8080
     export FIREBASE_PROJECT_ID=your-project-id
     export FIREBASE_SERVICE_ACCOUNT_FILE=/path/to/service-account.json
     ```

3. **Run the Server:**
   ```bash
   dart run bin/main.dart
   ```

   The server will start on `0.0.0.0:8080` (or your specified port).

### Client App

1. **Install Dependencies:**
   ```bash
   cd client
   flutter pub get
   ```

2. **Configure Firebase:**
   - Use the same Firebase project as the server
   - Download `google-services.json` for Android
   - Download `GoogleService-Info.plist` for iOS/macOS
   - Place them in:
     - `client/android/app/google-services.json`
     - `client/macos/Runner/GoogleService-Info.plist`

3. **Update Server URL:**
   - Edit `client/lib/services/api_service.dart`
   - Update `baseUrl` to match your signaling server address

4. **Run the App:**
   ```bash
   flutter run
   ```

## Testing with curl

Replace `localhost:8080` with your server address if different.

```bash
# Register a device
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"device-1","deviceName":"Alice","fcmToken":"optional-fcm-token"}'

# List all registered devices
curl http://localhost:8080/users

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

## Key Technologies

- **WebRTC**: Peer-to-peer communication protocol
- **Flutter**: Cross-platform mobile framework
- **Dart**: Programming language for both server and client
- **Firebase Cloud Messaging (FCM)**: Real-time data messaging for WebRTC signaling
- **STUN**: NAT traversal (Google's public STUN server)
- **HTTP/REST**: Device registration and discovery

## Limitations & Future Improvements

### Current Limitations:
1. **In-Memory Storage**: Device registry and signal queues are lost on server restart
2. **No Authentication**: Anyone can register and access the system
3. **No File Size Limits**: Could cause memory issues with very large files
4. **Single STUN Server**: May not work in all network configurations (NAT traversal)
5. **FCM Dependency**: Requires Firebase Cloud Messaging to be configured and working

### Potential Improvements:
1. **Persistent Storage**: Use a database for device registry
2. **Authentication**: User accounts and secure device registration
3. **TURN Servers**: Better NAT traversal for difficult network conditions
4. **File Chunking**: Stream large files instead of loading entirely into memory
5. **Connection Retry**: Automatic reconnection on failure
6. **Multiple File Transfer**: Queue and transfer multiple files
7. **Encryption**: End-to-end encryption for file transfers
8. **WebSocket Fallback**: Use WebSockets as fallback if FCM is unavailable

## Troubleshooting

### Connection Issues:
- Ensure both devices are on networks that allow peer-to-peer connections
- Check firewall settings
- Verify STUN server is accessible
- Consider adding TURN servers for restrictive networks

### FCM Not Working:
- Verify Firebase configuration files are in correct locations
- Check that FCM tokens are being generated and sent to server
- Ensure server has valid Firebase service account credentials
- Check device notification permissions (required for FCM token generation)
- Verify FCM data messages are being received (check logs for "Received FCM data message")
- Ensure the app is handling foreground messages via `FirebaseMessaging.onMessage`

### File Transfer Fails:
- Verify WebRTC connection state is "Connected"
- Check data channel state is "Open"
- Ensure sufficient memory for file size
- Check network stability during transfer
