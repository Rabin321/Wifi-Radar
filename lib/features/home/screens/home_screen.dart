import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../models/signal_network.dart';
import '../widgets/radar_painter.dart';

class WifiRadarHomeScreen extends StatefulWidget {
  const WifiRadarHomeScreen({super.key});

  @override
  State<WifiRadarHomeScreen> createState() => _WifiRadarHomeScreenState();
}

class _WifiRadarHomeScreenState extends State<WifiRadarHomeScreen> {
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _isScanning = false;
  bool _permissionsGranted = false;
  List<SignalNetwork> _networks = const [];
  SignalNetwork? _connectedNetwork;
  String _status = 'Waiting for room scan';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _requestPermissions();
    if (!mounted) return;

    if (_permissionsGranted) {
      await _initializeCamera();
    }

    await _scanWifi();
  }

  Future<void> _requestPermissions() async {
    try {
      final statuses = await [
        Permission.camera,
        Permission.locationWhenInUse,
      ].request();

      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final locationGranted = statuses[Permission.locationWhenInUse]?.isGranted ?? false;

      if (mounted) {
        setState(() {
          _permissionsGranted = cameraGranted && locationGranted;
          if (!_permissionsGranted) {
            _status = 'Enable camera and location to scan the room';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Permission access unavailable');
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _status = 'No camera available');
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _cameraController = controller;
      await controller.initialize();

      if (mounted) {
        setState(() {
          _cameraReady = true;
          _status = 'Camera live';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Camera unavailable');
      }
    }
  }

  Future<void> _scanWifi() async {
    if (!mounted) return;

    setState(() => _isScanning = true);

    try {
      final connectedDetails = await _readConnectedNetworkDetails();
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: false);

      if (canScan == CanStartScan.yes ||
          canScan == CanStartScan.noLocationPermissionRequired) {
        final started = await WiFiScan.instance.startScan();
        if (started) {
          final results = await WiFiScan.instance.getScannedResults();
          if (mounted) {
            final networks = results
                .map(_mapAccessPoint)
                .where((network) => network.ssid.isNotEmpty)
                .toList();

            final connectedNetwork = findConnectedNetwork(
              connectedDetails.ssid,
              connectedDetails.bssid,
              networks,
            );

            setState(() {
              _networks = networks;
              _connectedNetwork = connectedNetwork;
              _status = connectedNetwork == null
                  ? 'Connected network not detected'
                  : 'Connected to ${connectedNetwork.ssid}';
            });
            return;
          }
        }
      }

      if (mounted) {
        setState(() {
          _networks = const [];
          _connectedNetwork = null;
          _status = 'No Wi‑Fi networks detected';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _networks = const [];
          _connectedNetwork = null;
          _status = 'No Wi‑Fi networks detected';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<({String? ssid, String? bssid})> _readConnectedNetworkDetails() async {
    try {
      final info = NetworkInfo();
      final ssid = await info.getWifiName();
      final bssid = await info.getWifiBSSID();
      return (ssid: ssid, bssid: bssid);
    } catch (_) {
      return (ssid: null, bssid: null);
    }
  }

  Future<void> _openWifiSettings() async {
    await openAppSettings();
  }

  SignalNetwork _mapAccessPoint(WiFiAccessPoint accessPoint) {
    final ssid = accessPoint.ssid.trim();
    return SignalNetwork(
      ssid: ssid.isEmpty ? 'Hidden network' : ssid,
      bssid: accessPoint.bssid,
      level: accessPoint.level,
      security: accessPoint.capabilities.isEmpty ? 'Open' : accessPoint.capabilities,
      channel: accessPoint.frequency,
    );
  }

  @override
  Widget build(BuildContext context) {
    final networks = _networks;
    final connectedNetwork = _connectedNetwork;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wi‑Fi Radar',
                            style: TextStyle(
                              fontSize: 28.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            'Scan room',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _scanButton(),
                  ],
                ),
                SizedBox(height: 18.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1F2B),
                    borderRadius: BorderRadius.circular(22.r),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52.w,
                        height: 52.w,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5EE6C5).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(18.r),
                        ),
                        child: Icon(
                          Icons.signal_wifi_4_bar_rounded,
                          color: const Color(0xFF5EE6C5),
                          size: 28.sp,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connected network',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              connectedNetwork?.ssid ?? 'No Wi‑Fi connected',
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              connectedNetwork == null
                                  ? 'Connect to a Wi‑Fi network and re-scan'
                                  : '${connectedNetwork.level} dBm signal strength',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (connectedNetwork == null)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: TextButton.icon(
                      onPressed: _openWifiSettings,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.04),
                        foregroundColor: const Color(0xFF5EE6C5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                      ),
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('Connect Wi‑Fi'),
                    ),
                  ),
                SizedBox(height: 18.h),
                Container(
                  height: 310.h,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28.r),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF081B2B), Color(0xFF0D2435)],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28.r),
                    child: Stack(
                      children: [
                        if (_cameraReady && _cameraController != null)
                          Positioned.fill(child: CameraPreview(_cameraController!))
                        else
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF112C42),
                                    const Color(0xFF0A1727),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.wifi_tethering,
                                  size: 52.sp,
                                  color: Colors.white.withOpacity(0.52),
                                ),
                              ),
                            ),
                          ),
                        Positioned.fill(child: CustomPaint(painter: RadarPainter())),
                        Positioned(
                          left: 16.w,
                          right: 16.w,
                          bottom: 16.h,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _statChip('Active', '${networks.length} APs'),
                              _statChip('Status', _isScanning ? 'Scanning' : 'Ready'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 18.h),
                Row(
                  children: [
                    Text(
                      'Network list',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.signal_cellular_4_bar_rounded,
                      size: 18.sp,
                      color: Colors.greenAccent,
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        _status,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: networks.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (context, index) {
                    final network = networks[index];
                    final signalColor = _signalColor(network.level);

                    return Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1F2B),
                        borderRadius: BorderRadius.circular(20.r),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42.w,
                            height: 42.w,
                            decoration: BoxDecoration(
                              color: signalColor.withOpacity(0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.wifi,
                              size: 22.sp,
                              color: signalColor,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  network.ssid,
                                  style: TextStyle(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  network.security,
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${network.level} dBm',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: signalColor,
                                ),
                              ),
                              SizedBox(height: 6.h),
                              _signalBars(network.level),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scanButton() {
    return TextButton.icon(
      onPressed: _isScanning ? null : _scanWifi,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFF5EE6C5).withOpacity(0.12),
        foregroundColor: const Color(0xFF5EE6C5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.r)),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      ),
      icon: _isScanning
          ? SizedBox(
              width: 14.w,
              height: 14.h,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh_rounded),
      label: Text(_isScanning ? 'Scanning' : 'Scan now'),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10.sp, color: Colors.white.withOpacity(0.7)),
          ),
          SizedBox(height: 2.h),
          Text(
            value,
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _signalBars(int level) {
    final activeBars = switch (level) {
      <= -85 => 1,
      <= -70 => 2,
      <= -60 => 3,
      _ => 4,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        final isActive = index < activeBars;
        return Container(
          width: 5.w,
          height: 10.h + (index * 4).toDouble(),
          margin: EdgeInsets.only(left: index == 0 ? 0 : 2.w),
          decoration: BoxDecoration(
            color: isActive ? _signalColor(level) : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(2.r),
          ),
        );
      }),
    );
  }

  Color _signalColor(int level) {
    if (level >= -60) return const Color(0xFF5EE6C5);
    if (level >= -70) return const Color(0xFF88D97E);
    if (level >= -80) return const Color(0xFFF7C873);
    return const Color(0xFFFF6B6B);
  }
}
