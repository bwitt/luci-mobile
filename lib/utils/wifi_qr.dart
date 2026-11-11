import 'package:luci_mobile/utils/uci_values.dart';

/// The `T:` field of a Wi-Fi QR code.
enum WifiQrSecurity {
  wpa('WPA'),
  wep('WEP'),
  nopass('nopass');

  const WifiQrSecurity(this.token);

  final String token;
}

/// The QR security for an OpenWrt `encryption` value, or null for 802.1X
/// (`wpa`, `wpa2`, `wpa3`, …) and anything unknown, which a password can't join.
WifiQrSecurity? wifiQrSecurity(String? encryption) {
  final mode = (encryption ?? '').trim().toLowerCase().split('+').first;
  if (mode.isEmpty || mode == 'none' || mode == 'owe') {
    return WifiQrSecurity.nopass;
  }
  if (mode.startsWith('wep')) return WifiQrSecurity.wep;
  if (mode.startsWith('psk') || mode.startsWith('sae')) {
    return WifiQrSecurity.wpa;
  }
  return null;
}

/// Backslash-escapes the characters the `WIFI:` format reserves.
String wifiQrEscape(String value) =>
    value.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');

/// A Wi-Fi network as the camera apps on iOS and Android read it from a QR.
class WifiQrNetwork {
  const WifiQrNetwork({
    required this.ssid,
    required this.security,
    this.password = '',
    this.hidden = false,
  });

  /// From a `wifi-iface` UCI section; null when it uses 802.1X.
  static WifiQrNetwork? fromUci(Map<dynamic, dynamic> section) {
    final security = wifiQrSecurity(uciText(section['encryption']));
    if (security == null) return null;
    var password = security == WifiQrSecurity.nopass
        ? ''
        : _raw(section['key']);
    if (security == WifiQrSecurity.wep) {
      // A WEP `key` of 1-4 selects one of key1..key4.
      if (RegExp(r'^[1-4]$').hasMatch(password)) {
        password = _raw(section['key$password']);
      }
      if (password.startsWith('s:')) password = password.substring(2);
    }
    return WifiQrNetwork(
      ssid: _raw(section['ssid']),
      security: security,
      password: password,
      hidden: uciBool(section['hidden']),
    );
  }

  final String ssid;
  final WifiQrSecurity security;
  final String password;
  final bool hidden;

  /// False when a password is needed but the router didn't return one.
  bool get hasPassword =>
      security == WifiQrSecurity.nopass || password.isNotEmpty;

  String get payload {
    final fields = StringBuffer('WIFI:T:${security.token};')
      ..write('S:${wifiQrEscape(ssid)};');
    if (security != WifiQrSecurity.nopass) {
      fields.write('P:${wifiQrEscape(password)};');
    }
    if (hidden) fields.write('H:true;');
    return '$fields;';
  }
}

// Untrimmed, since spaces are significant in an SSID or passphrase.
String _raw(dynamic value) => switch (value) {
  null => '',
  List(isEmpty: true) => '',
  List(:final first) => first.toString(),
  _ => value.toString(),
};
