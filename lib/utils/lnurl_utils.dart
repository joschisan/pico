import 'package:pico/bridge_generated.dart/app.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';

/// The lnurl's pay limits, or null when the lnurl names an account of the
/// same mint: such a payment goes direct, funded straight from the account
/// with no gateway and no fee, and never contacts the lnurl's endpoint —
/// so there are no limits to ask for, and the null is what tells the
/// amount and confirmation screens which path they are on.
Future<PayResponseWrapper?> fetchLimitsUnlessDirect({
  required Pico pico,
  required PicoAccount account,
  required LnurlWrapper lnurl,
}) async {
  if (pico.lightningLnurlIsDirect(mint: account.mint, lnurl: lnurl)) {
    return null;
  }

  return lnurlFetchLimits(lnurl: lnurl);
}
