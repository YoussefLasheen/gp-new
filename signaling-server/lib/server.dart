import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingServer {
  final Map<String, WebSocketChannel> _clients = {};
  final Map<String, String> _clientNames = {};
  final int port;

  SignalingServer({this.port = 8080});

  Future<void> start() async {
    final handler = webSocketHandler((WebSocketChannel channel) {
      String? clientId;
      
      channel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            final type = data['type'] as String;

            switch (type) {
              case 'register':
                clientId = data['clientId'] as String? ?? _generateClientId();
                final clientName = data['name'] as String? ?? clientId!;
                final id = clientId!;
                _clients[id] = channel;
                _clientNames[id] = clientName;
                
                // Send confirmation
                channel.sink.add(jsonEncode({
                  'type': 'registered',
                  'clientId': id,
                  'name': clientName,
                }));

                // Notify all other clients
                _broadcastToOthers(id, {
                  'type': 'client_joined',
                  'clientId': id,
                  'name': clientName,
                });

                // Send list of existing clients
                _sendClientList(channel);
                break;

              case 'get_clients':
                _sendClientList(channel);
                break;

              case 'connect_request':
                final targetId = data['targetId'] as String;
                if (_clients.containsKey(targetId)) {
                  _clients[targetId]?.sink.add(jsonEncode({
                    'type': 'connection_request',
                    'fromId': clientId,
                    'fromName': _clientNames[clientId],
                  }));
                } else {
                  channel.sink.add(jsonEncode({
                    'type': 'error',
                    'message': 'Client not found',
                  }));
                }
                break;

              case 'connection_response':
                final targetId = data['targetId'] as String;
                final accepted = data['accepted'] as bool;
                if (_clients.containsKey(targetId)) {
                  _clients[targetId]?.sink.add(jsonEncode({
                    'type': 'connection_response',
                    'fromId': clientId,
                    'fromName': _clientNames[clientId],
                    'accepted': accepted,
                  }));
                }
                break;

              case 'message':
                final targetId = data['targetId'] as String;
                final message = data['message'] as String;
                if (_clients.containsKey(targetId)) {
                  _clients[targetId]?.sink.add(jsonEncode({
                    'type': 'message',
                    'fromId': clientId,
                    'fromName': _clientNames[clientId],
                    'message': message,
                  }));
                } else {
                  channel.sink.add(jsonEncode({
                    'type': 'error',
                    'message': 'Client not found',
                  }));
                }
                break;
            }
          } catch (e) {
            channel.sink.add(jsonEncode({
              'type': 'error',
              'message': 'Invalid message format: $e',
            }));
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          if (clientId != null) {
            _handleClientDisconnect(clientId!);
          }
        },
      );
    });

    final pipeline = const Pipeline().addMiddleware(logRequests()).addHandler(handler);

    await shelf_io.serve(
      pipeline,
      InternetAddress.anyIPv4,
      port,
    );

    print('Signaling server running on ws://localhost:$port');
  }

  void _sendClientList(WebSocketChannel channel) {
    final clients = _clients.keys.map((id) => {
      'clientId': id,
      'name': _clientNames[id] ?? id,
    }).toList();

    channel.sink.add(jsonEncode({
      'type': 'client_list',
      'clients': clients,
    }));
  }

  void _broadcastToOthers(String excludeId, Map<String, dynamic> message) {
    _clients.forEach((id, channel) {
      if (id != excludeId) {
        channel.sink.add(jsonEncode(message));
      }
    });
  }

  void _handleClientDisconnect(String clientId) {
    _clients.remove(clientId);
    _clientNames.remove(clientId);
    
    _broadcastToOthers(clientId, {
      'type': 'client_left',
      'clientId': clientId,
    });
  }

  String _generateClientId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

