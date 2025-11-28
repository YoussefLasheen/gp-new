import 'dart:io';

import 'package:dart_firebase_admin/dart_firebase_admin.dart';
import 'package:dart_firebase_admin/messaging.dart';
import 'package:signaling_server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

const _defineHost = String.fromEnvironment('HOST');
const _definePort = String.fromEnvironment('PORT');
const _defineFirebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _defineServiceAccountFile =
    String.fromEnvironment('FIREBASE_SERVICE_ACCOUNT_FILE');

void main(List<String> args) async {
  if (_defineHost.isEmpty ||
      _definePort.isEmpty ||
      _defineFirebaseProjectId.isEmpty ||
      _defineServiceAccountFile.isEmpty) {
    stdout.writeln(
      'Warning: Required environment variables not configured. FCM notifications are disabled.',
    );
    return;
  }
  if (!File(_defineServiceAccountFile).existsSync()) {
    stdout.writeln(
      'Warning: Firebase credentials file not found at $_defineServiceAccountFile. FCM notifications are disabled.',
    );
    return;
  }
  final host = _defineHost;
  final portEnv = _definePort;
  final port = int.tryParse(portEnv) ?? 8080;
  final resolvedHost = InternetAddress(host);

  final firebaseProjectId = _defineFirebaseProjectId;
  final firebaseCredentialsPath = _defineServiceAccountFile;

  final credential =
      Credential.fromServiceAccount(File(firebaseCredentialsPath));
  final firebaseApp = FirebaseAdminApp.initializeApp(
    firebaseProjectId,
    credential,
  );
  final messaging = Messaging(firebaseApp);

  final server = SignalingServer(messaging: messaging);

  stdout.writeln(
    'Starting signaling server on ${resolvedHost.address}:$port',
  );

  final serverInstance = await shelf_io.serve(
    server.handler,
    resolvedHost,
    port,
  );

  stdout.writeln(
    'Server running on http://${serverInstance.address.address}:${serverInstance.port}',
  );

  var isShuttingDown = false;
  Future<void> shutdown(int exitCode) async {
    if (isShuttingDown) {
      return;
    }
    isShuttingDown = true;
    stdout.writeln('\nShutting down server...');
    await serverInstance.close();
    await firebaseApp.close();
    exit(exitCode);
  }

  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) {
      shutdown(0);
    });
  }
}
