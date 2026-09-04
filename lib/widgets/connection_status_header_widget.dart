import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/icon_chip_widget.dart';

/// Overall mint reachability shown above the node list, as a row that
/// mirrors the node rows: the mint's icon-chip badge with its name as the
/// header and an online/offline status beneath.
///
/// [operational] is the bridge's judgement that enough nodes are
/// reachable to sign, by picomint's own threshold. The badge carries
/// the primary colour while reachable and turns amber when too few nodes
/// are connected — the same split the mint row on home uses.
class ConnectionStatusHeader extends StatelessWidget {
  final String name;
  final bool operational;

  const ConnectionStatusHeader({
    super.key,
    required this.name,
    required this.operational,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        operational ? Theme.of(context).colorScheme.primary : warningColor;

    return ListTile(
      contentPadding: listTilePadding,
      leading: IconChip(icon: PhosphorIconsRegular.stack, color: color),
      title: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: mediumStyle),
          Text(
            operational ? 'Online' : 'Offline',
            style: smallStyle.copyWith(color: operational ? color : null),
          ),
        ],
      ),
    );
  }
}
