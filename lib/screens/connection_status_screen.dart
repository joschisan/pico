import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/bleed_column_widget.dart';
import 'package:pico/widgets/bleed_list_widget.dart';
import 'package:pico/widgets/connection_status_header_widget.dart';
import 'package:pico/widgets/icon_chip_widget.dart';
import 'package:pico/widgets/section_header_widget.dart';

/// Per-node reachability for one mint. Removing it lives in the
/// settings drawer alongside the row that opens this screen, so there is no
/// destructive action up here.
class ConnectionStatusScreen extends StatefulWidget {
  final PicoAccount account;
  final Pico pico;

  const ConnectionStatusScreen({
    super.key,
    required this.account,
    required this.pico,
  });

  @override
  State<ConnectionStatusScreen> createState() => _ConnectionStatusScreenState();
}

class _ConnectionStatusScreenState extends State<ConnectionStatusScreen> {
  // The same stream the home row reads — backed by the client's kept-alive
  // connections and emitting the current snapshot first, so statuses don't
  // flicker in.
  late final Stream<MintConnectivity> _stream = widget.pico
      .subscribeConnectivity(mint: widget.account.mint);

  // Round-trip time, sampled at connect. Sub-10ms links keep one decimal so
  // a fast node doesn't collapse to a misleading "0 ms".
  String _formatRtt(double ms) =>
      '${ms < 10 ? ms.toStringAsFixed(1) : ms.round()} ms';

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Connectivity')),
      body: StreamBuilder<MintConnectivity>(
        stream: _stream,
        builder: (context, snapshot) {
          final connectivity = snapshot.data;
          if (connectivity == null) {
            return const Center(child: smallSpinner);
          }

          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
            child: BleedColumn(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(title: 'Mint'),
                BleedList.column(
                  children: [
                    ConnectionStatusHeader(
                      name: widget.account.mintName,
                      operational: connectivity.operational,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SectionHeader(title: 'Nodes'),
                BleedList.column(
                  children: [
                    for (final node in connectivity.nodes)
                      ListTile(
                        contentPadding: listTilePadding,
                        leading: IconChip(
                          icon: PhosphorIconsRegular.hardDrives,
                          color: node.rttMs != null ? null : warningColor,
                        ),
                        // Stack name/status in the title (not subtitle) to
                        // keep the single-line tile height.
                        title: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(node.name, style: mediumStyle),
                            Text(
                              node.rttMs != null ? 'Online' : 'Offline',
                              style: smallStyle.copyWith(
                                color: node.rttMs != null ? color : null,
                              ),
                            ),
                          ],
                        ),
                        // The round-trip time of the live link, measured
                        // over the same kept-alive connection requests use.
                        trailing: switch (node.rttMs) {
                          null => null,
                          final rtt => Text(_formatRtt(rtt), style: smallStyle),
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
