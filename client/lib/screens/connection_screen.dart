import 'package:flutter/material.dart';
import '../services/webrtc_service.dart';

class ConnectionScreen extends StatefulWidget {
  final String remoteDeviceName;
  final String remoteDeviceId;
  final bool isIncoming;
  final WebRTCService webrtcService;

  const ConnectionScreen({
    super.key,
    required this.remoteDeviceName,
    required this.remoteDeviceId,
    required this.isIncoming,
    required this.webrtcService,
  });

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  bool _isConnected = false;
  String _connectionStatus = 'Connecting...';

  @override
  void initState() {
    super.initState();
    _setupWebRTC();
  }

  void _setupWebRTC() {
    widget.webrtcService.onConnectionReady = () {
      setState(() {
        _isConnected = true;
        _connectionStatus = 'Connected';
      });
    };

    widget.webrtcService.onConnectionEnded = () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    };

    widget.webrtcService.onError = (error) {
      if (mounted) {
        setState(() {
          _connectionStatus = 'Error: $error';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    };
  }

  Future<void> _endConnection() async {
    await widget.webrtcService.endConnection();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: Text(widget.remoteDeviceName),
        backgroundColor: Colors.grey[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _endConnection,
            tooltip: 'Close',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection status card
              Card(
                color: _isConnected ? Colors.green[700] : Colors.orange[700],
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(
                        _isConnected ? Icons.check_circle : Icons.sync,
                        color: Colors.white,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _connectionStatus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_isConnected) ...[
                        const SizedBox(height: 16),
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Connection info
              Card(
                color: Colors.grey[800],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Connection Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow('Device', widget.remoteDeviceName),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Device ID',
                        widget.remoteDeviceId.substring(0, 8) + '...',
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'Type',
                        widget.isIncoming ? 'Incoming' : 'Outgoing',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

