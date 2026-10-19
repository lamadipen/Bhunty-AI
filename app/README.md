# Bhunte AI — Flutter app

Android · iOS · Web. Two modes:

- **demo** (default): in-memory demo shop, no login. Nothing is saved.
- **firebase**: the shop is saved in Firestore with offline persistence. Sign-in is **anonymous and automatic** for now (no login screen); phone OTP login is built but off — turn it on with `--dart-define=PHONE_LOGIN=true`.

The AI backend is still the scripted demo in both modes (Phase 2).

```bash
flutter pub get
flutter run                                   # demo
flutter run --dart-define-from-file=firebase.local.json   # Firebase (after setup below)
flutter run --dart-define=SCANNER=demo        # scripted scanner (no camera needed)
flutter test
flutter analyze
dart run flutter_launcher_icons               # after changing ../brand/ icons
```

## Firebase setup (one time, needs your Google account)

1. Create a Firebase project in the console. Enable **Authentication → Sign-in method → Anonymous** and create a **Firestore** database (region close to Nepal, e.g. `asia-south1`).
2. In `app/`: `flutterfire configure` — pick the project and Android, iOS, Web. This writes `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`, which Android and iOS read directly.
3. Web: copy `firebase.example.json` to `firebase.local.json` and fill it from the console (Project settings → Your apps → Web app → config) or `firebase apps:sdkconfig WEB <app-id>`. It also sets `BACKEND=firebase`, so one flag runs the app on Firebase on any platform.
4. From the repo root: `firebase deploy --only firestore:rules --project <your-project>`.

**No project details in git.** `google-services.json`, `GoogleService-Info.plist`, `firebase.local.json`, `lib/firebase_options.dart` (flutterfire also writes it; the app doesn't use it) and `.firebaserc` are all git-ignored, so each developer keeps their own. These values aren't secrets; access is controlled by `firestore.rules`. Never commit service-account keys or LLM API keys.

**Know this about anonymous sign-in:** the account lives on one device. Uninstalling the app or clearing its data creates a new account, and the old shop's data stays in Firestore but can no longer be opened. Fine for pilots; turn on phone login before real shops depend on it.

### Phone login (later)

1. Enable **Authentication → Phone**; add test phone numbers there to avoid real SMS while testing.
2. Android: add your debug and release SHA-1/SHA-256 in the Firebase console. iOS: set up APNs or the reCAPTCHA fallback as Firebase's phone-auth guide says.
3. Run with `--dart-define=PHONE_LOGIN=true`.
4. Before shipping it, change `FirebaseAuthService.confirmCode` to **link** the phone credential to the current anonymous user (`currentUser.linkWithCredential`) so existing shops keep their uid and data.

On first sign-in (anonymous or phone) the app creates `shops/{uid}` and seeds the 8 sample products so the tap grid isn't empty (catalog editing comes next).

Rules tests (no project needed, runs the local emulator; needs Java 11+ and the Firebase CLI):

```bash
cd ../rules-test && npm install && npm test
```

## Screens (from the design prototype)

| Prototype screen | File |
|---|---|
| 1 · Home (गृह) | `lib/screens/home_screen.dart` |
| 2 · Sell (बेच्नुस्) + payment sheets + done | `lib/screens/sell_screen.dart`, `lib/screens/payment_sheets.dart` |
| 3 · Add stock (bill photo, voice, or by hand) | `lib/screens/stock_screen.dart`, `lib/screens/add_stock_sheet.dart` |
| New product (not in the prototype) | `lib/screens/new_product_screen.dart` |
| Print own barcode/QR labels | `lib/screens/label_screen.dart`, `lib/labels/` |
| Camera scanner + type-the-number | `lib/scanning/` |
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
- **Own codes are in-store EAN-13 (prefix 2, GS1 restricted circulation)**, so they never clash with real product barcodes. Each product prints its label as a barcode (phone camera *and* laser scanners) or a QR (small/round items). Labels are drawn by Flutter and placed in the PDF as images, because the `pdf` package can't shape Devanagari (`core/barcode.dart`, `labels/`).
- **Scanning always has a way out.** The camera screen (`mobile_scanner`) shows why it can't scan (permission denied, no camera) with a retry, and "type the number" is always on screen. Typed GTINs must pass the check digit; payment QRs, links and other non-product codes are refused (`core/product_code.dart`). UPC-A is stored as EAN-13 so both scans match.
- **Own codes are flagged (`ownCode`), not guessed from the 2 prefix.** Hidden products (`archived`) leave grids and searches but keep their history and code; scanning that code offers to show them again.
- **Editing never writes stock.** `updatedProducts` are saved with merge and without `stockMilli`, so another phone's sales aren't overwritten.
- **Text keyboard only on the new-product name.** Every number goes through the keypad (`widgets/number_pad.dart`).
- **No ✓/✕ characters in text** — Mukta has no glyphs for them and there is no offline fallback font. Use `Icons.check_rounded` / `Icons.close_rounded` (e.g. `BigButton(trailingIcon: …)`).

## Versions

If a web build can't find a plugin (`MissingPluginException` on web), run `flutter clean`: the web plugin registrant can be cached from before the plugin was added.

`image` is pinned below 4.11: 4.11.0 needs a newer `archive` than `pdf` 3.12 allows. `pdf` 3.13+/`printing` 5.15+ need Flutter 3.41; drop the pin when upgrading.

Firebase packages are pinned to the `cloud_firestore` 6.x / `firebase_core` 4.x line because `fake_cloud_firestore` (used by the tests) does not support `cloud_firestore` 7 yet. Upgrade together when it does.

## Next steps

1. Run the Firebase setup above and try the app on a real Android phone (sell, then go offline and sell again).
2. Catalog editing (add/edit products, photos) so new shops don't depend on the sample catalog.
3. Replace `DemoBarcodeScanner` with ML Kit (`mobile_scanner`), `DemoAssistantService` with a Cloud Functions client.
4. Surface rejected writes (`FirestoreBackend.onError`) to the user instead of only logging them.
