import 'package:flutter/widgets.dart';

import 'ai/assistant_service.dart';
import 'data/shop_store.dart';

/// Hands the store and services to every screen. Widgets that read
/// `context.store` in build rebuild when the store changes.
class AppScope extends InheritedNotifier<ShopStore> {
  const AppScope({
    super.key,
    required ShopStore store,
    required this.assistant,
    required this.scanner,
    this.signOut,
    required super.child,
  }) : super(notifier: store);

  final AssistantService assistant;
  final BarcodeScanner scanner;
  final Future<void> Function()? signOut;

  static AppScope _of(BuildContext context, {required bool listen}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!;
  }
}

extension AppScopeContext on BuildContext {
  /// Use in build: rebuilds this widget when the store changes.
  ShopStore get store => AppScope._of(this, listen: true).notifier!;

  /// Use in callbacks.
  ShopStore get readStore => AppScope._of(this, listen: false).notifier!;

  AssistantService get assistant => AppScope._of(this, listen: false).assistant;
  BarcodeScanner get scanner => AppScope._of(this, listen: false).scanner;

  /// Null in the demo (nobody is signed in).
  Future<void> Function()? get signOut => AppScope._of(this, listen: false).signOut;
}
