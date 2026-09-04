import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/utils/drawer_utils.dart';
import 'package:pico/widgets/bleed_list_widget.dart';
import 'package:pico/widgets/drawer_shell_widget.dart';
import 'package:pico/widgets/settings_card_widget.dart';

/// One of a mint's accounts as the picker sees it: the account to hand
/// back when it is chosen, and the live balance to show while choosing.
typedef AccountOption = ({PicoAccount account, ValueListenable<int?> balance});

/// Picks which of a mint's three accounts the pager sits on.
///
/// The pager only carries the accounts worth carrying — primary, plus
/// whichever others hold money or have been asked for — so this is the one
/// place all three are listed. Choosing an empty one is how it gets a page:
/// there is nothing to create, only a balance to start showing.
class SelectAccountDrawer extends StatelessWidget {
  /// Every account of the mint in view, in the order the pager would
  /// swipe them.
  final List<AccountOption> accounts;

  final void Function(PicoAccount) onSelect;

  const SelectAccountDrawer({
    super.key,
    required this.accounts,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required List<AccountOption> accounts,
    required void Function(PicoAccount) onSelect,
  }) {
    return DrawerUtils.show(
      context: context,
      child: SelectAccountDrawer(accounts: accounts, onSelect: onSelect),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DrawerShell(
      children: [
        BleedList.column(
          children: [for (final option in accounts) _row(option)],
        ),
      ],
    );
  }

  Widget _row(AccountOption option) {
    return ValueListenableBuilder<int?>(
      valueListenable: option.balance,
      builder: (context, sats, _) {
        return SettingsCard(
          // The same chip the home row and the page list carry, so an account
          // reads as an account wherever it is listed.
          icon: PhosphorIconsRegular.stack,
          title: option.account.account.display(),
          // Null until the first value lands, which leaves the row single-line
          // rather than claiming a balance of zero it hasn't read yet.
          subtitle:
              sats == null ? null : '${NumberFormat('#,###').format(sats)} sat',
          // Every row picks, including the account already in view — landing
          // back where you started is a fair answer to opening the list.
          onTap: () {
            Navigator.of(context).pop();
            onSelect(option.account);
          },
        );
      },
    );
  }
}
