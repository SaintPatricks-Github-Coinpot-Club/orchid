import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:orchid/pages/app_routes.dart';

void main() {
  // Force portrait orientation
  // Note: There is a bug causing this to fail on iPad, so we have locked
  // Note: the orientation in the main plist:
  // Note: https://github.com/flutter/flutter/issues/27235
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((_) {
    runApp(OrchidApp());
  });
}

class OrchidApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Orchid',
        debugShowCheckedModeBanner: false,

        // Theme (overridden for most widgets)
        theme: ThemeData(
          primarySwatch: Colors.deepPurple,
        ),

        // Routing
        initialRoute: '/',
        routes: AppRoutes.routes);
  }
}
