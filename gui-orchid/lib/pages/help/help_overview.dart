import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:orchid/api/orchid_docs.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:orchid/common/titled_page_base.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:orchid/orchid/orchid_colors.dart';
import 'package:orchid/orchid/orchid_text.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpOverviewPage extends StatefulWidget {
  @override
  _HelpOverviewPageState createState() => _HelpOverviewPageState();
}

class _HelpOverviewPageState extends State<HelpOverviewPage> {
  String _helpText;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (_helpText == null) {
      _helpText = "";
      OrchidDocs.helpOverview(context).then((text) {
        setState(() {
          _helpText = text;
        });
      });
    }

    String title = s.orchidOverview;
    return TitledPage(title: title, child: buildPage(context));
  }

  Widget buildPage(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Scrollbar(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[html(_helpText)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // flutter_hmtl supports a subset of html: https://pub.dev/packages/flutter_html
  Widget html(String html) {
    return Html(
      data: html,
      defaultTextStyle: OrchidText.body2,
      linkStyle: OrchidText.body2.copyWith(color: OrchidColors.purple_bright),
      onLinkTap: (url) {
        launch(url, forceSafariVC: false);
      },
      onImageTap: (src) {},
      // This is our css :)
      customTextStyle: (dom.Node node, TextStyle baseStyle) {
        if (node is dom.Element) {
          switch (node.localName) {
            case 'h1': return baseStyle.merge(OrchidText.title.copyWith(fontSize: 24).copyWith(height: 1.0));
            case 'h2': return baseStyle.merge(OrchidText.title.copyWith(height: 1.0));
          }
        }
        return baseStyle;
      },
    );
  }

  S get s {
    return S.of(context);
  }
}
