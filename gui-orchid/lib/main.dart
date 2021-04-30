import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:orchid/api/purchase/orchid_purchase.dart';
import 'package:orchid/pages/orchid_app.dart';
import 'package:window_size/window_size.dart';
import 'api/configuration/orchid_user_config/orchid_user_config.dart';
import 'api/monitoring/orchid_status.dart';
import 'api/orchid_api.dart';
import 'api/orchid_log_api.dart';
import 'api/orchid_platform.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OrchidAPI().logger().write("App Startup");
  OrchidStatus().beginPollingStatus();
  OrchidAPI().applicationReady();
  OrchidPlatform.pretendToBeAndroid =
      (await OrchidUserConfig().getUserConfigJS())
          .evalBoolDefault('isAndroid', false);
  if (OrchidPlatform.pretendToBeAndroid) {
    log("pretendToBeAndroid = ${OrchidPlatform.pretendToBeAndroid}");
  }
  if (Platform.isIOS || Platform.isMacOS || Platform.isAndroid) {
    OrchidPurchaseAPI().initStoreListener();
  }
  var languageOverride = (await OrchidUserConfig().getUserConfigJS())
      .evalStringDefault("lang", null);
  if (languageOverride != null &&
      OrchidPlatform.hasLanguage(languageOverride)) {
    OrchidPlatform.languageOverride = languageOverride;
  }
  if (OrchidPlatform.isDesktop) {
    print("main: Setting window size");
    setWindowFrame(Rect.fromLTWH(100, 100, 375, 650));
    setWindowMinSize(Size(216, 250));
  }
  runApp(OrchidApp());
}
