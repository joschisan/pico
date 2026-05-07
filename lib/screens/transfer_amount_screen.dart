import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/fee_preview_widget.dart';

/// Lightning transfer between two federations: dest mints a bolt11,
/// source pays it. Routing fees come out of the source side silently.
class TransferAmountScreen extends StatefulWidget {
  final PicoClient source;
  final PicoClient dest;

  const TransferAmountScreen({
    super.key,
    required this.source,
    required this.dest,
  });

  @override
  State<TransferAmountScreen> createState() => _TransferAmountScreenState();
}

class _TransferAmountScreenState extends State<TransferAmountScreen> {
  int _amountSats = 0;

  // Both gateways prefetched on init so the combined fee updates
  // synchronously as the user types.
  GatewayInfoWrapper? _sourceGateway;
  GatewayInfoWrapper? _destGateway;
  bool _gatewayFailed = false;

  @override
  void initState() {
    super.initState();
    widget.source.lnSelectAnyGateway().then(
      (g) {
        if (mounted) setState(() => _sourceGateway = g);
      },
      onError: (_) {
        if (mounted) setState(() => _gatewayFailed = true);
      },
    );
    widget.dest.lnSelectAnyGateway().then(
      (g) {
        if (mounted) setState(() => _destGateway = g);
      },
      onError: (_) {
        if (mounted) setState(() => _gatewayFailed = true);
      },
    );
  }

  Future<void> _handleConfirm(int amountSats) async {
    final src = _sourceGateway;
    final dst = _destGateway;
    if (src == null || dst == null) throw 'Querying gateway fees…';

    final bolt11 = await widget.dest.lnReceive(
      gateway: dst,
      amountSat: amountSats,
    );
    final invoice = parseBolt11Invoice(invoice: bolt11)!;
    await widget.source.lnSend(gateway: src, invoice: invoice);

    if (!mounted) return;

    Navigator.of(context).pop();
  }

  Widget _buildFeePreview() {
    if (_gatewayFailed) return const FeePreview.error(label: 'gateway fee');
    final src = _sourceGateway;
    final dst = _destGateway;
    if (src == null || dst == null) {
      return const FeePreview.loading(label: 'gateway fee');
    }
    final combined =
        src.gatewayFeeForAmount(amountSats: _amountSats) +
        dst.gatewayFeeForReceiveAmount(amountSats: _amountSats);
    return FeePreview.value(combined, label: 'gateway fee');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lightning Transfer')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: BorderedList.column(
                children: [
                  _EndpointRow(client: widget.source, role: 'Origin'),
                  _EndpointRow(client: widget.dest, role: 'Destination'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildFeePreview(),
            ),
            Expanded(
              child: AmountEntryWidget(
                client: widget.source,
                onConfirm: _handleConfirm,
                onAmountChanged:
                    (sats) => setState(() => _amountSats = sats),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  final PicoClient client;
  final String role;

  const _EndpointRow({required this.client, required this.role});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: listTilePadding,
      trailing: Text(
        role,
        style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
      ),
      leading: StreamBuilder<List<(String, bool)>>(
        stream: client.subscribeConnectionStatus(),
        builder: (_, snapshot) {
          final online = snapshot.data?.any((s) => s.$2) ?? false;
          return Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  online
                      ? scheme.primary
                      : scheme.primary.withValues(alpha: 0.3),
            ),
          );
        },
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<int>(
            stream: client.subscribeBalance(),
            builder: (_, snapshot) {
              final sats = snapshot.data ?? 0;
              return Text(
                '${NumberFormat('#,###').format(sats)} sat',
                style: mediumStyle,
              );
            },
          ),
          FutureBuilder<String?>(
            future: client.federationName(),
            builder:
                (_, snapshot) => Text(
                  snapshot.data ?? '…',
                  style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
        ],
      ),
    );
  }
}
