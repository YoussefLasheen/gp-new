import 'dart:io';
import 'package:client/client.dart';

void main(List<String> args) async {
  print('=== P2P Communication Client ===\n');

  // Get server URL from command-line argument or environment variable
  String serverUrl = 'ws://localhost:8080';
  if (args.isNotEmpty) {
    serverUrl = args[0];
  } else {
    final envUrl = Platform.environment['SERVER_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      serverUrl = envUrl;
    }
  }

  stdout.write('Enter your name: ');
  final name = stdin.readLineSync()?.trim() ?? 'Anonymous';

  final client = P2PClient(serverUrl: serverUrl);

  try {
    await client.connect(name);

    // Set up connection request handler
    client.setOnConnectionRequest((clientId, clientName) {
      print('\n📨 Connection request from $clientName (ID: $clientId)');
      print('Use "accept $clientId" or "reject $clientId" to respond');
    });

    print('\nCommands:');
    print('  list - Show connected clients');
    print('  connect <clientId> - Request connection to a client');
    print('  accept <clientId> - Accept a connection request');
    print('  reject <clientId> - Reject a connection request');
    print('  msg <clientId> <message> - Send a message to a client');
    print('  quit - Disconnect and exit\n');

    while (client.isRunning) {
      stdout.write('> ');
      final input = stdin.readLineSync()?.trim() ?? '';

      if (input.isEmpty) continue;

      final parts = input.split(' ');
      final command = parts[0].toLowerCase();

      switch (command) {
        case 'list':
          client.requestClientList();
          await Future.delayed(Duration(milliseconds: 100));
          break;

        case 'connect':
          if (parts.length < 2) {
            print('Usage: connect <clientId>');
            break;
          }
          client.requestConnection(parts[1]);
          break;

        case 'accept':
          if (parts.length < 2) {
            print('Usage: accept <clientId>');
            break;
          }
          client.respondToConnection(parts[1], true);
          break;

        case 'reject':
          if (parts.length < 2) {
            print('Usage: reject <clientId>');
            break;
          }
          client.respondToConnection(parts[1], false);
          break;

        case 'msg':
          if (parts.length < 3) {
            print('Usage: msg <clientId> <message>');
            break;
          }
          final targetId = parts[1];
          final message = parts.sublist(2).join(' ');
          client.sendMessage(targetId, message);
          break;

        case 'quit':
        case 'exit':
          client.disconnect();
          break;

        default:
          print('Unknown command: $command');
          print('Available commands: list, connect, accept, reject, msg, quit');
      }
    }
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}
