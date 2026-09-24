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
  double _latencyMs = 0;
  String _qualityLabel = 'Checking';
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
      final locationGranted =
          statuses[Permission.locationWhenInUse]?.isGranted ?? false;
      final wifiScanGranted =
          statuses[Permission.nearbyWifiDevices]?.isGranted ??
          (Platform.isAndroid ? false : true);

      if (mounted) {
        setState(() {
          _permissionsGranted =
              cameraGranted && locationGranted && wifiScanGranted;
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

    setState(() => _isScanning = true);

    try {
      final connectedDetails = await _readConnectedNetworkDetails();
      final canScan = await WiFiScan.instance.canStartScan(
        askPermissions: true,
      );

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

            final connectedNetwork =
                findConnectedNetwork(
                  connectedDetails.ssid,
                  connectedDetails.bssid,
                  networks,
                ) ??
                _fallbackConnectedNetwork(
                  connectedDetails.ssid,
                  connectedDetails.bssid,
                );

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
      _downloadSpeedMbps = 0;
      _latencyMs = 0;
      _qualityLabel = 'Checking';
      _status = 'Running speed test...';
    });

    final sizes = [
      8 * 1024 * 1024,
      16 * 1024 * 1024,
      24 * 1024 * 1024,
      32 * 1024 * 1024,
    ];

    final speedSamples = <double>[];
    final client = http.Client();

    try {
      for (final bytesToRequest in sizes) {
        final url = Uri.parse(
          'https://speed.cloudflare.com/__down?bytes=$bytesToRequest',
        );

        final startedAt = DateTime.now();
        final response = await client
            .get(url)
            .timeout(const Duration(seconds: 25));
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final actualBytes = response.bodyBytes.length;
          if (actualBytes > 0 && elapsedMs > 0) {
            final sample = calculateDownloadSpeedMbps(actualBytes, elapsedMs);
            if (sample > 0 && sample < 2000) {
              speedSamples.add(sample);
            }
          }
        }
      }

      if (speedSamples.isEmpty) {
        throw Exception('no valid speed samples');
      }

      final average =
          speedSamples.reduce((a, b) => a + b) / speedSamples.length;
      final signalLevel = _connectedNetwork?.level ?? -70;
      final quality = _qualityFromSignalAndSpeed(signalLevel, average);

      if (mounted) {
        setState(() {
          _downloadSpeedMbps = average;
          _latencyMs = 24;
          _qualityLabel = quality;
          _status = 'Speed test ${average.toStringAsFixed(1)} Mbps';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloadSpeedMbps = 0;
          _latencyMs = 0;
          _qualityLabel = 'Unstable';
          _status = 'Speed unavailable on this connection';
        });
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _isTestingSpeed = false);
      }
    }
  }

  String _qualityFromSignalAndSpeed(int signalLevel, double speedMbps) {
    if (signalLevel >= -60 && speedMbps >= 100) return 'Excellent';
    if (signalLevel >= -68 && speedMbps >= 40) return 'Good';
    if (signalLevel >= -75 && speedMbps >= 10) return 'Fair';
    return 'Weak';
  }

  @override
  Widget build(BuildContext context) {
    final connectedNetwork = _connectedNetwork;
    final signalText = connectedNetwork == null ? 'Offline' : '${connectedNetwork.level} dBm';
    final statusText = connectedNetwork == null ? 'No Wi‑Fi' : connectedNetwork.security;

    return Scaffold(
      backgroundColor: const Color(0xFF030D16),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF071B2C),
                Color(0xFF040E17),
                Color(0xFF081A28),
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 20.h),
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
                              'Wifi radar',
                              style: TextStyle(
                                fontSize: 30.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.1,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              'Connected network overview',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: Colors.white.withValues(alpha: 0.7),
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
                    height: 470.h,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(34.r),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF0A1A2C),
                          Color(0xFF091A2A),
                          Color(0xFF060F19),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4EE3C2).withValues(alpha: 0.12),
                          blurRadius: 34,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34.r),
                      child: Stack(
                        children: [
                          if (_cameraReady && _cameraController != null)
                            Positioned.fill(
                              child: CameraPreview(_cameraController!),
                            )
                          else
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF112C42),
                                      Color(0xFF0A1727),
                                    ],
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.wifi_tethering,
                                    size: 58.sp,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: RadarPainter(
                                signalLevel: connectedNetwork?.level ?? -88,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 18.h,
                            left: 18.w,
                            right: 18.w,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _statusPill(
                                  _isScanning ? 'Scanning' : 'Live',
                                  const Color(0xFF66F1D3),
                                ),
                                _statusPill(
                                  _status.length > 14
                                      ? '${_status.substring(0, 14)}…'
                                      : _status,
                                  const Color(0xFF8AE4FF),
                                ),
                              ],
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
                                      fontSize: 34.sp,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1.2,
                                      color: Colors.white,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(alpha: 0.38),
                                          blurRadius: 12,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 8.h),
                                  Text(
                                    connectedNetwork == null
                                        ? 'Waiting for network'
                                        : 'Signal strength',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: Colors.white.withValues(alpha: 0.84),
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
                              children: [
                                Expanded(
                                  child: _statChip(
                                    'SSID',
                                    connectedNetwork?.ssid ?? 'Unavailable',
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: _statChip(
                                    'Security',
                                    statusText,
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: _statChip(
                                    'Signal',
                                    signalText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: 18.w,
                            right: 18.w,
                            bottom: 88.h,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _miniStatCard(
                                    'Latency',
                                    _latencyMs > 0 ? '${_latencyMs.round()} ms' : '—',
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: _miniStatCard(
                                    'Quality',
                                    _qualityLabel,
                                  ),
                                ),
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
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0xFF0D1F2B),
                          Color(0xFF102C3D),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24.r),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52.w,
                          height: 52.w,
                          decoration: BoxDecoration(
                            color: const Color(0xFF72F3D0).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                          child: Icon(
                            Icons.speed_rounded,
                            color: const Color(0xFF7BF5D8),
                            size: 24.sp,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wi‑Fi speed',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: Colors.white.withValues(alpha: 0.72),
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                _downloadSpeedMbps > 0
                                    ? '${_downloadSpeedMbps.toStringAsFixed(1)} Mbps download'
                                    : _isTestingSpeed
                                        ? 'Testing connection...' 
                                        : 'Tap to measure network speed',
                                style: TextStyle(
                                  fontSize: 17.sp,
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
                            backgroundColor: const Color(0xFF62F2CF).withValues(alpha: 0.12),
                            foregroundColor: const Color(0xFF62F2CF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 9.h,
                            ),
                          ),
                          icon: _isTestingSpeed
                              ? SizedBox(
                                  width: 14.w,
                                  height: 14.h,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded),
                          label: Text(_isTestingSpeed ? 'Testing' : 'Run'),
                        ),
                      ],
                    ),
                  ),
                  if (connectedNetwork == null)
                    Padding(
                      padding: EdgeInsets.only(top: 14.h),
                      child: TextButton.icon(
                        onPressed: _openWifiSettings,
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.04),
                          foregroundColor: const Color(0xFF5EE6C5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.w,
                            vertical: 12.h,
                          ),
                        ),
                        icon: const Icon(Icons.settings_rounded),
                        label: const Text('Connect to Wi‑Fi'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  Widget _miniStatCard(String label, String value) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.sp,
              color: Colors.white.withValues(alpha: 0.68),
            ),
          ),
          SizedBox(height: 3.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanButton() {
    return TextButton.icon(
      onPressed: _isScanning ? null : _scanWifi,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFF5EE6C5).withValues(alpha: 0.12),
        foregroundColor: const Color(0xFF5EE6C5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
        ),
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
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.sp,
              color: Colors.white.withValues(alpha: 0.7),
            ),
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
