import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/material.dart';
import 'package:pico/bridge_generated.dart/factory.dart';
import 'package:pico/drawers/confirm_currency_drawer.dart';
import 'package:pico/bridge_generated.dart/currency.dart';
import 'package:pico/utils/styles.dart';
import 'package:pico/widgets/grouped_list_widget.dart';
import 'package:pico/widgets/search_field_widget.dart';

class SelectCurrencyScreen extends StatefulWidget {
  final PicoClientFactory clientFactory;

  const SelectCurrencyScreen({super.key, required this.clientFactory});

  @override
  State<SelectCurrencyScreen> createState() => _SelectCurrencyScreenState();
}

class _SelectCurrencyScreenState extends State<SelectCurrencyScreen> {
  String _query = '';

  List<FiatCurrency> get _filtered =>
      listFiatCurrencies()
          .where(
            (c) =>
                c.code.toLowerCase().contains(_query.toLowerCase()) ||
                c.name.toLowerCase().contains(_query.toLowerCase()),
          )
          .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Currency')),
      body: GroupedList<FiatCurrency>(
        header: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SearchField(
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        items: _filtered,
        groupKey: (currency) => currency.code[0],
        itemBuilder:
            (context, currency) => ListTile(
              contentPadding: listTilePadding,
              leading: PhosphorIcon(
                PhosphorIconsRegular.currencyDollar,
                color: Theme.of(context).colorScheme.primary,
                size: mediumIconSize,
              ),
              title: Text(currency.name, style: mediumStyle),
              onTap: () {
                ConfirmCurrencyDrawer.show(
                  context,
                  currency: currency,
                  clientFactory: widget.clientFactory,
                );
              },
            ),
      ),
    );
  }
}
