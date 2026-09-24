class SignalNetwork {
  const SignalNetwork({
    required this.ssid,
    required this.bssid,
    required this.level,
    required this.security,
    required this.channel,
  });

  final String ssid;
  final String bssid;
  final int level;
  final String security;
  final int channel;
}

const List<SignalNetwork> demoNetworks = [
  SignalNetwork(
    ssid: 'Office WiFi',
    bssid: '18:EF:63:AA:9A:15',
    level: -54,
    security: 'WPA2',
    channel: 149,
  ),
  SignalNetwork(
    ssid: 'Guest Access',
    bssid: 'A0:80:50:12:49:FD',
    level: -68,
    security: 'Open',
    channel: 11,
  ),
  SignalNetwork(
    ssid: 'Living Room',
    bssid: 'E8:48:B8:5C:12:0A',
    level: -75,
    security: 'WPA3',
    channel: 6,
  ),
  SignalNetwork(
    ssid: 'Studio Mesh',
    bssid: '90:1A:CA:21:4D:70',
    level: -82,
    security: 'WPA2',
    channel: 1,
  ),
];
