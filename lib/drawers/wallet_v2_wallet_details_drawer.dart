import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/detail_row_widget.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/utils/currency_utils.dart';

class WalletV2WalletDetailsDrawer extends StatelessWidget {
  final Pico pico;
  final MintStats stats;

  const WalletV2WalletDetailsDrawer({
    super.key,
    required this.pico,
    required this.stats,
  });

  static Future<void> show(
    BuildContext context, {
    required Pico pico,
    required MintStats stats,
  }) {
    return DrawerUtils.show(
      context: context,
      child: WalletV2WalletDetailsDrawer(pico: pico, stats: stats),
    );
  }

  String _btc(int sats) => '${(sats / 100000000).toStringAsFixed(8)} BTC';

  String _count(int n) => NumberFormat('#,###').format(n);

  // The consensus feerate is reported in sats per 1000 vbytes (kvB),
  // so divide by 1000 to display it as sat/vB with a decimal point.
  String _feerate(int satPerKvb) {
    final value = (satPerKvb / 1000).toStringAsFixed(3);

    return '${value.replaceFirst(RegExp(r'\.?0+$'), '')} sat/vB';
  }

  @override
  Widget build(BuildContext context) {
    final feerate = stats.feerate;
    final fiat = cachedFiat(pico, stats.totalValueSat);

    return DrawerShell(
      children: [
        BorderedList.column(
          children: [
            DetailRow(
              icon: PhosphorIconsRegular.currencyBtc,
              label: 'Bitcoin in Custody',
              value: _btc(stats.totalValueSat),
            ),
            if (fiat != null)
              DetailRow(
                icon: PhosphorIconsRegular.currencyDollar,
                label: '${fiat.currency.name} in Custody',
                value: formatFiat(fiat.currency, fiat.value),
              ),
            DetailRow(
              icon: PhosphorIconsRegular.cube,
              label: 'Block Count',
              value: _count(stats.blockCount),
            ),
            if (feerate != null)
              DetailRow(
                icon: PhosphorIconsRegular.speedometer,
                label: 'Feerate',
                value: _feerate(feerate),
              ),
          ],
        ),
      ],
    );
  }
}
