import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/drawers/leave_federation_drawer.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/bordered_list_widget.dart';

class ConnectionStatusScreen extends StatefulWidget {
  final PicoClient client;
  final PicoClientFactory clientFactory;

  const ConnectionStatusScreen({
    super.key,
    required this.client,
    required this.clientFactory,
  });

  @override
  State<ConnectionStatusScreen> createState() => _ConnectionStatusScreenState();
}

class _ConnectionStatusScreenState extends State<ConnectionStatusScreen> {
  // The same stream the home ring reads — backed by the client's kept-alive
  // connections and emitting the current snapshot first, so dots don't
  // flicker in. Each entry is `(name, rttMs)`: a non-null RTT means that
  // guardian is connected, and carries its round-trip time in milliseconds.
  late final Stream<List<(String, double?)>> _stream =
      widget.client.subscribeConnectionStatus();

  // Round-trip time, sampled at connect. Sub-10ms links keep one decimal so
  // a fast guardian doesn't collapse to a misleading "0 ms".
  String _formatRtt(double ms) =>
      '${ms < 10 ? ms.toStringAsFixed(1) : ms.round()} ms';

  Future<void> _onLeave(BuildContext context) async {
    LeaveFederationDrawer.show(
      context,
      client: widget.client,
      clientFactory: widget.clientFactory,
      onSuccess: () {
        // The leave drawer pops itself; once it's gone, pop the
        // connection-status screen too so the user lands back on
        // settings (which re-fetches via subscribe_global_balance et al).
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<String?>(
          future: widget.client.federationName(),
          builder: (context, snapshot) {
            return Text(snapshot.data ?? 'Federation');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.signOut, size: smallIconSize),
            onPressed: () => _onLeave(context),
          ),
        ],
      ),
      body: StreamBuilder<List<(String, double?)>>(
        stream: _stream,
        builder: (context, snapshot) {
          final statuses = snapshot.data;
          if (statuses == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BorderedList.column(
              children: [
                for (final (name, rttMs) in statuses)
                  ListTile(
                    contentPadding: listTilePadding,
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: rttMs != null ? color : Colors.red,
                      ),
                    ),
                    title: Text(name, style: mediumStyle),
                    subtitle: Text(
                      rttMs != null ? 'Connected' : 'Disconnected',
                      style: smallStyle.copyWith(
                        color: rttMs != null ? color : Colors.red,
                      ),
                    ),
                    trailing: rttMs != null
                        ? Text(_formatRtt(rttMs), style: smallStyle)
                        : null,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
