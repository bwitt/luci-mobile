import 'package:flutter/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/utils/wifi_qr.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:luci_mobile/widgets/platform_ui/vocabulary.dart';

/// A QR code a phone camera joins [network] from, with the SSID and password
/// spelled out beneath it for reading aloud.
class WifiQrSheet extends StatefulWidget {
  const WifiQrSheet({required this.network, super.key});

  final WifiQrNetwork network;

  @override
  State<WifiQrSheet> createState() => _WifiQrSheetState();
}

class _WifiQrSheetState extends State<WifiQrSheet> {
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final network = widget.network;
    const white = Color(0xFFFFFFFF);

    Widget field(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          value,
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.shareWifiTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.shareWifiScanHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Center(
              // Scanners need dark modules on light, whatever the theme.
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: network.payload,
                  size: 220,
                  padding: EdgeInsets.zero,
                  backgroundColor: white,
                  semanticsLabel: l10n.shareWifiTitle,
                ),
              ),
            ),
            const SizedBox(height: 8),
            field(
              l10n.ssid,
              Text(
                network.hidden
                    ? '${network.ssid} ${l10n.hiddenNetwork}'
                    : network.ssid,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            if (network.security != WifiQrSecurity.nopass)
              field(
                l10n.password,
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _obscurePassword ? '•' * 8 : network.password,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    AdaptiveButton.icon(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off,
                      style: AdaptiveButtonStyle.plain,
                      semanticLabel: _obscurePassword
                          ? l10n.showPassword
                          : l10n.hidePassword,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
