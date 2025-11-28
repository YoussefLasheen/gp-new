import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'fcm_service.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  String? _remoteDeviceId;

  // Callbacks
  Function()? onConnectionReady;
  Function()? onConnectionEnded;
  Function(String)? onError;

  Future<void> initialize() async {
    // No need for media streams for data channel connection
  }

  Future<void> startConnection({
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

      // Create data channel for connection verification
      _dataChannel = await _peerConnection!.createDataChannel(
        'dataChannel',
        RTCDataChannelInit()..ordered = true,
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
          onConnectionReady?.call();
        }
      };

      // Create offer
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Register with FCMService to receive answer and ICE candidates
      FCMService.setActiveWebRTCService(this, targetDeviceId);

      // Send offer via FCM (server will forward it as FCM data message with SDP included)
      await ApiService.sendWebRTCSignal(
        targetDeviceId: targetDeviceId,
        fromDeviceId: fromDeviceId,
        signalType: 'offer',
        sdp: offer.sdp,
        type: offer.type,
      );
    } catch (e) {
      onError?.call('Failed to start connection: $e');
      _cleanup();
    }
  }

  void _setupDataChannel() {
    if (_dataChannel == null) return;

    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        onConnectionReady?.call();
      }
    };

    // Data channel is ready - connection is established
    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      // Connection is established and working
      print('Data channel message received: ${message.text}');
    };
  }

  Future<void> handleIncomingConnection({
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
          onConnectionReady?.call();
        }
      };

      // Set remote description
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );

      // Create answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      // Register with FCMService to receive ICE candidates
      FCMService.setActiveWebRTCService(this, fromDeviceId);

      // Send answer via FCM (server will forward it as FCM data message with SDP included)
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
      onError?.call('Failed to handle incoming connection: $e');
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
      // Send ICE candidate via FCM (server will forward it as FCM data message)
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
    _dataChannel?.close();
    _peerConnection?.close();
    _peerConnection = null;
    _dataChannel = null;
    _remoteDeviceId = null;

    // Unregister from FCMService
    FCMService.clearActiveWebRTCService();
  }

  void dispose() {
    _cleanup();
  }
}
