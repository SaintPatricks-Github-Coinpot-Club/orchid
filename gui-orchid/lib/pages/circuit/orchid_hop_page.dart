import 'dart:async';

import 'package:badges/badges.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orchid/api/orchid_budget_api.dart';
import 'package:orchid/api/orchid_crypto.dart';
import 'package:orchid/api/orchid_eth/v0/orchid_market_v0.dart';
import 'package:orchid/api/orchid_eth/v0/orchid_eth_v0.dart';
import 'package:orchid/api/orchid_log_api.dart';
import 'package:orchid/api/orchid_urls.dart';
import 'package:orchid/api/pricing/orchid_pricing_v0.dart';
import 'package:orchid/api/orchid_eth/v0/orchid_contract_v0.dart';
import 'package:orchid/api/preferences/user_preferences.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:orchid/common/scan_paste_account.dart';
import 'package:orchid/common/account_chart.dart';
import 'package:orchid/common/app_buttons.dart';
import 'package:orchid/common/app_text_field.dart';
import 'package:orchid/common/app_dialogs.dart';
import 'package:orchid/common/formatting.dart';
import 'package:orchid/common/instructions_view.dart';
import 'package:orchid/common/link_text.dart';
import 'package:orchid/common/screen_orientation.dart';
import 'package:orchid/common/tap_clears_focus.dart';
import 'package:orchid/common/titled_page_base.dart';
import 'package:orchid/pages/account_manager/account_manager_page.dart';
import 'package:orchid/util/units.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:styled_text/styled_text.dart';
import '../../common/app_colors.dart';
import '../../common/app_sizes.dart';
import '../../common/app_text.dart';
import '../app_routes.dart';
import 'curator_page.dart';
import 'funder_selection.dart';
import 'hop_editor.dart';
import 'key_selection.dart';
import 'model/circuit_hop.dart';
import 'model/orchid_hop.dart';
import 'package:intl/intl.dart';

/// Create / edit / view an Orchid Hop
class OrchidHopPage extends HopEditor<OrchidHop> {
  // The OrchidHopEditor operates in a "settings"-like fashion and allows
  // editing certain elements of the hop even when in "View" mode.  This flag
  // disables these features.
  bool disabled = false;

  OrchidHopPage(
      {@required editableHop, mode = HopEditorMode.View, onAddFlowComplete})
      : super(
            editableHop: editableHop,
            mode: mode,
            onAddFlowComplete: onAddFlowComplete);

  @override
  _OrchidHopPageState createState() => _OrchidHopPageState();
}

class _OrchidHopPageState extends State<OrchidHopPage> {
  var _pastedFunderField = TextEditingController();
  var _curatorField = TextEditingController();
  var _importKeyField = TextEditingController();
  KeySelectionItem _initialSelectedKeyItem;
  KeySelectionItem _selectedKeyItem;
  FunderSelectionItem _initialSelectedFunderItem;
  FunderSelectionItem _selectedFunderItem;

  bool _showBalance = false;
  OXTLotteryPot _lotteryPot; // initially null
  MarketConditionsV0 _marketConditions;
  List<OrchidUpdateTransactionV0> _transactions;
  DateTime _lotteryPotLastUpdate;
  Timer _balanceTimer;
  bool _balancePollInProgress = false;
  bool _showMarketStatsAlert = false;

  @override
  void initState() {
    super.initState();
    // Disable rotation until we update the screen design
    ScreenOrientation.portrait();
    initStateAsync();
  }

  void initStateAsync() async {
    // If the hop is empty initialize it to defaults now.
    if (_hop() == null) {
      widget.editableHop.update(OrchidHop.from(_hop(),
          curator: await UserPreferences().getDefaultCurator() ??
              OrchidHop.appDefaultCurator));
    }

    // Init the UI from the supplied hop
    setState(() {
      OrchidHop hop = _hop();
      _curatorField.text = hop?.curator;

      _initialSelectedKeyItem =
          hop?.keyRef != null ? KeySelectionItem(keyRef: hop.keyRef) : null;

      _initialSelectedFunderItem =
          hop?.funder != null ? FunderSelectionItem(funder: hop.funder) : null;

      _selectedKeyItem = _initialSelectedKeyItem;
    });

    if (widget.editable()) {
      _pastedFunderField.addListener(_textFieldChanged);
      _importKeyField.addListener(_textFieldChanged);
    }

    // init balance and account details polling
    if (widget.readOnly() && await UserPreferences().getQueryBalances()) {
      setState(() {
        _showBalance = true;
      });
      _balanceTimer = Timer.periodic(Duration(seconds: 10), (_) {
        _pollBalanceAndAccountDetails();
      });
      _pollBalanceAndAccountDetails(); // kick one off immediately
    }
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _updateHop();
  }

