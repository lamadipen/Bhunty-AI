import 'package:flutter/material.dart';

import 'ai/assistant_service.dart';
import 'app_scope.dart';
import 'data/shop_store.dart';
import 'photos/photo_reader.dart';
import 'photos/photo_source.dart';
import 'screens/assistant_screen.dart';
import 'screens/home_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/sell_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/udharo_screen.dart';
import 'theme/theme.dart';

abstract final class Routes {
  static const home = '/';
  static const sell = '/sell';
  static const stock = '/stock';
  static const udharo = '/udharo';
  static const assistant = '/assistant';
  static const reports = '/reports';
}

/// Phone layout everywhere; on tablets and the web it stays phone-width, centred.
Widget phoneFrame(BuildContext context, Widget? child) => ColoredBox(
  color: const Color(0xFFDDE4DF),
  child: Center(
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
  ),
);

/// A bare app shell for screens shown before a shop is open (login, loading).
class ShellApp extends StatelessWidget {
  const ShellApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bhunte AI',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    builder: phoneFrame,
    home: home,
  );
}

class BhunteApp extends StatelessWidget {
  const BhunteApp({
    super.key,
    required this.store,
    required this.assistant,
    required this.scanner,
    this.photoReader = const NoPhotoReader(),
    this.photoSource = const DevicePhotoSource(),
    this.signOut,
  });

  final ShopStore store;
  final AssistantService assistant;
  final BarcodeScanner scanner;
  final PhotoReader photoReader;
  final PhotoSource photoSource;

  /// Set when signed in with Firebase; null in the demo.
  final Future<void> Function()? signOut;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      assistant: assistant,
      scanner: scanner,
      photoReader: photoReader,
      photoSource: photoSource,
      signOut: signOut,
      child: MaterialApp(
        title: 'Bhunte AI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: phoneFrame,
        initialRoute: Routes.home,
        routes: {
          Routes.home: (_) => const HomeScreen(),
          Routes.sell: (_) => const SellScreen(),
          Routes.stock: (_) => const StockScreen(),
          Routes.udharo: (_) => const UdharoScreen(),
          Routes.assistant: (_) => const AssistantScreen(),
          Routes.reports: (_) => const ReportsScreen(),
        },
      ),
    );
  }
}
