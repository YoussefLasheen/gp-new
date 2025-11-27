# P2P Communication Test Project

This monorepo contains a peer-to-peer communication test system with a signaling server and CLI client.

## Structure

- `signaling-server/` - WebSocket signaling server in Dart
- `client/` - CLI client application for connecting and messaging

## Getting Started

### Prerequisites

- Dart SDK (>=3.0.0)

### Running the Signaling Server

```bash
cd signaling-server
dart pub get
dart run bin/main.dart
```

The server will start on `ws://localhost:8080` by default.

You can specify a custom port:
```bash
dart run bin/main.dart 3000
```

Or use an environment variable:
```bash
PORT=3000 dart run bin/main.dart
```

### Running the Client

In a separate terminal:

```bash
cd client
dart pub get
dart run bin/main.dart
```

The client will connect to `ws://localhost:8080` by default.

You can specify a custom server URL:
```bash
dart run bin/main.dart ws://localhost:3000
```

Or use an environment variable:
```bash
SERVER_URL=ws://localhost:3000 dart run bin/main.dart
```

You can run multiple client instances to test peer-to-peer communication.

## Client Commands

- `list` - Show all connected clients
- `connect <clientId>` - Request connection to a specific client
- `msg <clientId> <message>` - Send a message to a connected client
- `quit` - Disconnect and exit

## How It Works

1. Clients connect to the signaling server via WebSocket
2. Clients register with a name and receive a unique client ID
3. Clients can see a list of all connected clients
4. Clients can request connections to other clients
5. Clients can send messages to connected clients through the signaling server

