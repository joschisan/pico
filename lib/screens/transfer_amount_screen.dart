import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/drawers/federation_picker_drawer.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/bordered_list_widget.dart';
import 'package:pico/widgets/fee_preview_widget.dart';

/// Lightning transfer between two federations: dest mints a bolt11,
/// source pays it. Routing fees come out of the source side silently.
class TransferAmountScreen extends StatefulWidget {
  final PicoClient source;
  final PicoClient dest;
  final PicoClientFactory clientFactory;

  const TransferAmountScreen({
    super.key,
    required this.source,
    required this.dest,
    required this.clientFactory,
  });

  @override
  State<TransferAmountScreen> createState() => _TransferAmountScreenState();
}

class _TransferAmountScreenState extends State<TransferAmountScreen> {
  late PicoClient _source = widget.source;
  late PicoClient _dest = widget.dest;
  int _amountSats = 0;

  // Both gateways prefetched on init / on endpoint swap so the
  // combined fee updates synchronously as the user types.
  GatewayInfoWrapper? _sourceGateway;
  GatewayInfoWrapper? _destGateway;
  bool _gatewayFailed = false;

  @override
  void initState() {
    super.initState();
    _kickoffSourceGateway();
    _kickoffDestGateway();
  }

  void _kickoffSourceGateway() {
    _sourceGateway = null;
    _gatewayFailed = false;
    _source.lnSelectAnyGateway().then(
      (g) {
        if (mounted) setState(() => _sourceGateway = g);
      },
      onError: (_) {
        if (mounted) setState(() => _gatewayFailed = true);
      },
    );
  }

  void _kickoffDestGateway() {
    _destGateway = null;
    _gatewayFailed = false;
    _dest.lnSelectAnyGateway().then(
      (g) {
        if (mounted) setState(() => _destGateway = g);
      },
      onError: (_) {
        if (mounted) setState(() => _gatewayFailed = true);
      },
    );
  }

  Future<void> _openPicker({
    required String title,
    required ValueChanged<PicoClient> onSelected,
  }) async {
    final clients = await widget.clientFactory.clients();
    if (!mounted) return;
    FederationPickerDrawer.show(
      context,
      clients: clients,
      onSelected: onSelected,
      title: title,
    );
  }

  Future<void> _handleConfirm(int amountSats) async {
    final src = _sourceGateway;
    final dst = _destGateway;
    if (src == null || dst == null) throw 'Querying gateway fees…';

    final bolt11 = await _dest.lnReceive(gateway: dst, amountSat: amountSats);
    final invoice = parseBolt11Invoice(invoice: bolt11)!;
    await _source.lnSend(gateway: src, invoice: invoice);

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
                  _EndpointRow(
                    client: _source,
                    role: 'Source',
                    onTap:
                        () => _openPicker(
                          title: 'Select Source',
                          onSelected:
                              (c) => setState(() {
                                _source = c;
                                _kickoffSourceGateway();
                              }),
                        ),
                  ),
                  _EndpointRow(
                    client: _dest,
                    role: 'Destination',
                    onTap:
                        () => _openPicker(
                          title: 'Select Destination',
                          onSelected:
                              (c) => setState(() {
                                _dest = c;
                                _kickoffDestGateway();
                              }),
                        ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildFeePreview(),
            ),
            Expanded(
              child: AmountEntryWidget(
                key: ValueKey(_source.federationId()),
                client: _source,
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
  final VoidCallback onTap;

  const _EndpointRow({
    required this.client,
    required this.role,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: onTap,
      contentPadding: listTilePadding,
      trailing: Text(
        role,
        style: smallStyle.copyWith(color: scheme.onSurfaceVariant),
      ),
      leading: StreamBuilder<bool>(
        stream: client.liveness(),
        builder: (_, snapshot) {
          return Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (snapshot.data) {
                null => scheme.primary.withValues(alpha: 0.3),
                true => scheme.primary,
                false => Colors.red,
              },
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
