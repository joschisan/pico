import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/drawers/leave_federation_drawer.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/bordered_list_widget.dart';

class ConnectionStatusScreen extends StatelessWidget {
  final PicoClient client;
  final PicoClientFactory clientFactory;

  const ConnectionStatusScreen({
    super.key,
    required this.client,
    required this.clientFactory,
  });

  Future<void> _onLeave(BuildContext context) async {
    LeaveFederationDrawer.show(
      context,
      client: client,
      clientFactory: clientFactory,
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
          future: client.federationName(),
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
      body: FutureBuilder<List<(int, String)>>(
        future: client.peers(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final peers = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BorderedList.column(
              children: [
                for (final (peerId, name) in peers)
                  StreamBuilder<bool>(
                    stream: client.livenessPeer(peerId: peerId),
                    builder: (_, peerSnap) {
                      final online = peerSnap.data;
                      return ListTile(
                        contentPadding: listTilePadding,
                        leading: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (online) {
                              null => color.withValues(alpha: 0.3),
                              true => color,
                              false => Colors.red,
                            },
                          ),
                        ),
                        title: Text(name, style: mediumStyle),
                        trailing: Text(
                          switch (online) {
                            null => '',
                            true => 'Online',
                            false => 'Offline',
                          },
                          style: smallStyle.copyWith(
                            color: online == true ? color : null,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
