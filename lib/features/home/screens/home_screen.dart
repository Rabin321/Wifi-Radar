import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:http/http.dart' as http;
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
  bool _isTestingSpeed = false;
  bool _permissionsGranted = false;
  String _status = 'Checking connection';
  double _downloadSpeedMbps = 0;
  SignalNetwork? _connectedNetwork;

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
      final permissions = <Permission>[
        Permission.camera,
        Permission.locationWhenInUse,
        if (Platform.isAndroid) Permission.nearbyWifiDevices,
      ];

      final statuses = await permissions.request();

      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final locationGranted = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
      final wifiScanGranted =
          statuses[Permission.nearbyWifiDevices]?.isGranted ?? (Platform.isAndroid ? false : true);

      if (mounted) {
        setState(() {
          _permissionsGranted = cameraGranted && locationGranted && wifiScanGranted;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {});
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
        setState(() {});
      }
    }
  }

  Future<void> _scanWifi() async {
    if (!mounted) return;

    if (mounted) {
      setState(() => _isScanning = true);
    }

    try {
      final connectedDetails = await _readConnectedNetworkDetails();
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);

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
            ) ??
                _fallbackConnectedNetwork(connectedDetails.ssid, connectedDetails.bssid);

            setState(() {
              _connectedNetwork = connectedNetwork;
              _status = connectedNetwork == null
                  ? 'Wi‑Fi connection unavailable'
                  : 'Connected to ${connectedNetwork.ssid}';
            });
            return;
          }
        }
      }

      if (mounted) {
        final fallbackNetwork = _fallbackConnectedNetwork(
          connectedDetails.ssid,
          connectedDetails.bssid,
        );

        setState(() {
          _connectedNetwork = fallbackNetwork;
          _status = fallbackNetwork == null
              ? 'Wi‑Fi scan is not available right now'
              : 'Connected to ${fallbackNetwork.ssid}';
        });
      }
    } catch (_) {
      if (mounted) {
        final connectedDetails = await _readConnectedNetworkDetails();
        final fallbackNetwork = _fallbackConnectedNetwork(
          connectedDetails.ssid,
          connectedDetails.bssid,
        );

        setState(() {
          _connectedNetwork = fallbackNetwork;
          _status = fallbackNetwork == null
              ? 'Wi‑Fi scan is not available right now'
              : 'Connected to ${fallbackNetwork.ssid}';
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

  SignalNetwork? _fallbackConnectedNetwork(String? ssid, String? bssid) {
    final currentSsid = ssid?.trim();
    if (currentSsid == null || currentSsid.isEmpty) return null;

    return SignalNetwork(
      ssid: currentSsid,
      bssid: bssid?.trim() ?? 'Connected Wi‑Fi',
      level: -58,
      security: 'Connected',
      channel: 0,
    );
  }

  Future<void> _openWifiSettings() async {
    await openAppSettings();
  }

  SignalNetwork _mapAccessPoint(WiFiAccessPoint accessPoint) {
    final ssid = accessPoint.ssid.trim();
    final security = accessPoint.capabilities.isEmpty
        ? 'Open'
        : _normalizeSecurity(accessPoint.capabilities);

    return SignalNetwork(
      ssid: ssid.isEmpty ? 'Hidden network' : ssid,
      bssid: accessPoint.bssid,
      level: accessPoint.level,
      security: security,
      channel: accessPoint.frequency,
    );
  }

  String _normalizeSecurity(String capabilities) {
    final value = capabilities.toUpperCase();
    if (value.contains('WEP')) return 'WEP';
    if (value.contains('WPA3')) return 'WPA3';
    if (value.contains('WPA2')) return 'WPA2';
    if (value.contains('WPA')) return 'WPA';
    return 'Open';
  }

  Future<void> _runSpeedTest() async {
    if (!mounted || _connectedNetwork == null || _isTestingSpeed) return;

    setState(() {
      _isTestingSpeed = true;
      _status = 'Testing Wi‑Fi speed...';
    });

    final endpoints = [
      Uri.parse('https://speed.cloudflare.com/__down?bytes=10000000'),
      Uri.parse('https://www.google.com/favicon.ico'),
    ];

    try {
      for (final endpoint in endpoints) {
        final stopwatch = Stopwatch()..start();
        final response = await http
            .get(endpoint)
            .timeout(const Duration(seconds: 20));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }

        final bytes = response.contentLength ?? response.bodyBytes.length;
        stopwatch.stop();
        final seconds = stopwatch.elapsedMicroseconds / 1000000.0;

        if (bytes <= 0 || seconds <= 0) {
          continue;
        }

        final mbps = (bytes * 8 / 1000 / 1000) / seconds;

        if (mounted) {
          setState(() {
            _downloadSpeedMbps = mbps;
            _status = 'Connected speed: ${mbps.toStringAsFixed(1)} Mbps';
          });
        }
        return;
      }

      throw Exception('no valid speed test response');
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloadSpeedMbps = 0;
          _status = 'Speed unavailable on this network';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingSpeed = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  height: 420.h,
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
                        Positioned.fill(
                          child: CustomPaint(
                            painter: RadarPainter(
                              signalLevel: connectedNetwork?.level ?? -90,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  connectedNetwork == null
                                      ? 'No signal'
                                      : '${connectedNetwork.level} dBm',
                                  style: TextStyle(
                                    fontSize: 28.sp,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.35),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                Text(
                                  connectedNetwork == null
                                      ? 'Scan a room'
                                      : 'Signal strength',
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16.w,
                          right: 16.w,
                          bottom: 16.h,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _statChip('Signal', connectedNetwork == null ? 'No signal' : '${connectedNetwork.level} dBm'),
                              _statChip('Status', _status),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 18.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.w),
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
                          color: const Color(0xFF5EE6C5).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        child: Icon(
                          Icons.speed_rounded,
                          color: const Color(0xFF5EE6C5),
                          size: 22.sp,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connected Wi‑Fi speed',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: Colors.white.withOpacity(0.72),
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              _downloadSpeedMbps > 0
                                  ? '${_downloadSpeedMbps.toStringAsFixed(1)} Mbps download'
                                  : _isTestingSpeed
                                      ? 'Testing connection...' 
                                      : 'Tap to run a quick speed test',
                              style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _isTestingSpeed || connectedNetwork == null
                            ? null
                            : _runSpeedTest,
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFF5EE6C5).withOpacity(0.12),
                          foregroundColor: const Color(0xFF5EE6C5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                        ),
                        icon: _isTestingSpeed
                            ? SizedBox(
                                width: 14.w,
                                height: 14.h,
                                child: const CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(_isTestingSpeed ? 'Testing' : 'Test'),
                      ),
                    ],
                  ),
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

}
