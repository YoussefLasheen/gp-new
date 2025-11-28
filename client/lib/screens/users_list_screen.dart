import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/webrtc_service.dart';
import 'call_screen.dart';

class UsersListScreen extends StatefulWidget {
  const UsersListScreen({super.key});

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _currentDeviceId;
  String? _currentDeviceName;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadUsers();
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentDeviceId = prefs.getString('deviceId');
      _currentDeviceName = prefs.getString('deviceName');
    });
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final users = await ApiService.getUsers();
      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendConnectionRequest(
    String targetDeviceId,
    String targetDeviceName,
  ) async {
    if (_currentDeviceId == null || _currentDeviceName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device information not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Initialize WebRTC service
      final webrtcService = WebRTCService();
      await webrtcService.initialize();

      // Start the file transfer connection
      await webrtcService.startFileTransfer(
        targetDeviceId: targetDeviceId,
        fromDeviceId: _currentDeviceId!,
        fromDeviceName: _currentDeviceName!,
      );

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FileSendScreen(
              remoteDeviceName: targetDeviceName,
              remoteDeviceId: targetDeviceId,
              isIncoming: false,
              webrtcService: webrtcService,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting file transfer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pull to refresh',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final deviceId = user['deviceId'] as String;
                  final deviceName = user['deviceName'] as String;
                  final isCurrentUser = deviceId == _currentDeviceId;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isCurrentUser
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                        child: Icon(
                          Icons.person,
                          color: isCurrentUser
                              ? Colors.white
                              : Colors.grey[700],
                        ),
                      ),
                      title: Text(
                        deviceName,
                        style: TextStyle(
                          fontWeight: isCurrentUser
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        deviceId.substring(0, 8) + '...',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: isCurrentUser
                          ? Chip(
                              label: const Text('You'),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                            )
                          : IconButton(
                              icon: const Icon(Icons.file_upload),
                              onPressed: () =>
                                  _sendConnectionRequest(deviceId, deviceName),
                              tooltip: 'Send file',
                            ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
