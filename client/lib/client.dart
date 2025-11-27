import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class P2PClient {
  WebSocketChannel? _channel;
  String? _clientId;
  final Map<String, String> _connectedClients = {};
  final String serverUrl;
  bool _isRunning = false;
  Function(String, String)? _onConnectionRequest;

  P2PClient({this.serverUrl = 'ws://localhost:8080'});

  Future<void> connect(String name) async {
    try {
      final uri = Uri.parse(serverUrl);
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('Connection error: $error');
          _isRunning = false;
        },
        onDone: () {
          print('\nDisconnected from server');
          _isRunning = false;
        },
      );

      // Register with the server
      _channel!.sink.add(jsonEncode({
        'type': 'register',
        'name': name,
      }));

      _isRunning = true;
    } catch (e) {
      print('Failed to connect: $e');
      rethrow;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String;

      switch (type) {
        case 'registered':
          _clientId = data['clientId'] as String;
          print('\n✓ Connected as ${data['name']} (ID: $_clientId)');
          requestClientList();
          break;

        case 'client_list':
          final clients = data['clients'] as List;
          _connectedClients.clear();
          print('\n=== Connected Clients ===');
          if (clients.isEmpty) {
            print('No other clients connected');
          } else {
            for (final client in clients) {
              final clientMap = client as Map<String, dynamic>;
              final id = clientMap['clientId'] as String;
              final name = clientMap['name'] as String;
              if (id != _clientId) {
                _connectedClients[id] = name;
                print('  [$id] $name');
              }
            }
          }
          print('========================\n');
          break;

        case 'client_joined':
          final id = data['clientId'] as String;
          final name = data['name'] as String;
          if (id != _clientId) {
            _connectedClients[id] = name;
            print('\n✓ $name joined (ID: $id)');
          }
          break;

        case 'client_left':
          final id = data['clientId'] as String;
          final name = _connectedClients.remove(id) ?? 'Unknown';
          print('\n✗ $name left (ID: $id)');
          break;

        case 'connection_request':
          final fromId = data['fromId'] as String;
          final fromName = data['fromName'] as String;
          if (_onConnectionRequest != null) {
            _onConnectionRequest!(fromId, fromName);
          } else {
            print('\n📨 Connection request from $fromName (ID: $fromId)');
            print('Use "accept <clientId>" or "reject <clientId>" to respond');
          }
          break;

        case 'connection_response':
          final fromName = data['fromName'] as String;
          final accepted = data['accepted'] as bool;
          if (accepted) {
            print('\n✓ $fromName accepted your connection request');
          } else {
            print('\n✗ $fromName rejected your connection request');
          }
          break;

        case 'message':
          final fromName = data['fromName'] as String;
          final message = data['message'] as String;
          print('\n[$fromName]: $message');
          break;

        case 'error':
          print('\n✗ Error: ${data['message']}');
          break;
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }

  void requestClientList() {
    _channel?.sink.add(jsonEncode({
      'type': 'get_clients',
    }));
  }

  void setOnConnectionRequest(
      Function(String clientId, String clientName) handler) {
    _onConnectionRequest = handler;
  }

  void requestConnection(String targetId) {
    if (!_connectedClients.containsKey(targetId)) {
      print('Error: Client not found');
      return;
    }

    _channel?.sink.add(jsonEncode({
      'type': 'connect_request',
      'targetId': targetId,
    }));
  }

  void respondToConnection(String targetId, bool accepted) {
    _channel?.sink.add(jsonEncode({
      'type': 'connection_response',
      'targetId': targetId,
      'accepted': accepted,
    }));
  }

  void sendMessage(String targetId, String message) {
    if (!_connectedClients.containsKey(targetId)) {
      print('Error: Client not found');
      return;
    }

    _channel?.sink.add(jsonEncode({
      'type': 'message',
      'targetId': targetId,
      'message': message,
    }));
  }

  void disconnect() {
    _channel?.sink.close();
    _isRunning = false;
  }

  bool get isRunning => _isRunning;
  Map<String, String> get connectedClients =>
      Map.unmodifiable(_connectedClients);
}
