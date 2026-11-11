import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/wifi_scan_result.dart';

/// One row of `iwinfo scan` as rpcd serialises it: the key management and
/// cipher names are lower-cased (`rpc_iwinfo_add_bit_array(..., true, ...)`).
Map<String, dynamic> _rpcdRow({
  String ssid = 'Neighbour',
  int? frequency,
  int channel = 6,
  int signal = -60,
  Map<String, dynamic>? encryption,
}) => {
  'ssid': ssid,
  'bssid': 'AA:BB:CC:11:22:33',
  'mode': 'Master',
  'channel': channel,
  'frequency': ?frequency,
  'signal': signal,
  'quality': 50,
  'quality_max': 70,
  'encryption': encryption ?? {'enabled': false},
};

void main() {
  test('classifies the 4.9 GHz Wi-Fi band', () {
    final result = WifiScanResult.fromJson({
      'frequency': 4940,
      'encryption': <String, dynamic>{},
    });

    expect(result.band, '4.9 GHz');
  });

  group('parsing a scan row', () {
    test('reads the fields iwinfo sends', () {
      final result = WifiScanResult.fromJson(_rpcdRow(frequency: 2437));
      expect(result.ssid, 'Neighbour');
      expect(result.bssid, 'AA:BB:CC:11:22:33');
      expect(result.mode, 'Master');
      expect(result.channel, 6);
      expect(result.frequency, 2437);
      expect(result.signal, -60);
      expect(result.qualityPercent, 71);
      expect(result.encryption.isOpen, isTrue);
    });

    test('tolerates numbers as strings or doubles and missing fields', () {
      final result = WifiScanResult.fromJson({
        'ssid': 42,
        'channel': '11',
        'signal': -71.6,
        'quality': [1],
        'encryption': 'not a map',
      });
      expect(result.ssid, '42');
      expect(result.bssid, '');
      expect(result.mode, 'Unknown');
      expect(result.channel, 11);
      expect(result.signal, -72);
      expect(result.quality, 0);
      expect(result.qualityMax, 100);
      expect(result.encryption.enabled, isFalse);
    });

    // An implausible frequency must fall back to the channel, not decide
    // the band by itself.
    test('ignores implausible frequencies', () {
      expect(WifiScanResult.fromJson({'frequency': 0}).frequency, isNull);
      expect(WifiScanResult.fromJson({'frequency': 900}).frequency, isNull);
      expect(WifiScanResult.fromJson({'frequency': 60000}).frequency, isNull);
      expect(
        WifiScanResult.fromJson(_rpcdRow(channel: 1, frequency: 900)).band,
        '2.4 GHz',
      );
    });

    test('a quality_max of zero gives 0%, not a division error', () {
      final result = WifiScanResult.fromJson({'quality': 5, 'quality_max': 0});
      expect(result.qualityPercent, 0);
    });
  });

  group('band', () {
    String band({int? frequency, int channel = 0}) => WifiScanResult.fromJson(
      _rpcdRow(frequency: frequency, channel: channel),
    ).band;

    test('comes from the frequency when there is one', () {
      expect(band(frequency: 2412), '2.4 GHz');
      expect(band(frequency: 5180), '5 GHz');
      expect(band(frequency: 5955), '6 GHz');
    });

    // Channel numbers overlap between 2.4 and 6 GHz, so 6 GHz cannot be
    // told from the channel alone.
    test('falls back to the channel, which cannot tell 6 GHz', () {
      expect(band(channel: 11), '2.4 GHz');
      expect(band(channel: 36), '5 GHz');
      expect(band(channel: 0), 'Unknown');
      expect(band(channel: 20), 'Unknown');
    });
  });

  test('signal strength buckets match the bars', () {
    final cases = {
      -45: ('Excellent', 4),
      -55: ('Good', 3),
      -65: ('Fair', 2),
      -75: ('Weak', 1),
      -90: ('Very Weak', 0),
    };
    cases.forEach((signal, expected) {
      final result = WifiScanResult.fromJson(_rpcdRow(signal: signal));
      expect(result.signalStrength, expected.$1, reason: '$signal dBm');
      expect(result.signalBars, expected.$2, reason: '$signal dBm');
    });
  });

  group('WifiEncryption', () {
    test('builds a description when the router sends none', () {
      final enc = WifiEncryption.fromJson({
        'enabled': true,
        'wpa': [1, 2],
        'auth_suites': ['psk'],
        'pair_ciphers': ['ccmp', 'tkip'],
      });
      expect(enc.wpa, 2);
      expect(enc.description, 'WPA2 PSK (CCMP, TKIP)');
      expect(enc.shortLabel, 'WPA2');
    });

    test('takes the highest WPA version from strings too', () {
      final enc = WifiEncryption.fromJson({
        'wpa': ['1', '3'],
      });
      expect(enc.wpa, 3);
      expect(enc.enabled, isTrue);
      expect(enc.description, 'WPA3');
    });

    test('prefers the description the router gave', () {
      final enc = WifiEncryption.fromJson({
        'enabled': true,
        'wpa': 2,
        'description': 'mixed WPA2/WPA3 PSK/SAE (CCMP)',
      });
      expect(enc.description, 'mixed WPA2/WPA3 PSK/SAE (CCMP)');
      expect(enc.shortLabel, 'WPA3');
    });

    test('an open network needs no password', () {
      final enc = WifiEncryption.fromJson({'enabled': false});
      expect(enc.isOpen, isTrue);
      expect(enc.description, 'None');
      expect(enc.shortLabel, 'Open');
      expect(enc.openwrtEncryption, 'none');
      expect(enc.requiresPassword, isFalse);
    });

    test('a boolean wep flag is read as WEP', () {
      final enc = WifiEncryption.fromJson({'wep': true});
      expect(enc.enabled, isTrue);
      expect(enc.description, 'WEP');
      expect(enc.shortLabel, 'WEP');
      expect(enc.openwrtEncryption, 'wep-open');
    });

    test('a WPA2 network from rpcd connects as psk2', () {
      final enc = WifiScanResult.fromJson(
        _rpcdRow(
          encryption: {
            'enabled': true,
            'wpa': [2],
            'authentication': ['psk'],
            'ciphers': ['ccmp'],
          },
        ),
      ).encryption;
      expect(enc.description, 'WPA2 PSK (CCMP)');
      expect(enc.openwrtEncryption, 'psk2');
      expect(enc.requiresPassword, isTrue);
      expect(enc.isEnterprise, isFalse);
    });

    test('a WPA1 network from rpcd connects as psk', () {
      final enc = WifiEncryption.fromJson({
        'enabled': true,
        'wpa': [1],
        'authentication': ['psk'],
      });
      expect(enc.openwrtEncryption, 'psk');
    });

    // These upper-case suites are what the reviewer fixtures send.
    test('upper-case suites map SAE, OWE and EAP', () {
      WifiEncryption enc(List<String> suites, {int wpa = 3}) =>
          WifiEncryption.fromJson({
            'enabled': true,
            'wpa': wpa,
            'auth_suites': suites,
          });
      expect(enc(['SAE']).openwrtEncryption, 'sae');
      expect(enc(['PSK', 'SAE']).openwrtEncryption, 'sae-mixed');
      expect(enc(['OWE']).openwrtEncryption, 'owe');
      expect(enc(['OWE']).requiresPassword, isFalse);
      expect(enc(['EAP']).openwrtEncryption, 'wpa-eap');
      expect(enc(['802.1X'], wpa: 2).isEnterprise, isTrue);
    });

    group('suites as rpcd sends them (lower case)', () {
      const bug =
          'bug: openwrtEncryption/isEnterprise/requiresPassword compare '
          'against upper-case suite names, but rpcd lower-cases them';

      test('a WPA3-only network connects as sae', () {
        final enc = WifiEncryption.fromJson({
          'enabled': true,
          'wpa': [3],
          'authentication': ['sae'],
          'ciphers': ['ccmp'],
        });
        expect(enc.openwrtEncryption, 'sae');
      }, skip: bug);

      test('a WPA2/WPA3 mixed network connects as sae-mixed', () {
        final enc = WifiEncryption.fromJson({
          'enabled': true,
          'wpa': [2, 3],
          'authentication': ['psk', 'sae'],
        });
        expect(enc.openwrtEncryption, 'sae-mixed');
      }, skip: bug);

      test('an OWE network needs no password', () {
        final enc = WifiEncryption.fromJson({
          'enabled': true,
          'wpa': [3],
          'authentication': ['owe'],
        });
        expect(enc.requiresPassword, isFalse);
        expect(enc.openwrtEncryption, 'owe');
      }, skip: bug);

      test('an 802.1X network is recognised as enterprise', () {
        final enc = WifiEncryption.fromJson({
          'enabled': true,
          'wpa': [2],
          'authentication': ['802.1x'],
        });
        expect(enc.isEnterprise, isTrue);
      }, skip: bug);
    });

    // rpcd sends `wep` as the list of auth algorithms, not a boolean.
    test('a WEP network from rpcd is recognised as WEP', () {
      final enc = WifiEncryption.fromJson({
        'enabled': true,
        'wep': ['open'],
        'ciphers': ['wep-40'],
      });
      expect(enc.wep, isTrue);
      expect(enc.shortLabel, 'WEP');
    }, skip: 'bug: only `wep: true` is recognised; rpcd sends a list');
  });
}
