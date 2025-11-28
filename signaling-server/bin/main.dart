import 'dart:io';
import 'package:signaling_server/server.dart';
import 'package:dotenv/dotenv.dart' as dotenv;
import 'package:shelf/shelf_io.dart' as shelf_io;

void main(List<String> args) async {
  // Load environment variables
  dotenv.load();

  final fcmServerKey = dotenv.env['FCM_SERVER_KEY'];

  final server = SignalingServer(fcmServerKey: fcmServerKey);
  
  final port = int.parse(dotenv.env['PORT'] ?? '8080');
  final host = InternetAddress(dotenv.env['HOST'] ?? 'localhost');

  print('Starting signaling server on ${host.address}:$port');
  if (fcmServerKey == null) {
    print('Warning: FCM_SERVER_KEY not set. FCM notifications will not work.');
  }

  final serverInstance = await shelf_io.serve(
    server.handler,
    host,
    port,
  );

  print('Server running on http://${serverInstance.address.address}:${serverInstance.port}');
  
  // Handle shutdown gracefully
  ProcessSignal.sigint.watch().listen((signal) {
    print('\nShutting down server...');
    serverInstance.close();
    exit(0);
  });
}

