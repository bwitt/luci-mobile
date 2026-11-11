import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/client.dart';

void main() {
  group('Client.fromLease', () {
    test('reads a typical odhcpd/dnsmasq lease', () {
      final client = Client.fromLease({
        'ipaddr': '192.168.1.100',
        'macaddr': 'AA:BB:CC:DD:EE:FF',
        'hostname': 'laptop',
        'expires': 3600,
        'activetime': '120',
        'vendor': 'Dell',
        'dnsname': 'laptop.lan',
      });

      expect(client.ipAddress, '192.168.1.100');
      expect(client.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(client.hostname, 'laptop');
      expect(client.leaseTime, 3600);
      expect(client.activeTime, 120);
      expect(client.vendor, 'Dell');
      expect(client.dnsName, 'laptop.lan');
      expect(client.expiresAt, isNotNull);
    });

    // Router data is loosely typed: numbers arrive as strings or doubles.
    test('accepts lease times as strings and doubles', () {
      expect(Client.fromLease({'expires': '42'}).leaseTime, 42);
      expect(Client.fromLease({'expires': 42.9}).leaseTime, 42);
      expect(Client.fromLease({'expires': 'soon'}).leaseTime, isNull);
      expect(Client.fromLease({'expires': true}).leaseTime, isNull);
    });

    test('an empty lease falls back to placeholders instead of throwing', () {
      final client = Client.fromLease(const {});
      expect(client.ipAddress, 'N/A');
      expect(client.macAddress, 'N/A');
      expect(client.hostname, 'Unknown');
      expect(client.expiresAt, isNull);
      expect(client.ipv6Addresses, isNull);
    });

    // dnsmasq writes `*` for a client that sent no hostname.
    test('a `*` or blank hostname falls through to the next name', () {
      expect(
        Client.fromLease({'hostname': '*', 'name': 'printer'}).hostname,
        'printer',
      );
      expect(
        Client.fromLease({'hostname': '  ', '_hintName': 'nas'}).hostname,
        'nas',
      );
      expect(Client.fromLease({'hostname': '*'}).hostname, 'Unknown');
    });

    test('an expired or zero lease has no expiry timestamp', () {
      expect(Client.fromLease({'expires': 0}).expiresAt, isNull);
      expect(Client.fromLease({'expires': -5}).expiresAt, isNull);
    });

    group('IPv6 addresses', () {
      test('are read from the ipv6addrs list', () {
        final client = Client.fromLease({
          'ipv6addrs': ['fd00::10', 'fe80::1'],
        });
        expect(client.ipv6Addresses, ['fd00::10', 'fe80::1']);
      });

      test('are split from a comma-separated ipv6addr string', () {
        final client = Client.fromLease({'ipv6addr': 'fd00::10, ,fe80::1'});
        expect(client.ipv6Addresses, ['fd00::10', 'fe80::1']);
      });

      test('are read from an ipv6addr list', () {
        final client = Client.fromLease({
          'ipv6addr': ['fd00::10'],
        });
        expect(client.ipv6Addresses, ['fd00::10']);
      });
    });

    test('carries the owning router and presence through', () {
      final client = Client.fromLease({
        '_routerId': 'r1',
        '_routerLabel': 'Home',
        '_online': false,
      });
      expect(client.routerId, 'r1');
      expect(client.routerLabel, 'Home');
      expect(client.isOnline, isFalse);
    });
  });

  group('guessing the connection type', () {
    test('signal data means wireless', () {
      expect(
        Client.fromLease({'signal': -60}).connectionType,
        ConnectionType.wireless,
      );
    });

    test('a switch port or eth interface means wired', () {
      expect(
        Client.fromLease({'port': 'lan1'}).connectionType,
        ConnectionType.wired,
      );
      expect(
        Client.fromLease({'ifname': 'eth0.1'}).connectionType,
        ConnectionType.wired,
      );
    });

    test('a phone-like hostname means wireless', () {
      expect(
        Client.fromLease({'hostname': 'Pixel-Android'}).connectionType,
        ConnectionType.wireless,
      );
      expect(
        Client.fromLease({'hostname': 'iPhone'}).connectionType,
        ConnectionType.wireless,
      );
    });

    test('a known vendor OUI decides when nothing else does', () {
      expect(
        Client.fromLease({'macaddr': 'A4:4C:C8:01:02:03'}).connectionType,
        ConnectionType.wireless,
      );
      expect(
        Client.fromLease({'macaddr': '00:1A:4D:01:02:03'}).connectionType,
        ConnectionType.wired,
      );
      expect(
        Client.fromLease({'macaddr': '02:00:00:01:02:03'}).connectionType,
        ConnectionType.unknown,
      );
    });

    // A client that left is no longer anywhere; the guess would keep
    // calling it wired or wireless (#5).
    test('is not guessed for a client presence found offline', () {
      expect(
        Client.fromLease({'hostname': 'iPhone', '_online': false})
            .connectionType,
        ConnectionType.unknown,
      );
      expect(
        Client.fromLease({'hostname': 'iPhone', '_online': true})
            .connectionType,
        ConnectionType.wireless,
      );
    });
  });

  group('formatting', () {
    test('formatDuration drops zero units and never returns empty', () {
      expect(Client.formatDuration(0), '0m');
      expect(Client.formatDuration(59), '0m');
      expect(Client.formatDuration(60), '1m');
      expect(Client.formatDuration(3600), '1h');
      expect(Client.formatDuration(90061), '1d 1h 1m');
      expect(Client.formatDuration(86400), '1d');
    });

    test('formattedLeaseTime distinguishes unlimited and expired', () {
      Client lease(int? t) =>
          Client(ipAddress: '', macAddress: '', hostname: '', leaseTime: t);
      expect(lease(null).formattedLeaseTime, 'Unlimited');
      expect(lease(0).formattedLeaseTime, 'Unlimited');
      expect(lease(-1).formattedLeaseTime, 'Expired');
      expect(lease(7200).formattedLeaseTime, '2h');
    });

    test('formattedActiveTime and formattedExpiresAt say N/A when unknown', () {
      final client = Client(ipAddress: '', macAddress: '', hostname: '');
      expect(client.formattedActiveTime, 'N/A');
      expect(client.formattedExpiresAt, 'N/A');
      expect(client.copyWith(activeTime: 3660).formattedActiveTime, '1h 1m');
      expect(
        client.copyWith(expiresAt: 1700000000).formattedExpiresAt,
        isNot('N/A'),
      );
    });
  });

  group('connectionLabel', () {
    Client base({
      ConnectionType type = ConnectionType.unknown,
      String? band,
      bool? online,
    }) => Client(
      ipAddress: '',
      macAddress: '',
      hostname: '',
      connectionType: type,
      wifiBand: band,
      isOnline: online,
    );

    test('offline wins over everything else', () {
      expect(
        base(
          type: ConnectionType.wireless,
          band: '5G',
          online: false,
        ).connectionLabel,
        'Offline',
      );
    });

    test('a known band is shown formatted', () {
      expect(base(band: '5G').connectionLabel, isNot('5G'));
      expect(base(band: '5G').connectionLabel, contains('5'));
    });

    test('falls back to the connection type', () {
      expect(base(type: ConnectionType.wireless).connectionLabel, 'Wi-Fi');
      expect(base(type: ConnectionType.wired).connectionLabel, 'Ethernet');
      expect(base().connectionLabel, 'Unknown');
    });
  });

  group('copying', () {
    final original = Client(
      ipAddress: '192.168.1.5',
      macAddress: 'AA:BB:CC:00:00:01',
      hostname: 'tv',
      isOnline: true,
      routerId: 'r1',
    );

    test('copyWith changes only what was passed', () {
      final copy = original.copyWith(hostname: 'living-room-tv');
      expect(copy.hostname, 'living-room-tv');
      expect(copy.ipAddress, original.ipAddress);
      expect(copy.isOnline, isTrue);
      expect(copy.routerId, 'r1');
    });

    // copyWith treats null as "keep", so it cannot forget presence.
    test('withOnline can set presence back to unknown', () {
      expect(original.copyWith(isOnline: null).isOnline, isTrue);
      final unknown = original.withOnline(null);
      expect(unknown.isOnline, isNull);
      expect(unknown.hostname, 'tv');
      expect(unknown.routerId, 'r1');
    });
  });

  test('fromWirelessStation is a wireless client with only a MAC', () {
    final client = Client.fromWirelessStation('AA:BB:CC:DD:EE:01');
    expect(client.macAddress, 'AA:BB:CC:DD:EE:01');
    expect(client.ipAddress, 'N/A');
    expect(client.connectionType, ConnectionType.wireless);
  });
}
