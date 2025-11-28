import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  WebSocketChannel? _signalingChannel;
  String? _remoteDeviceId;

  // Callbacks
  Function()? onDataChannelReady;
  Function()? onConnectionEnded;
  Function(String)? onError;
  Function(String fileName, int fileSize)? onFileReceiveStart;
  Function(int bytesReceived, int totalBytes)? onFileReceiveProgress;
  Function(Uint8List fileData, String fileName)? onFileReceived;
  Function(int bytesSent, int totalBytes)? onFileSendProgress;
  Function()? onFileSendComplete;

  Future<void> initialize() async {
    // No need for media streams for file transfer
  }

  Future<void> startFileTransfer({
    required String targetDeviceId,
    required String fromDeviceId,
    required String fromDeviceName,
  }) async {
    try {
      _remoteDeviceId = targetDeviceId;

      // Create peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      // Create data channel
      _dataChannel = await _peerConnection!.createDataChannel(
        'fileTransfer',
        RTCDataChannelInit()
          ..ordered = true
          ..maxRetransmits = 3,
      );

      _setupDataChannel();

      // Set up event handlers
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _sendIceCandidate(candidate, fromDeviceId);
      };

      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        _dataChannel = channel;
        _setupDataChannel();
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _cleanup();
          onConnectionEnded?.call();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          onDataChannelReady?.call();
        }
      };

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer to server
      await ApiService.sendWebRTCSignal(
        targetDeviceId: targetDeviceId,
        fromDeviceId: fromDeviceId,
        signalType: 'offer',
        sdp: offer.sdp,
        type: offer.type,
      );

      // Start polling for answer and ICE candidates
      _startAnswerPolling(fromDeviceId);
    } catch (e) {
      onError?.call('Failed to start file transfer: $e');
      _cleanup();
    }
  }

  void _setupDataChannel() {
    if (_dataChannel == null) return;

    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        onDataChannelReady?.call();
      }
    };

    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      _handleDataChannelMessage(message);
    };
  }

  Future<void> sendFile(Uint8List fileData, String fileName) async {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      onError?.call('Data channel not ready');
      return;
    }

    try {
      final totalBytes = fileData.length;
      const chunkSize = 16 * 1024; // 16KB chunks
      int offset = 0;

      // Send file metadata first
      final metadata =
          '{"type":"file_start","fileName":"$fileName","fileSize":$totalBytes}';
      _dataChannel!.send(RTCDataChannelMessage(metadata));

      // Send file in chunks
      while (offset < totalBytes) {
        final end = (offset + chunkSize < totalBytes)
            ? offset + chunkSize
            : totalBytes;
        final chunk = fileData.sublist(offset, end);

        _dataChannel!.send(RTCDataChannelMessage.fromBinary(chunk));

        offset = end;

        // Report progress
        onFileSendProgress?.call(offset, totalBytes);

        // Small delay to prevent overwhelming the channel
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Send completion message
      _dataChannel!.send(RTCDataChannelMessage('{"type":"file_complete"}'));
      onFileSendComplete?.call();
    } catch (e) {
      onError?.call('Failed to send file: $e');
    }
  }

  Timer? _answerPollTimer;
  String? _currentFileName;
  int? _currentFileSize;
  int _currentFileBytesReceived = 0;
  final List<Uint8List> _fileChunks = [];

  void _handleDataChannelMessage(RTCDataChannelMessage message) {
    try {
      // Check for binary data first (file chunks)
      final binary = message.binary;
      if (binary != null) {
        _fileChunks.add(binary);
        _currentFileBytesReceived += binary.length;

        if (_currentFileSize != null) {
          onFileReceiveProgress?.call(
            _currentFileBytesReceived,
            _currentFileSize!,
          );
        }
        return;
      }

      // Handle text messages (control messages)
      final text = message.text;
      if (text.isNotEmpty && text.startsWith('{')) {
        // Parse JSON control message
        if (text.contains('"type":"file_start"')) {
          // Extract metadata (simplified - use proper JSON parsing in production)
          final nameMatch = RegExp(r'"fileName":"([^"]+)"').firstMatch(text);
          final sizeMatch = RegExp(r'"fileSize":(\d+)').firstMatch(text);

          if (nameMatch != null && sizeMatch != null) {
            _currentFileName = nameMatch.group(1);
            _currentFileSize = int.parse(sizeMatch.group(1)!);
            _currentFileBytesReceived = 0;
            _fileChunks.clear();

            onFileReceiveStart?.call(_currentFileName!, _currentFileSize!);
          }
        } else if (text.contains('"type":"file_complete"')) {
          // Combine all chunks
          final totalSize = _fileChunks.fold<int>(
            0,
            (sum, chunk) => sum + chunk.length,
          );
          final fileData = Uint8List(totalSize);
          int offset = 0;
          for (final chunk in _fileChunks) {
            fileData.setRange(offset, offset + chunk.length, chunk);
            offset += chunk.length;
          }

          onFileReceived?.call(fileData, _currentFileName ?? 'unknown');

          // Reset
          _currentFileName = null;
          _currentFileSize = null;
          _currentFileBytesReceived = 0;
          _fileChunks.clear();
        }
      }
    } catch (e) {
      print('Error handling data channel message: $e');
      onError?.call('Error receiving file: $e');
    }
  }

  void _startAnswerPolling(String fromDeviceId) {
    _answerPollTimer?.cancel();
    _answerPollTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      try {
        if (_remoteDeviceId == null) {
          timer.cancel();
          return;
        }

        final response = await ApiService.getWebRTCSignals(
          deviceId: fromDeviceId,
        );
        final signals = response['signals'] as List?;

        if (signals != null) {
          for (final signal in signals) {
            final signalType = signal['signalType'] as String;
            final signalFromDeviceId = signal['fromDeviceId'] as String;

            if (signalFromDeviceId == _remoteDeviceId) {
              if (signalType == 'answer') {
                await handleAnswer(
                  sdp: signal['sdp'] as String,
                  type: signal['type'] as String,
                );
                timer.cancel();
              } else if (signalType == 'ice-candidate') {
                await handleIceCandidate(
                  candidate: signal['candidate'] as String,
                  sdpMid: signal['sdpMid'] as String,
                  sdpMLineIndex: signal['sdpMLineIndex'].toString(),
                );
              }
            }
          }
        }
      } catch (e) {
        print('Error polling answer: $e');
      }
    });
  }

  Future<void> handleIncomingFileTransfer({
    required String fromDeviceId,
    required String sdp,
    required String type,
  }) async {
    try {
      _remoteDeviceId = fromDeviceId;

      // Create peer connection
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });

      // Set up event handlers
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) async {
        final prefs = await SharedPreferences.getInstance();
        final myDeviceId = prefs.getString('deviceId');
        if (myDeviceId != null) {
          _sendIceCandidate(candidate, myDeviceId);
        }
      };

      _peerConnection!.onDataChannel = (RTCDataChannel channel) {
        _dataChannel = channel;
        _setupDataChannel();
      };

      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          _cleanup();
          onConnectionEnded?.call();
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          onDataChannelReady?.call();
        }
      };

      // Set remote description
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );

      // Create answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Send answer to server
      final prefs = await SharedPreferences.getInstance();
      final myDeviceId = prefs.getString('deviceId');
      if (myDeviceId != null) {
        await ApiService.sendWebRTCSignal(
          targetDeviceId: fromDeviceId,
          fromDeviceId: myDeviceId,
          signalType: 'answer',
          sdp: answer.sdp,
          type: answer.type,
        );
      }
    } catch (e) {
      onError?.call('Failed to handle incoming file transfer: $e');
      _cleanup();
    }
  }

  Future<void> handleAnswer({required String sdp, required String type}) async {
    try {
      if (_peerConnection == null) return;

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );
    } catch (e) {
      onError?.call('Failed to handle answer: $e');
    }
  }

  Future<void> handleIceCandidate({
    required String candidate,
    required String sdpMid,
    required String sdpMLineIndex,
  }) async {
    try {
      if (_peerConnection == null) return;

      await _peerConnection!.addCandidate(
        RTCIceCandidate(candidate, sdpMid, int.tryParse(sdpMLineIndex) ?? 0),
      );
    } catch (e) {
      onError?.call('Failed to handle ICE candidate: $e');
    }
  }

  Future<void> _sendIceCandidate(
    RTCIceCandidate candidate,
    String fromDeviceId,
  ) async {
    if (_remoteDeviceId == null) return;

    try {
      await ApiService.sendWebRTCSignal(
        targetDeviceId: _remoteDeviceId!,
        fromDeviceId: fromDeviceId,
        signalType: 'ice-candidate',
        candidate: candidate.candidate,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex.toString(),
      );
    } catch (e) {
      print('Error sending ICE candidate: $e');
    }
  }

  Future<void> endConnection() async {
    _cleanup();
    onConnectionEnded?.call();
  }

  void _cleanup() {
    _answerPollTimer?.cancel();
    _answerPollTimer = null;
    _dataChannel?.close();
    _peerConnection?.close();
    _signalingChannel?.sink.close();
    _peerConnection = null;
    _dataChannel = null;
    _signalingChannel = null;
    _remoteDeviceId = null;
    _fileChunks.clear();
    _currentFileName = null;
    _currentFileSize = null;
    _currentFileBytesReceived = 0;
  }

  void dispose() {
    _cleanup();
  }
}
