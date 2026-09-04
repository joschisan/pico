import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/async_button_widget.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/widgets/balanced_text_widget.dart';

class ExpirationDrawer extends StatelessWidget {
  final Pico pico;
  final int date;
  final InviteCodeWrapper? successor;

  const ExpirationDrawer({
    super.key,
    required this.pico,
    required this.date,
    this.successor,
  });

  static Future<void> show(
    BuildContext context, {
    required Pico pico,
    required int date,
    InviteCodeWrapper? successor,
  }) {
    return DrawerUtils.show(
      context: context,
      child: ExpirationDrawer(pico: pico, date: date, successor: successor),
    );
  }

  String _formatDate() {
    return DateFormat.yMMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(date * 1000),
    );
  }

  Future<void> _addSuccessor(BuildContext context) async {
    await pico.addMint(invite: successor!);

    if (!context.mounted) return;

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = _formatDate();

    return DrawerShell(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: BalancedText(
            'This mint will expire on $formattedDate, please migrate your funds before this date.',
            textAlign: TextAlign.center,
            style: smallStyle.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        if (successor != null) ...[
          const SizedBox(height: 16),
          AsyncButton(
            text: 'Add Successor Mint',
            onPressed: () => _addSuccessor(context),
          ),
        ],
      ],
    );
  }
}
