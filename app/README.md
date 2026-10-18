# Bhunte AI — Flutter app

Android · iOS · Web. Runs entirely on demo data in memory; Firebase and the AI backend are stubbed behind interfaces.

```bash
flutter pub get
flutter run            # pick a device, or -d chrome
flutter test
flutter analyze
dart run flutter_launcher_icons   # after changing ../brand/ icons
```

## Screens (from the design prototype)

| Prototype screen | File |
|---|---|
| 1 · Home (गृह) | `lib/screens/home_screen.dart` |
| 2 · Sell (बेच्नुस्) + payment sheets + done | `lib/screens/sell_screen.dart`, `lib/screens/payment_sheets.dart` |
| 3 · Add stock from bill photo | `lib/screens/stock_screen.dart` |
| 4 · Udharo (credit) | `lib/screens/udharo_screen.dart` |
| 5 · Talk to Bhunte | `lib/screens/assistant_screen.dart` |
| Reports (हिसाब tile; not in the prototype) | `lib/screens/reports_screen.dart` |

## Structure

```
lib/
  core/        money (int paisa), qty (int milli-units), cash tenders, Nepal time, keypad input
  data/        models, ShopStore (all reads/writes), ProposedAction, demo data
  ai/          AssistantService + BarcodeScanner interfaces, demo implementations, code-built answers
  widgets/     header, big buttons, keypad, sheets, toast
  theme/       colours and Mukta font
assets/fonts/  Mukta (bundled so Devanagari works offline; OFL licence included)
```

## Rules the code follows

- **Money is `int` paisa, quantity is `int` milli-units.** 1.5 kg = 1500. See `core/money.dart`, `core/qty.dart`.
- **Only `ShopStore` changes data.** AI output is an `AssistantIntent`; actions are shown on a confirm card and only `ShopStore.apply()` commits them after a tap. `ShopStore.validate()` runs the same checks the Cloud Function will.
- **Chat answers are built in code** (`ai/answers.dart`) from store data; the model would only pick the metric.
- **Today is Nepal time** (UTC+5:45) whatever the device timezone.
- **No ✓/✕ characters in text** — Mukta has no glyphs for them and there is no offline fallback font. Use `Icons.check_rounded` / `Icons.close_rounded` (e.g. `BigButton(trailingIcon: …)`).

## Next steps

1. Firebase project + `flutterfire configure`; phone OTP login.
2. `FirestoreShopStore` with the same methods as `ShopStore`, each write as one batched write (see `docs/architecture.md`).
3. Replace `DemoBarcodeScanner` with ML Kit (`mobile_scanner`), `DemoAssistantService` with a Cloud Functions client.
