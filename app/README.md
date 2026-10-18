# Bhunte AI — Flutter app

Android · iOS · Web. Two modes:

- **demo** (default): in-memory demo shop, no login. Nothing is saved.
- **firebase**: phone OTP login; the shop is saved in Firestore with offline persistence.

The AI backend is still the scripted demo in both modes (Phase 2).

```bash
flutter pub get
flutter run                                   # demo
flutter run --dart-define=BACKEND=firebase    # Firebase (after setup below)
flutter test
flutter analyze
dart run flutter_launcher_icons               # after changing ../brand/ icons
```

## Firebase setup (one time, needs your Google account)

1. Create a Firebase project in the console. Enable **Authentication → Phone** and create a **Firestore** database (region close to Nepal, e.g. `asia-south1`).
2. In `app/`: `flutterfire configure` — pick the project and Android, iOS, Web. This replaces the placeholder `lib/firebase_options.dart` and adds the platform config files.
3. Android: add your debug and release SHA-1/SHA-256 in the Firebase console (phone auth needs them). iOS: enable push/APNs or reCAPTCHA fallback as Firebase's phone-auth guide says.
4. From the repo root: `firebase deploy --only firestore:rules --project <your-project>`.
5. For testing without real SMS, add test phone numbers under Authentication → Phone.

On first sign-in the app creates `shops/{uid}` and seeds the 8 sample products so the tap grid isn't empty (catalog editing comes next).

Rules tests (no project needed, runs the local emulator; needs Java 11+ and the Firebase CLI):

```bash
cd ../rules-test && npm install && npm test
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
  data/        models, ShopStore (all reads/writes), ShopBackend/ShopChange, ProposedAction, demo data
  firebase/    FirestoreBackend (batched writes + listeners), Firestore mapping, phone auth, auth gate
  ai/          AssistantService + BarcodeScanner interfaces, demo implementations, code-built answers
  widgets/     header, big buttons, keypad, sheets, toast
  theme/       colours and Mukta font
assets/fonts/  Mukta (bundled so Devanagari works offline; OFL licence included)
```

## Rules the code follows

- **Money is `int` paisa, quantity is `int` milli-units.** 1.5 kg = 1500. See `core/money.dart`, `core/qty.dart`.
- **One user action = one `ShopChange` = one Firestore batch.** `ShopStore` does the arithmetic and updates its cache at once; `FirestoreBackend` persists with `FieldValue.increment` and never awaits the network or uses `runTransaction` (fails offline). Listeners feed remote changes back via `replaceFromRemote`.
- **Only `ShopStore` changes data.** AI output is an `AssistantIntent`; actions are shown on a confirm card and only `ShopStore.apply()` commits them after a tap. `ShopStore.validate()` runs the same checks the Cloud Function will.
- **Chat answers are built in code** (`ai/answers.dart`) from store data; the model would only pick the metric.
- **Today is Nepal time** (UTC+5:45) whatever the device timezone.
- **No ✓/✕ characters in text** — Mukta has no glyphs for them and there is no offline fallback font. Use `Icons.check_rounded` / `Icons.close_rounded` (e.g. `BigButton(trailingIcon: …)`).

## Versions

Firebase packages are pinned to the `cloud_firestore` 6.x / `firebase_core` 4.x line because `fake_cloud_firestore` (used by the tests) does not support `cloud_firestore` 7 yet. Upgrade together when it does.

## Next steps

1. Run the Firebase setup above and try sign-in on a real Android phone.
2. Catalog editing (add/edit products, photos) so new shops don't depend on the sample catalog.
3. Replace `DemoBarcodeScanner` with ML Kit (`mobile_scanner`), `DemoAssistantService` with a Cloud Functions client.
4. Surface rejected writes (`FirestoreBackend.onError`) to the user instead of only logging them.
