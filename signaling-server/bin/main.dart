import 'dart:io';
import 'package:signaling_server/server.dart';

void main(List<String> args) async {
  // Get port from command-line argument or environment variable
  int port = 8080;
  if (args.isNotEmpty) {
    final portArg = int.tryParse(args[0]);
    if (portArg != null) {
      port = portArg;
    } else {
      print('Invalid port: ${args[0]}. Using default port 8080.');
    }
  } else {
    final envPort = Platform.environment['PORT'];
    if (envPort != null) {
      final portEnv = int.tryParse(envPort);
      if (portEnv != null) {
        port = portEnv;
      }
    }
  }

  final server = SignalingServer(port: port);
  await server.start();
}

