import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lib.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';
import 'package:pico/screens/contact_name_entry_screen.dart';
import 'package:pico/screens/confirm_lnurl_send_screen.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/max_action_widget.dart';

class LnurlAmountScreen extends StatefulWidget {
  final PicoClient client;
  final PicoClientFactory clientFactory;
  final LnurlWrapper lnurl;
  final PayResponseWrapper payResponse;
  final String? contactName;

  const LnurlAmountScreen({
    super.key,
    required this.client,
    required this.clientFactory,
    required this.lnurl,
    required this.payResponse,
    this.contactName,
  });

  @override
  State<LnurlAmountScreen> createState() => _LnurlAmountScreenState();
}

class _LnurlAmountScreenState extends State<LnurlAmountScreen> {
  late String? _contactName = widget.contactName;
  // What a max send would pay: the balance less the gateway's cut, the
  // transaction fee and the app's cut. Null until it has been priced, and
  // when emptying the account isn't payable here at all.
  final ValueNotifier<int?> _maxAmount = ValueNotifier(null);
  // The gateway the max was priced against. The figure is only true through
  // it — a payee this gateway serves itself is priced without a routing fee —
  // so the send that follows must use it too, not select afresh.
  GatewayInfoWrapper? _gateway;
  // Reaches the entry widget's figure from the app bar's Max action; the
  // client never changes under this screen, so the key carries no reset duty.
  final _entryKey = GlobalKey<AmountEntryWidgetState>();

  @override
  void initState() {
    super.initState();
    _loadMaxAmount();
  }

  @override
  void dispose() {
    _maxAmount.dispose();
    super.dispose();
  }

  /// Prices the max the figure on screen has to hold to: against the invoice
  /// it will be paid over. Whether the gateway routes or is itself the payee
  /// decides the routing fee, and no amount says which — so this resolves a
  /// throwaway invoice at the payee's minimum first, picks the gateway for
  /// it, and prices against that. The probe costs one request and is never
  /// paid; what it buys is a figure [_handleConfirmMax] can resolve the real
  /// invoice for unchanged, so the confirmation screen shows the number the
  /// user pressed.
  ///
  /// Only offered when this payee would accept it. A payment capped to the
  /// payee's limit isn't a max send — it would leave notes behind, and the
  /// max path exists precisely to leave none.
  Future<void> _loadMaxAmount() async {
    try {
      // The payee's minimum, floored to sats by the wrapper — a minimum
      // under a sat floors to zero, which no invoice can carry.
      final probeSats =
          widget.payResponse.minSats < 1 ? 1 : widget.payResponse.minSats;

      final probe = await lnurlResolve(
        payResponse: widget.payResponse,
        amountSats: probeSats,
      );

      final gateway = await widget.client.lnSelectGatewayForInvoice(
        invoice: probe,
      );

      final max = await widget.client.lnMaxAmountForInvoice(
        gateway: gateway,
        invoice: probe,
      );

      if (!mounted || max <= 0) return;

      if (max < widget.payResponse.minSats) return;
      if (widget.payResponse.maxSats < max) return;

      _gateway = gateway;
      _maxAmount.value = max;
    } catch (_) {
      // No invoice or no gateway to price against, so no max to offer. The
      // screen still sends any amount typed into it, which needs a gateway
      // only later.
    }
  }

  /// Resolves the invoice for the entered amount, selects the gateway for that
  /// specific invoice (exact fee, with the direct-swap shortcut applied), then
  /// hands both off to the confirmation screen.
  Future<void> _handleConfirm(int amountSats) async {
    final invoice = await lnurlResolve(
      payResponse: widget.payResponse,
      amountSats: amountSats,
    );

    final gateway = await widget.client.lnSelectGatewayForInvoice(
      invoice: invoice,
    );

    final feeSats = gateway.gatewayFeeForInvoice(invoice: invoice);

    _confirm(
      invoice: invoice,
      amountSats: amountSats,
      gateway: gateway,
      feeSats: feeSats,
      isMax: false,
    );
  }

  /// Resolves the real invoice for the figure on screen, through the gateway
  /// it was priced against. The probe in [_loadMaxAmount] already settled
  /// whether that gateway routes or is the payee, so in the ordinary case
  /// the re-pricing below confirms the figure and the confirmation screen
  /// shows the number the user pressed.
  ///
  /// The figure is still re-priced against the invoice actually being paid:
  /// the balance can move while the screen is open, and a payee may issue
  /// from a different gateway than its probe. An amount that no longer
  /// empties the account is re-resolved at the one that does — a max send
  /// pays a stale figure without complaint, as an ordinary send that leaves
  /// change behind, so this re-pricing is what upholds the emptying.
  Future<void> _handleConfirmMax() async {
    var amountSats = _maxAmount.value!;
    final gateway = _gateway!;

    var invoice = await lnurlResolve(
      payResponse: widget.payResponse,
      amountSats: amountSats,
    );

    final exact = await widget.client.lnMaxAmountForInvoice(
      gateway: gateway,
      invoice: invoice,
    );

    if (exact != amountSats) {
      // The exact figure can climb past what this payee accepts, and a
      // capped payment is no longer a max send.
      if (widget.payResponse.maxSats < exact) {
        throw 'This account holds more than this address accepts';
      }

      amountSats = exact;

      invoice = await lnurlResolve(
        payResponse: widget.payResponse,
        amountSats: amountSats,
      );
    }

    _confirm(
      invoice: invoice,
      amountSats: amountSats,
      gateway: gateway,
      feeSats: gateway.gatewayFeeForInvoice(invoice: invoice),
      isMax: true,
    );
  }

  void _confirm({
    required Bolt11InvoiceWrapper invoice,
    required int amountSats,
    required GatewayInfoWrapper gateway,
    required int feeSats,
    required bool isMax,
  }) {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (_) => ConfirmLnurlSendScreen(
              client: widget.client,
              invoice: invoice,
              amountSats: amountSats,
              gateway: gateway,
              feeSats: feeSats,
              contactName: _contactName,
              isMax: isMax,
            ),
      ),
    );
  }

  Future<void> _handleSaveContact() async {
    final name = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => ContactNameEntryScreen(
              clientFactory: widget.clientFactory,
              lnurl: widget.lnurl,
            ),
      ),
    );

    if (mounted && name != null) {
      setState(() => _contactName = name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_contactName ?? 'Send Lightning'),
        actions: [
          if (_contactName == null)
            IconButton(
              icon: const Icon(
                PhosphorIconsRegular.userPlus,
                size: smallIconSize,
              ),
              onPressed: _handleSaveContact,
            ),
          MaxAction(maxAmount: _maxAmount, entry: _entryKey),
        ],
      ),
      body: SafeArea(
        maintainBottomViewPadding: true,
        child: AmountEntryWidget(
          key: _entryKey,
          client: widget.client,
          onConfirm: _handleConfirm,
          maxAmount: _maxAmount,
          onConfirmMax: _handleConfirmMax,
          buttonText: 'Continue',
        ),
      ),
    );
  }
}
