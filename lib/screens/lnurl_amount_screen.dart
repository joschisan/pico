import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:pico/bridge_generated.dart/client.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/bridge_generated.dart/lnurl.dart';
import 'package:pico/screens/contact_name_entry_screen.dart';
import 'package:pico/utils/auth_utils.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/amount_entry_widget.dart';
import 'package:pico/widgets/fee_preview_widget.dart';
import 'package:pico/widgets/federation_chip_widget.dart';
import 'package:share_plus/share_plus.dart';

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
  late PicoClient _client = widget.client;
  late String? _contactName = widget.contactName;
  GatewayInfoWrapper? _gateway;
  bool _gatewayFailed = false;
  int _amountSats = 0;

  @override
  void initState() {
    super.initState();
    _kickoffGatewaySelection();
  }

  void _kickoffGatewaySelection() {
    _gateway = null;
    _gatewayFailed = false;
    _client.lnSelectAnyGateway().then(
      (g) {
        if (mounted) setState(() => _gateway = g);
      },
      onError: (_) {
        if (mounted) setState(() => _gatewayFailed = true);
      },
    );
  }

  Future<void> _handleConfirm(int amountSats) async {
    final gateway = _gateway;
    if (gateway == null) throw 'Querying network fee…';

    final invoice = await lnurlResolve(
      payResponse: widget.payResponse,
      amountSats: amountSats,
    );

    if (!mounted) return;

    await requireBiometricAuth(context);

    await _client.lnSend(gateway: gateway, invoice: invoice);

    if (!mounted) return;

    Navigator.of(context).pop();
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

  void _handleShare() {
    SharePlus.instance.share(ShareParams(text: widget.lnurl.encode()));
  }

  Widget _buildFeePreview() {
    if (_gatewayFailed) return const FeePreview.error();
    final gateway = _gateway;
    if (gateway == null) return const FeePreview.loading();
    return FeePreview.value(
      gateway.gatewayFeeForAmount(amountSats: _amountSats),
    );
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
            )
          else
            IconButton(
              icon: const Icon(PhosphorIconsRegular.copy, size: smallIconSize),
              onPressed: _handleShare,
            ),
        ],
      ),
      body: SafeArea(
        maintainBottomViewPadding: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: FederationChip(
                clientFactory: widget.clientFactory,
                client: _client,
                onChanged: (next) {
                  setState(() {
                    _client = next;
                    _kickoffGatewaySelection();
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildFeePreview(),
            ),
            Expanded(
              child: AmountEntryWidget(
                key: ValueKey(_client.federationId()),
                client: _client,
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
