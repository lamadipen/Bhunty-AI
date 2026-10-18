import 'package:flutter/material.dart';

import 'ai/assistant_service.dart';
import 'app_scope.dart';
import 'data/shop_store.dart';
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

class BhunteApp extends StatelessWidget {
  const BhunteApp({super.key, required this.store, required this.assistant, required this.scanner});

  final ShopStore store;
  final AssistantService assistant;
  final BarcodeScanner scanner;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      assistant: assistant,
      scanner: scanner,
      child: MaterialApp(
        title: 'Bhunte AI',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Phone layout everywhere; on tablets and the web it stays phone-width, centred.
        builder: (context, child) => ColoredBox(
          color: const Color(0xFFDDE4DF),
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
          ),
        ),
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
