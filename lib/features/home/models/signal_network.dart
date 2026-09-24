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

double calculateDownloadSpeedMbps(int bytesTransferred, int elapsedMilliseconds) {
  if (bytesTransferred <= 0 || elapsedMilliseconds <= 0) {
    return 0;
  }

  final bits = bytesTransferred * 8.0;
  final seconds = elapsedMilliseconds / 1000.0;
  return bits / (1000 * 1000 * seconds);
}

SignalNetwork? findConnectedNetwork(
  String? ssid,
  String? bssid,
  List<SignalNetwork> networks,
) {
  final normalizedSsid = ssid?.trim().replaceAll('"', '');
  final normalizedBssid = bssid?.trim().toUpperCase();

  if ((normalizedSsid == null || normalizedSsid.isEmpty) &&
      (normalizedBssid == null || normalizedBssid.isEmpty)) {
    return null;
  }

  for (final network in networks) {
    final matchingSsid = network.ssid.trim().replaceAll('"', '');
    final matchingBssid = network.bssid.trim().toUpperCase();

    final ssidMatches = normalizedSsid != null &&
        normalizedSsid.isNotEmpty &&
        matchingSsid == normalizedSsid;
    final bssidMatches = normalizedBssid != null &&
        normalizedBssid.isNotEmpty &&
        matchingBssid == normalizedBssid;

    if (ssidMatches || bssidMatches) {
      return network;
    }
  }

  return null;
}
