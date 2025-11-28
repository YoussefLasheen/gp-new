import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/webrtc_service.dart';

class FileSendScreen extends StatefulWidget {
  final String remoteDeviceName;
  final String remoteDeviceId;
  final bool isIncoming;
  final WebRTCService webrtcService;

  const FileSendScreen({
    super.key,
    required this.remoteDeviceName,
    required this.remoteDeviceId,
    required this.isIncoming,
    required this.webrtcService,
  });

  @override
  State<FileSendScreen> createState() => _FileSendScreenState();
}

class _FileSendScreenState extends State<FileSendScreen> {
  bool _isConnected = false;
  bool _isSending = false;
  bool _isReceiving = false;
  String? _selectedFileName;
  int? _selectedFileSize;
  int _bytesSent = 0;
  int _bytesReceived = 0;
  int _totalBytesToReceive = 0;
  String? _receivingFileName;
  PlatformFile? _selectedFile;

  @override
  void initState() {
    super.initState();
    _setupWebRTC();
  }

  void _setupWebRTC() {
    widget.webrtcService.onDataChannelReady = () {
      setState(() {
        _isConnected = true;
      });
    };

    widget.webrtcService.onConnectionEnded = () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    };

    widget.webrtcService.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $error'), backgroundColor: Colors.red),
        );
      }
    };

    widget.webrtcService.onFileReceiveStart = (fileName, fileSize) {
      setState(() {
        _isReceiving = true;
        _receivingFileName = fileName;
        _totalBytesToReceive = fileSize;
        _bytesReceived = 0;
      });
    };

    widget.webrtcService.onFileReceiveProgress = (bytesReceived, totalBytes) {
      setState(() {
        _bytesReceived = bytesReceived;
        _totalBytesToReceive = totalBytes;
      });
    };

    widget.webrtcService.onFileReceived = (fileData, fileName) async {
      try {
        // Save the received file
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(fileData);

        setState(() {
          _isReceiving = false;
          _bytesReceived = 0;
          _totalBytesToReceive = 0;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File received: $fileName'),
              backgroundColor: Colors.green,
              action: SnackBarAction(
                label: 'Open',
                onPressed: () {
                  // Could open the file here
                },
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    };

    widget.webrtcService.onFileSendProgress = (bytesSent, totalBytes) {
      setState(() {
        _bytesSent = bytesSent;
      });
    };

    widget.webrtcService.onFileSendComplete = () {
      setState(() {
        _isSending = false;
        _bytesSent = 0;
        _selectedFile = null;
        _selectedFileName = null;
        _selectedFileSize = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    };
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final fileData = await file.readAsBytes();

        setState(() {
          _selectedFile = result.files.single;
          _selectedFileName = result.files.single.name;
          _selectedFileSize = fileData.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendFile() async {
    if (_selectedFile == null || _selectedFile!.path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected yet. Please wait...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final file = File(_selectedFile!.path!);
      final fileData = await file.readAsBytes();

      setState(() {
        _isSending = true;
        _bytesSent = 0;
      });

      await widget.webrtcService.sendFile(fileData, _selectedFileName!);
    } catch (e) {
      setState(() {
        _isSending = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _endConnection() async {
    await widget.webrtcService.endConnection();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection status
              Card(
                color: _isConnected ? Colors.green[700] : Colors.orange[700],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.check_circle : Icons.sync,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isConnected ? 'Connected' : 'Connecting...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // File selection section
              Card(
                color: Colors.grey[800],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Send File',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_selectedFile != null) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.insert_drive_file,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedFileName!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _formatBytes(_selectedFileSize!),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                setState(() {
                                  _selectedFile = null;
                                  _selectedFileName = null;
                                  _selectedFileSize = null;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      ElevatedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.folder_open),
                        label: Text(
                          _selectedFile == null ? 'Select File' : 'Change File',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      if (_isSending) ...[
                        const SizedBox(height: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Sending...',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                Text(
                                  '${((_bytesSent / _selectedFileSize!) * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: _bytesSent / _selectedFileSize!,
                              backgroundColor: Colors.grey[700],
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_formatBytes(_bytesSent)} / ${_formatBytes(_selectedFileSize!)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_selectedFile != null &&
                          !_isSending &&
                          _isConnected) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _sendFile,
                          icon: const Icon(Icons.send),
                          label: const Text('Send File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // File receiving section
              if (_isReceiving)
                Card(
                  color: Colors.grey[800],
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Receiving File',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.download, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _receivingFileName ?? 'Unknown',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _formatBytes(_totalBytesToReceive),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Downloading...',
                              style: TextStyle(color: Colors.white70),
                            ),
                            Text(
                              '${((_bytesReceived / _totalBytesToReceive) * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: _totalBytesToReceive > 0
                              ? _bytesReceived / _totalBytesToReceive
                              : 0,
                          backgroundColor: Colors.grey[700],
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatBytes(_bytesReceived)} / ${_formatBytes(_totalBytesToReceive)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
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
}
