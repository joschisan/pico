import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/fountain.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';
import 'package:pico/drawers/ecash_drawer.dart';
import 'package:pico/drawers/invite_drawer.dart';
import 'package:pico/drawers/lightning_send_drawer.dart';
import 'package:pico/drawers/lnurl_drawer.dart';
import 'package:pico/screens/onchain_amount_screen.dart';

/// The flow [input] routes to — an invite, a Bolt11 invoice, an ecash
/// bundle, a bitcoin address, an lnurl, or a fountain fragment when
/// [decoder] rides along — or null when nothing recognised it. One table
/// serves scan, paste and deep link, so the three inputs can never drift
/// apart in what they accept.
///
/// Matching and acting are split so the scanner can stop itself, fire the
/// haptic and pop before the flow opens; callers with nothing to tear
/// down just run the action.
///
/// [account] is the account in view — the one every payment flow spends
/// from or receives into. Null (no mint added yet) matches invites only:
/// that is how the user adds their first mint. InviteDrawer owns the add
/// lifecycle so its own still-mounted context drives the pop and toast.
VoidCallback? matchInput(
  BuildContext context, {
  required Pico pico,
  required String input,
  required PicoAccount? account,
  EcashDecoder? decoder,
}) {
  final invite = parseInviteCode(invite: input);
  if (invite != null) {
    return () => InviteDrawer.show(context, invite: invite, pico: pico);
  }

  if (account == null) return null;

  final invoice = parseBolt11Invoice(invoice: input);
  if (invoice != null) {
    return () => LightningSendDrawer.show(
      context,
      account: account,
      pico: pico,
      invoice: invoice,
    );
  }

  final ecash = parseEcash(ecash: input);
  if (ecash != null) {
    return () =>
        EcashDrawer.show(context, selected: account, pico: pico, ecash: ecash);
  }

  final address = parseBitcoinAddress(address: input);
  if (address != null) {
    // An address carries no amount, so there is nothing to confirm before
    // asking for one — go straight to the amount entry.
    return () => Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => OnchainAmountScreen(
              account: account,
              pico: pico,
              address: address,
            ),
      ),
    );
  }

  final lnurl = parseLnurl(request: input);
  if (lnurl != null) {
    return () =>
        LnurlDrawer.show(context, account: account, pico: pico, lnurl: lnurl);
  }

  final fragment = decoder?.addFragment(fragment: input);
  if (fragment != null) {
    return () => EcashDrawer.show(
      context,
      selected: account,
      pico: pico,
      ecash: fragment,
    );
  }

  return null;
}