  @override
  Widget build(BuildContext context) {
    var isValid = _funderValid() && _keyRefValid();
    return TapClearsFocus(
      child: TitledPage(
        title: s.orchidHop,
        actions: widget.mode == HopEditorMode.Create
            ? [widget.buildSaveButton(context, _onSave, isValid: isValid)]
            : [],
        child: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 500),
                  child: _buildContent()),
            ),
          ),
        ),
        decoration: BoxDecoration(),
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.mode) {
      case HopEditorMode.Create:
        return _buildCreateModeContent();
      case HopEditorMode.Edit:
      case HopEditorMode.View:
        return _buildViewOrEditModeContent();
      default:
        throw Error();
    }
  }

  Widget _buildCreateModeContent() {
    var bodyStyle = TextStyle(fontSize: 16, color: Color(0xff504960));
    // var linkStyle = AppText.linkStyle.copyWith(fontSize: 15);

    var text = StyledText(
      style: bodyStyle,
      newLineAsBreaks: true,
      text: s.chooseAnOrchidAccountToUseWithThisHop +
          '  ' +
          s.ifYouDontSeeYourAccountBelowYouCanUse,
      tags: {
        // 'link': linkStyle.link(OrchidUrls.partsOfOrchidAccount),
      },
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30.0),
      child: Column(
        // crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          pady(36),
          InstructionsView(
            image: Image.asset('assets/images/group12.png'),
            title: s.selectAnOrchidAccount,
          ),
          text,
          pady(16),
          LinkText(
            s.takeMeToTheAccountManager,
            style: AppText.linkStyle.copyWith(fontStyle: FontStyle.italic),
            onTapped: () {
              Navigator.of(context).push(new MaterialPageRoute(
                  builder: (context) => AccountManagerPage()));
            },
          ),
          pady(24),
          divider(),
          pady(24),
          _buildAccountDetails(),
          pady(96),
        ],
      ),
    );
  }

  Widget _buildViewOrEditModeContent() {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 24, bottom: 24, right: 16),
      child: Column(
        children: <Widget>[
          if (AppSize(context).tallerThan(AppSize.iphone_12_max)) pady(64),
          _buildSection(
              title: s.account, child: _buildAccountDetails(), onDetail: null),
          pady(16),
          divider(),
          pady(24),
          _buildSection(
              title: s.curation,
              child: _buildCuration(),
              onDetail: !widget.disabled ? _editCurator : null),
          pady(36),
        ],
      ),
    );
  }

  Widget _buildSection({String title, Widget child, VoidCallback onDetail}) {
    return Column(
      children: <Widget>[
        Text(title,
            style: AppText.dialogTitle
                .copyWith(color: Colors.black, fontSize: 22)),
        pady(8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: child),
              Visibility(
                visible: onDetail != null,
                child: Container(
                  //width: 60,
                  //color: Colors.red,
                  child: FlatButton(
                      child: Icon(Icons.chevron_right), onPressed: onDetail),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountDetails() {
    return Row(
      children: [
        Flexible(
          child: Column(
            // mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              // Balance and Deposit
              Visibility(
                visible: _showBalance,
                child: _buildAccountBalanceAndChart(),
              ),

              // Signer
              if (widget.readOnly()) pady(16),
              _buildSelectSignerField(),

              pady(16),

              // Funder
              if (_selectedKeyItem != null) _buildSelectFunderField(),

              // Market Stats
              if (widget.mode == HopEditorMode.View) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: _buildMarketStatsLink(),
                ),
              ],

              if (widget.readOnly())
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _buildShareAccountButton(),
                    ],
                  ),
                ),

              if (widget.readOnly() && _transactions != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: divider(),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildTransactionList(),
                )
              ]
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionList() {
    const String bullet = "• ";
    var txRows = _transactions.map((utx) {
      return Row(
        children: [
          Text(bullet, style: TextStyle(fontSize: 20)),
          Container(
              width: 40,
              child: Text(utx.tx.type.toString().split('.')[1] + ':')),
          padx(16),
          Container(
            width: 150,
            child: Text(s.balance +
                ': ' +
                formatCurrency(utx.update.endBalance.floatValue,
                    suffix: 'OXT')),
          ),
          padx(8),
          Flexible(child: Text(utx.tx.transactionHash.substring(0, 8) + '...'))
        ],
      );
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.transactions, style: AppText.textLabelStyle),
      pady(8),
      ...txRows,
    ]);
  }

  // Build the signer key entry dropdown selector
  Column _buildSelectSignerField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(s.orchidIdentitySignerKey + ':',
            style: AppText.textLabelStyle.copyWith(
                fontSize: 16,
                color: _keyRefValid()
                    ? AppColors.neutral_1
                    : AppColors.neutral_3)),
        pady(8),
        Row(
          children: <Widget>[
            Expanded(
              child: KeySelectionDropdown(
                  key: ValueKey(_initialSelectedKeyItem.toString()),
                  enabled: widget.editable(),
                  initialSelection: _initialSelectedKeyItem,
                  onSelection: _onKeySelected),
            ),
            // Copy key button
            Visibility(
              visible: widget.readOnly(),
              child: RoundedRectButton(
                  backgroundColor: Colors.deepPurple,
                  textColor: Colors.white,
                  text: s.copy,
                  onPressed: _onCopyButton),
            ),
          ],
        ),

        // Show the import key field if the user has selected the option
        Visibility(
          visible: widget.editable() &&
              _selectedKeyItem?.option == KeySelectionDropdown.importKeyOption,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _buildImportKey(),
          ),
        )
      ],
    );
  }

  // Build the import key field
  Widget _buildImportKey() {
    return AppTextField(
        hintText: '0x...',
        margin: EdgeInsets.zero,
        controller: _importKeyField,
        trailing: FlatButton(
            color: Colors.transparent,
            padding: EdgeInsets.zero,
            child: Text(s.paste, style: AppText.pasteButtonStyle),
            onPressed: _onPasteImportedKey));
  }

  /// Select a funder account address for the selected signer identity
  Column _buildSelectFunderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(s.funderAccount + ':',
            style: AppText.textLabelStyle.copyWith(
                fontSize: 16,
                color: _funderValid()
                    ? AppColors.neutral_1
                    : AppColors.neutral_3)),
        pady(widget.readOnly() ? 4 : 8),

        Row(
          children: <Widget>[
            Expanded(
              child: FunderSelectionDropdown(
                  signer: _selectedKeyItem?.keyRef,
                  key: ValueKey(_selectedKeyItem?.toString() ??
                      _initialSelectedKeyItem.toString()),
                  enabled: widget.editable(),
                  initialSelection:
                      _selectedFunderItem ?? _initialSelectedFunderItem,
                  onSelection: _onFunderSelected),
            ),

            /*
            // Copy key button
            Visibility(
              visible: widget.readOnly(),
              child: RoundedRectButton(
                  backgroundColor: Colors.deepPurple,
                  textColor: Colors.white,
                  text: s.copy,
                  onPressed: _onCopyButton),
            ),
             */
          ],
        ),

        // Show the paste funder field if the user has selected the option
        Visibility(
          visible: widget.editable() &&
              _selectedFunderItem?.option ==
                  FunderSelectionDropdown.pasteKeyOption,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _buildPasteFunderField(),
          ),
        )
      ],
    );
  }

  Column _buildPasteFunderField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        /*
        Text("Funder Account" ':',
            style: AppText.textLabelStyle.copyWith(
                fontSize: 16,
                color: _funderValid()
                    ? AppColors.neutral_1
                    : AppColors.neutral_3)),
        pady(widget.readOnly() ? 4 : 8),
         */
        AppTextField(
            hintText: '0x...',
            margin: EdgeInsets.zero,
            controller: _pastedFunderField,
            readOnly: widget.readOnly(),
            enabled: widget.editable(),
            trailing: widget.editable()
                ? FlatButton(
                    color: Colors.transparent,
                    padding: EdgeInsets.zero,
                    child: Text(s.paste, style: AppText.pasteButtonStyle),
                    onPressed: _onPasteFunderAddress)
                : null)
      ],
    );
  }

  void _onPasteFunderAddress() async {
    ClipboardData data = await Clipboard.getData('text/plain');
    _pastedFunderField.text = data.text;
  }

  void _onPasteImportedKey() async {
    ClipboardData data = await Clipboard.getData('text/plain');
    _importKeyField.text = data.text;
  }

  Widget _buildAccountBalanceAndChart() {
    return Row(
      children: [
        Flexible(child: _buildAccountBalance()),
        Expanded(
          child: AccountChart(
              lotteryPot: _lotteryPot,
              efficiency: _marketConditions?.efficiency,
              transactions: _transactions),
        )
      ],
    );
  }

  Widget _buildAccountBalance() {
    const color = Color(0xff3a3149);
    const valueStyle = TextStyle(
        color: color,
        fontSize: 15.0,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.24,
        fontFamily: 'SFProText-Regular',
        height: 20.0 / 15.0);

    var balanceText = _lotteryPot?.balance != null
        ? NumberFormat('#0.0###').format(_lotteryPot?.balance?.floatValue) +
            " ${s.oxt}"
        : "...";
    var depositText = _lotteryPot?.deposit != null
        ? NumberFormat('#0.0###').format(_lotteryPot?.deposit?.floatValue) +
            " ${s.oxt}"
        : '...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Balance
        Text(s.amount + ':',
            style: AppText.textLabelStyle
                .copyWith(fontSize: 20, color: AppColors.neutral_1)),
        pady(4),
        Padding(
          padding: EdgeInsets.only(top: 10, bottom: 8, left: 16),
          child:
              Text(balanceText, textAlign: TextAlign.left, style: valueStyle),
        ),
        pady(16),
        // Deposit
        Text(s.deposit + ':',
            style: AppText.textLabelStyle
                .copyWith(fontSize: 20, color: AppColors.neutral_1)),
        pady(4),
        Padding(
          padding: EdgeInsets.only(top: 10, bottom: 8, left: 16),
          child:
              Text(depositText, textAlign: TextAlign.left, style: valueStyle),
        ),
      ],
    );
  }

  Widget _buildCuration() {
    return Row(
      children: <Widget>[
        Expanded(
            child: AppTextField(
          controller: _curatorField,
          padding: EdgeInsets.zero,
          readOnly: true,
          enabled: false,
        ))
      ],
    );
  }

  Widget _buildMarketStatsLink() {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _showMarketStats,
        child: Row(
          children: [
            LinkText(
              s.marketStats,
              style: AppText.linkStyle.copyWith(fontSize: 13),
              onTapped: _showMarketStats,
            ),
            padx(8),
            Badge(
              showBadge: _showMarketStatsAlert,
              position: BadgePosition.topEnd(top: -6, end: -28),
              badgeContent: Text('!',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              padding: EdgeInsets.all(8),
              toAnimate: false,
            )
          ],
        ),
      ),
    );
  }

  Future<void> _showMarketStats() async {
    if (_lotteryPot == null) {
      return;
    }

    var marketConditions = await MarketConditionsV0.forPot(_lotteryPot);
    PricingV0 pricing = await OrchidPricingAPIV0().getPricing();
    GWEI gasPrice = await OrchidEthereumV0().getGasPrice();
    bool gasPriceHigh = gasPrice.value >= 50.0; // TODO
    /*
    // data
    if (_lotteryPot == null || pricing == null || gasPrice == null) {
      return;
    }

    // calculation
    ETH gasCostToRedeem =
        (gasPrice * OrchidPricingAPI.gasCostToRedeemTicket).toEth();
    OXT oxtCostToRedeem = pricing.ethToOxt(gasCostToRedeem);
    OXT maxFaceValue = OXT.min(_lotteryPot.balance, _lotteryPot.deposit / 2.0);
    bool balanceLimited =
        _lotteryPot.balance.value < _lotteryPot.deposit.value / 2.0;
     */

    // formatting
    var ethPriceText =
        formatCurrency(1.0 / pricing?.ethToUsdRate, suffix: 'USD');
    var oxtPriceText =
        formatCurrency(1.0 / pricing?.oxtToUsdRate, suffix: 'USD');
    var gasPriceText = formatCurrency(gasPrice.value, suffix: 'GWEI');
    String maxFaceValueText = formatCurrency(
        marketConditions.maxFaceValue?.floatValue,
        suffix: 'OXT');
    String costToRedeemText = formatCurrency(
        marketConditions.oxtCostToRedeem.floatValue,
        suffix: 'OXT');
    bool ticketUnderwater = marketConditions.oxtCostToRedeem.floatValue >=
        marketConditions.maxFaceValue.floatValue;

    String limitedByText = marketConditions.limitedByBalance
        ? s.yourMaxTicketValueIsCurrentlyLimitedByYourBalance +
            " ${formatCurrency(_lotteryPot.balance.floatValue, suffix: 'OXT')}.  " +
            s.considerAddingOxtToYourAccountBalance
        : s.yourMaxTicketValueIsCurrentlyLimitedByYourDeposit +
            " ${formatCurrency(_lotteryPot.deposit.floatValue, suffix: 'OXT')}.  " +
            s.considerAddingOxtToYourDepositOrMovingFundsFrom;

    String limitedByTitleText = marketConditions.limitedByBalance
        ? s.balanceTooLow
        : s.depositSizeTooSmall;

    return AppDialogs.showAppDialog(
        context: context,
        title: s.marketStats,
        body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.prices, style: TextStyle(fontWeight: FontWeight.bold)),
              pady(4),
              Text(s.ethPrice + " " + ethPriceText),
              Text(s.oxtPrice + " " + oxtPriceText),
              Text(s.gasPrice + " " + gasPriceText,
                  style: gasPriceHigh ? TextStyle(color: Colors.red) : null),

              pady(16),
              Text(s.ticketValue,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              pady(4),

              Text(s.maxFaceValue + " " + maxFaceValueText),

              Text(s.costToRedeem + " " + costToRedeemText,
                  style:
                      ticketUnderwater ? TextStyle(color: Colors.red) : null),

              // Problem description
              if (ticketUnderwater) ...[
                pady(16),
                Text(limitedByTitleText,
                    style: TextStyle(fontWeight: FontWeight.bold)),
                pady(8),
                Text(limitedByText,
                    style: TextStyle(fontStyle: FontStyle.italic)),
                pady(16),
                LinkText(s.viewTheDocsForHelpOnThisIssue,
                    style: AppText.linkStyle.copyWith(fontSize: 15),
                    url:
                        'https://docs.orchid.com/en/stable/accounts/#deposit-size-too-small')
              ]
            ]));
  }

  void _editCurator() async {
    var route = MaterialPageRoute(
        builder: (context) =>
            CuratorEditorPage(editableHop: widget.editableHop));
    await Navigator.push(context, route);
    _curatorField.text = _hop()?.curator;
  }

  void _onKeySelected(KeySelectionItem key) {
    setState(() {
      _selectedKeyItem = key;
      _selectedFunderItem = null;
      _pastedFunderField.text = null;
    });
    // clear the keyboard
    FocusScope.of(context).requestFocus(new FocusNode());
  }

  void _onFunderSelected(FunderSelectionItem funder) {
    setState(() {
      _selectedFunderItem = funder;
    });
    // clear the keyboard
    FocusScope.of(context).requestFocus(new FocusNode());
  }

  void _textFieldChanged() {
    setState(() {}); // Update validation
  }

  bool _keyRefValid() {
    // invalid selection
    if (_selectedKeyItem == null) {
      return false;
    }
    // key value selected
    if (_selectedKeyItem.keyRef != null) {
      return true;
    }
    return false;
  }

  bool _funderValid() {
    return (_selectedFunderItem != null &&
            _selectedFunderItem.option !=
                FunderSelectionDropdown.pasteKeyOption) ||
        _pastedFunderValid() ||
        widget.readOnly();
  }

  bool _pastedFunderValid() {
    try {
      EthereumAddress.parse(_pastedFunderField.text);
      return true;
    } catch (err) {
      return false;
    }
  }

  void _updateHop() {
    if (!widget.editable()) {
      return;
    }
    EthereumAddress funder;
    try {
      funder = _selectedFunderItem?.funder != null
          ? _selectedFunderItem.funder
          : EthereumAddress.from(_pastedFunderField.text);
    } catch (err) {
      funder = null; // don't update it
    }
    // The selected key ref may be null here in the case of the generate
    // or import options.  In those cases the key will be filled in upon save.
    widget.editableHop.update(OrchidHop.from(widget.editableHop.value?.hop,
        funder: funder, keyRef: _selectedKeyItem?.keyRef));
  }

  /// Copy the wallet address to the clipboard
  void _onCopyButton() async {
    StoredEthereumKey key = await _selectedKeyItem.keyRef.get();
    Clipboard.setData(ClipboardData(text: key.get().addressString));
  }

  // Participate in the save operation and then delegate to the on complete handler.
  void _onSave(CircuitHop result) async {
    // Pass on the updated hop
    widget.onAddFlowComplete(widget.editableHop.value.hop);
  }

  OrchidHop _hop() {
    return widget.editableHop.value?.hop;
  }

  Widget divider() {
    return Divider(
      color: Colors.black.withOpacity(0.5),
      height: 1.0,
    );
  }

  @override
  void dispose() {
    super.dispose();
    ScreenOrientation.reset();
    _pastedFunderField.removeListener(_textFieldChanged);
    _balanceTimer?.cancel();
  }

  void _pollBalanceAndAccountDetails() async {
    if (_balancePollInProgress) {
      return;
    }
    _balancePollInProgress = true;
    try {
      // funder and signer from the stored hop
      EthereumAddress funder = _hop()?.funder;
      StoredEthereumKey signerKey = await _hop()?.keyRef?.get();
      EthereumAddress signer =
          EthereumAddress.from(signerKey.get().addressString);

      // Fetch the pot balance
      OXTLotteryPot pot;
      MarketConditionsV0 marketConditions;
      List<OrchidUpdateTransactionV0> transactions;
      try {
        pot = await OrchidEthereumV0.getLotteryPot(funder, signer)
            .timeout(Duration(seconds: 60));
      } catch (err) {
        log('Error fetching lottery pot: $err');
        return;
      }
      try {
        marketConditions = await MarketConditionsV0.forPot(pot);
      } catch (err, stack) {
        log('Error fetching market conditions: $err\n$stack');
        return;
      }
      var ticketValue = await MarketConditionsV0.getMaxTicketValueV0(pot);
      try {
        transactions = await OrchidEthereumV0()
            .getUpdateTransactions(funder: funder, signer: signer);
      } catch (err) {
        log('Error fetching account update transactions: $err');
      }
      if (mounted) {
        setState(() {
          _lotteryPot = pot;
          _marketConditions = marketConditions;
          _showMarketStatsAlert = ticketValue.lteZero();
          _transactions = transactions;
        });
      }
      _lotteryPotLastUpdate = DateTime.now();
    } catch (err, stack) {
      log("Can't fetch balance: $err, $stack");

      // Allow a stale balance for a period of time.
      if (_lotteryPotLastUpdate != null &&
          _lotteryPotLastUpdate.difference(DateTime.now()) >
              Duration(hours: 1)) {
        if (mounted) {
          setState(() {
            _lotteryPot = null; // no balance available
          });
        }
      }
    } finally {
      _balancePollInProgress = false;
    }
  }

  Widget _buildShareAccountButton() {
    return TitleIconButton(
        text: s.shareOrchidAccount,
        spacing: 24,
        trailing: Image.asset('assets/images/scan.png', color: Colors.white),
        textColor: Colors.white,
        backgroundColor: Colors.deepPurple,
        onPressed: _exportAccount);
  }

  void _exportAccount() async {
    var config = await _hop().accountConfigString();
    var title = S.of(context).myOrchidAccount + ':';
    showExportAccountDialog(context: context, title: title, config: config);
  }

  static Future<void> showExportAccountDialog({
    BuildContext context,
    String title,
    String config,
  }) async {
    return AppDialogs.showAppDialog(
        context: context,
        title: title,
        body: Container(
          width: 250,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: QrImage(
                  data: config,
                  version: QrVersions.auto,
                  size: 250.0,
                ),
              ),
              CopyTextButton(copyText: config)
            ],
          ),
        ));
  }

  S get s {
    return S.of(context);
  }
}
