import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MBluetoothService()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DataDisplayScreen(),
      ),
    );
  }
}

class MBluetoothService with ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _characteristic;
  bool _isConnecting = false;
  String _connectionStatus = 'Disconnected';
  List<BluetoothDevice> _discoveredDevices = [];
  bool _isScanning = false;

  // Sensor Data
  String _fuelLevel = '80';
  String _humidity = '63';
  String _temperature = '25';
  String _rainStatus = 'No rain';
  String _distance = '160';
  String _rainValue = '0';

  // Getters
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isConnected => _connectedDevice != null;
  bool get isConnecting => _isConnecting;
  bool get isScanning => _isScanning;
  String get connectionStatus => _connectionStatus;
  List<BluetoothDevice> get discoveredDevices => _discoveredDevices;
  String get fuelLevel => _fuelLevel;
  String get humidity => _humidity;
  String get temperature => _temperature;
  String get rainStatus => _rainStatus;
  String get distance => _distance;
  String get rainValue => _rainValue;

  MBluetoothService() {
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    // Listen for state changes
    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        startDiscovery();
      } else {
        _updateStatus('Bluetooth Off');
      }
    });

    if (!await FlutterBluePlus.isAvailable) {
      _updateStatus('Bluetooth Not Available');
      return;
    }

    if (!await FlutterBluePlus.isOn) {
      _updateStatus('Bluetooth Off');
      return;
    }

    await startDiscovery();
  }

  Future<void> startDiscovery() async {
    if (_isScanning) return;

    _discoveredDevices = [];

    // Request necessary permissions
    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();
    final locationStatus = await Permission.location.request();

    if (!scanStatus.isGranted ||
        !connectStatus.isGranted ||
        !locationStatus.isGranted) {
      _updateStatus('Permission Denied');
      return;
    }

    _isScanning = true;
    _discoveredDevices = [];
    _updateStatus('Scanning...');
    notifyListeners();

    // Start scanning
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final device = result.device;
        if (!_discoveredDevices.any((d) => d.id == device.id)) {
          _discoveredDevices.add(device);
          notifyListeners();
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      await Future.delayed(const Duration(seconds: 7));
    } catch (e) {
      _updateStatus('Scan Failed: $e');
    } finally {
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
      _isScanning = false;
      _updateStatus(
        _discoveredDevices.isEmpty ? 'No Devices Found' : 'Scan Complete',
      );
      notifyListeners();
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (_isConnecting || _connectedDevice == device) return;

    _isConnecting = true;
    _updateStatus('Connecting...');
    notifyListeners();

    try {
      await _disconnect();
      await device.connect(autoConnect: false);
      _connectedDevice = device;

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.notify) {
            _characteristic = char;
            break;
          }
        }
      }

      if (_characteristic == null) throw Exception('No characteristic found');

      await _characteristic!.setNotifyValue(true);
      _characteristic!.onValueReceived.listen(_handleData);
      _updateStatus('Connected');
    } catch (e) {
      _updateStatus('Connection Failed: $e');
      await _disconnect();
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  void _handleData(List<int> data) {
    try {
      final values = String.fromCharCodes(data).split(',');
      if (values.length == 6) {
        _fuelLevel = values[0];
        _humidity = values[1];
        _temperature = values[2];
        _rainStatus = values[3] == '1' ? 'RAINING!' : 'No rain';
        _distance = values[4];
        _rainValue = values[5];
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('Data parse error: $e');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _characteristic = null;
  }

  void _updateStatus(String status) {
    _connectionStatus = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
}

class DataDisplayScreen extends StatelessWidget {
  const DataDisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bluetooth = context.watch<MBluetoothService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensor Data'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SensorCard(
              color: Colors.green,
              icon: Icons.local_gas_station,
              title: 'Fuel Level',
              value: '${bluetooth.fuelLevel}%',
              progress: double.tryParse(bluetooth.fuelLevel) ?? 0,
            ),
            _SensorCard(
              color: Colors.redAccent,
              icon: Icons.thermostat,
              title: 'Temperature',
              value: '${bluetooth.temperature}°C',
            ),
            _SensorCard(
              color: Colors.blueAccent,
              icon: Icons.water_drop,
              title: 'Humidity',
              value: '${bluetooth.humidity}%',
            ),
            _SensorCard(
              color: Colors.lightBlueAccent,
              icon: Icons.water,
              title: 'Rain Status',
              value: bluetooth.rainStatus,
              isRaining: bluetooth.rainStatus == 'RAINING!',
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final double progress;
  final bool isRaining;
  final Color color;

  const _SensorCard(
      {required this.icon,
      required this.title,
      required this.value,
      this.progress = 0,
      this.isRaining = false,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: color)),
                    Text(value,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ],
                ),
              ],
            ),
            if (progress > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress / 100,
                minHeight: 12,
                backgroundColor: Colors.grey[200],
                color: progress >= 90 ? Colors.red : Colors.green,
              ),
            ],
            if (isRaining) ...[
              const SizedBox(height: 8),
              const Text('Rain detected!', style: TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

class BluetoothDeviceListScreen extends StatelessWidget {
  const BluetoothDeviceListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bt = context.watch<MBluetoothService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Devices'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: Colors.green,
            ),
            onPressed: bt.startDiscovery,
          ),
        ],
      ),
      body: bt.isScanning
          ? const Center(
              child: CircularProgressIndicator(
              color: Colors.green,
            ))
          : bt.discoveredDevices.isEmpty
              ? Center(child: Text(bt.connectionStatus))
              : ListView(
                  children: bt.discoveredDevices.map((d) {
                    final name = d.name.isNotEmpty ? d.name : d.id.str;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text(d.id.id),
                      leading: const Icon(
                        Icons.bluetooth,
                        color: Colors.blue,
                      ),
                      onTap: () async {
                        if (d != null) {
                          bool go = false;
                          try {
                            showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (context) => const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.green,
                                      ),
                                    ));
                            //await d.connect();
                            await Future.delayed(Duration(seconds: 4));
                            go = true;
                          } catch (e) {
                            print(e);
                          }
                          Navigator.of(context).pop();

                          if (go) {
                            Navigator.of(context).push(CupertinoPageRoute(
                                builder: (context) => DataDisplayScreen()));
                          }
                        }
                      },
                    );
                  }).toList(),
                ),
    );
  }
}
