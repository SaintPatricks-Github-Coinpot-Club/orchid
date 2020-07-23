import 'dart:async';
import 'package:flutter/material.dart';
import 'package:orchid/api/preferences/user_preferences.dart';
import 'package:orchid/pages/circuit/circuit_page.dart';
import 'package:orchid/pages/circuit/hop_editor.dart';
import 'package:orchid/pages/circuit/model/circuit.dart';
import 'package:orchid/pages/circuit/model/circuit_hop.dart';
import 'package:orchid/pages/circuit/model/orchid_hop.dart';
import 'package:orchid/pages/circuit/orchid_hop_page.dart';
import 'package:orchid/pages/common/dialogs.dart';
import 'package:orchid/pages/common/formatting.dart';
import 'package:orchid/pages/common/titled_page_base.dart';
import 'package:orchid/generated/l10n.dart';

import '../app_colors.dart';
import '../app_text.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({Key key}) : super(key: key);

  @override
  _AccountsPageState createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  List<UniqueHop> _recentlyDeleted = [];

  @override
  void initState() {
    super.initState();
    initStateAsync();
  }

  void initStateAsync() async {
    _recentlyDeleted = await _getRecentlyDeletedHops();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return TitledPage(
      decoration: BoxDecoration(color: Colors.transparent),
      title: s.deletedHops,
      child: buildPage(context),
      lightTheme: true,
    );
  }

  Widget buildPage(BuildContext context) {
    List<Widget> list = [];
    if (_recentlyDeleted.isNotEmpty) {
      //list.add(titleTile(s.recentlyDeleted));
      list.add(pady(16));
      list.add(_buildInstructions());
      list.add(pady(32));
      list.addAll((_recentlyDeleted ?? []).map((hop) {
        return _buildInactiveHopTile(hop);
      }).toList());
    } else {
      list.add(Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Text(
          s.noRecentlyDeletedHops,
          textAlign: TextAlign.center,
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ));
    }
    return ListView(children: list);
  }

  Widget titleTile(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20),
      child: Text(
        text,
        style: TextStyle(fontSize: 20),
      ),
    );
  }

  Dismissible _buildInactiveHopTile(UniqueHop uniqueHop) {
    return Dismissible(
      key: Key(uniqueHop.key.toString()),
      background: CircuitPageState.buildDismissableBackground(context),
      confirmDismiss: _confirmDeleteHop,
      onDismissed: (direction) {
        _deleteHop(uniqueHop);
      },
      child: _buildHopTile(uniqueHop, activeHop: false),
    );
  }

  Widget _buildHopTile(UniqueHop uniqueHop, {bool activeHop = true}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: CircuitPageState.buildHopTile(
          context: context,
          onTap: () {
            _viewHop(uniqueHop);
          },
          uniqueHop: uniqueHop,
          bgColor: activeHop
              ? AppColors.purple_3.withOpacity(0.8)
              : Colors.grey[500],
          showAlertBadge: false),
    );
  }

  void _viewHop(UniqueHop uniqueHop, {bool animated = true}) async {
    EditableHop editableHop = EditableHop(uniqueHop);
    HopEditor editor = editableHop.editor();
    //  Turn off all editable features such as curation.
    if (editor is OrchidHopPage) {
      editor.disabled = true;
    }
    await editor.show(context, animated: animated);
  }

  Future<bool> _confirmDeleteHop(dismissDirection) async {
    var result = await Dialogs.showConfirmationDialog(
      context: context,
      title: s.confirmDelete,
      body: s.deletingThisHopWillRemoveItsConfiguredOrPurchasedAccount +
          "  " +
          s.ifYouPlanToReuseTheAccountLaterYouShould,
    );
    return result;
  }

  // Callback for swipe to delete
  void _deleteHop(UniqueHop uniqueHop) async {
    var index = _recentlyDeleted.indexOf(uniqueHop);
    setState(() {
      _recentlyDeleted.removeAt(index);
    });
    UserPreferences().setRecentlyDeleted(
      Hops(_recentlyDeleted.map((h) {
        return h.hop;
      }).toList()),
    );
  }

  // e.g. recently deleted
  Future<List<UniqueHop>> _getRecentlyDeletedHops() async {
    var recentlyDeletedHops = await UserPreferences().getRecentlyDeleted();
    var keyBase = DateTime.now().millisecondsSinceEpoch;
    var hops = recentlyDeletedHops.hops.where((hop) {
      return hop is OrchidHop;
    }).toList();
    return UniqueHop.wrap(hops, keyBase);
  }

  S get s {
    return S.of(context);
  }

  Widget _buildInstructions() {
    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 32),
      child: Text(
          "To restore a deleted hop:" +
              "\n\n" +
              "1. Click the hop below then click ‘Share Orchid Account’ and hit ‘Copy’." +
              "\n" +
              "2. Return to the ‘Manage Profile’ screen, click ‘New Hop’ then ‘Link Orchid Account’ and ‘Paste’." +
              "\n\n" +
              "To permanently delete a hop from the list below, swipe left on it.",
          style: TextStyle(fontStyle: FontStyle.italic)),
    );
  }
}
