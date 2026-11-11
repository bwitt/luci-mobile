import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/screens/interfaces_screen.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/state/app_state.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/utils/wifi_qr.dart';
import 'package:luci_mobile/widgets/wifi_qr_sheet.dart';

class _TestAppState extends AppState {
  _TestAppState(this._data)
    : super.forTesting(
        apiService: MockApiService(),
        authService: MockAuthService(),
      );

  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic>? get dashboardData => _data;
}

Map<String, dynamic> _wireless(Map<String, Map<String, dynamic>> ifaces) => {
  'uciWirelessConfig': {
    'values': {
      'radio0': {'.type': 'wifi-device', 'band': '5g'},
      for (final e in ifaces.entries)
        e.key: {
          '.type': 'wifi-iface',
          'device': 'radio0',
          'mode': 'ap',
          'network': 'lan',
          ...e.value,
        },
    },
  },
};

Future<void> _pumpScreen(
  WidgetTester tester,
  Map<String, Map<String, dynamic>> ifaces,
  String expand,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStateProvider.overrideWith(
          (ref) => _TestAppState(_wireless(ifaces)),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: InterfacesScreen(scrollToInterface: expand),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _payload(WidgetTester tester) =>
    tester.widget<WifiQrSheet>(find.byType(WifiQrSheet)).network.payload;

void main() {
  testWidgets('the sheet renders the QR and reveals the password', (
    tester,
  ) async {
    const network = WifiQrNetwork(
      ssid: 'Home',
      security: WifiQrSecurity.wpa,
      password: 'hunter22',
    );
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: Scaffold(body: WifiQrSheet(network: network)),
      ),
    );

    expect(find.byType(QrImageView), findsOneWidget);
    expect(_payload(tester), 'WIFI:T:WPA;S:Home;P:hunter22;;');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('hunter22'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.text('hunter22'), findsOneWidget);
  });

  testWidgets('an open network shows no password row', (tester) async {
    const network = WifiQrNetwork(
      ssid: 'Guest',
      security: WifiQrSecurity.nopass,
      hidden: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: luciLocalizationsDelegates,
        home: Scaffold(body: WifiQrSheet(network: network)),
      ),
    );

    expect(_payload(tester), 'WIFI:T:nopass;S:Guest;H:true;;');
    expect(find.text('Password'), findsNothing);
  });

  testWidgets('a PSK interface opens the QR sheet from its card', (
    tester,
  ) async {
    await _pumpScreen(tester, {
      'home': {'ssid': 'Home', 'encryption': 'psk2', 'key': 'hunter22'},
    }, 'home');

    await tester.ensureVisible(find.text('Share via QR code'));
    await tester.tap(find.text('Share via QR code'));
    await tester.pumpAndSettle();

    expect(_payload(tester), 'WIFI:T:WPA;S:Home;P:hunter22;;');
  });

  testWidgets('an enterprise interface explains why it cannot be shared', (
    tester,
  ) async {
    await _pumpScreen(tester, {
      'corp': {'ssid': 'Corp', 'encryption': 'wpa2'},
    }, 'corp');

    final enterprise = find.textContaining('Enterprise (802.1X)');
    await tester.ensureVisible(enterprise);
    expect(enterprise, findsOneWidget);
    await tester.tap(find.text('Share via QR code'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
  });
}
