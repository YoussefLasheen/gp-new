import 'package:signaling_server/server.dart';

void main() async {
  final server = SignalingServer(port: 8080);
  await server.start();
}

