import 'package:flutter_test/flutter_test.dart';
import 'package:wifiradar/features/home/models/signal_network.dart';

void main() {
  const networks = [
    SignalNetwork(
      ssid: 'Home WiFi',
      bssid: 'AA:BB:CC:DD:EE:FF',
      level: -55,
      security: 'WPA2',
      channel: 6,
    ),
    SignalNetwork(
      ssid: 'Office WiFi',
      bssid: '11:22:33:44:55:66',
      level: -68,
      security: 'WPA2',
      channel: 149,
    ),
  ];

  test('returns the matching network when the SSID or BSSID matches', () {
    expect(
      findConnectedNetwork('Home WiFi', null, networks),
      equals(networks.first),
    );

    expect(
      findConnectedNetwork(null, '11:22:33:44:55:66', networks),
      equals(networks[1]),
    );
  });

  test('returns null when there is no connected network match', () {
    expect(findConnectedNetwork('Unknown WiFi', null, networks), isNull);
    expect(findConnectedNetwork(null, null, networks), isNull);
  });
}
