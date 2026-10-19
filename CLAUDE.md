# Bhunte AI — context for AI coding sessions

Read this first. It captures every product decision made so far, so you don't need the original chat.

## What we're building

A point-of-sale (POS) app for small Nepali shops (kirana pasal, small retailers, hotels/cafés).
Name: **Bhunte AI (भुन्टे)** — the shop's cheerful little helper who keeps the records. The owner speaks, Bhunte writes it down. (Previously "Munshi".) Check app-store, domain and trademark availability before launch.

Platforms: Android, iOS and web from one codebase.

## Who the users are

- Shopkeepers who are not technically confident. They use Facebook, Messenger, Viber and TikTok comfortably.
- They are good at tapping pictures and entering numbers. They avoid typing text.
- Many mix Nepali and English when speaking. Internet can be patchy.

## Core product principles (do not break these)

1. **Tap first, AI second.** Checkout must be fast without the AI: a picture grid of frequent items, barcode scanning, and a number keypad. AI (voice, photo, chat) is for the slow, tedious jobs.
2. **The LLM never writes to the database directly.** It proposes structured actions via tool/function calling. The backend validates them, the app shows a confirmation card (e.g. "अण्डा × 5 = रु 100 · ठीक छ ✓ / होइन ✕"), and only a user tap commits.
3. **Money and stock are deterministic.** Totals, change, balances and stock counts are computed in code, never by the model.
4. **No text keyboard in normal use.** Quantities and money use a large 3×4 keypad. Voice and photos replace typing.
5. **Nepali first.** Large Devanagari label + icon on every action, small English underneath. Regular 0–9 digits for money.
6. **Big targets.** Primary buttons 64–76 px tall; minimum touch target 44 px. One main action per screen, bottom sheets, a clear "सकियो ✓" end state.
7. **Works offline.** Selling, scanning, the tap grid and udharo must work with no network and sync later. AI features degrade gracefully when offline.
8. **Flag uncertainty.** When AI is unsure (e.g. unclear bill line), leave the row unticked and highlight it so the user checks only those.

## Where AI is used

| Feature | Input | AI job | Output |
|---|---|---|---|
| Stock from bill photo | Photo of wholesaler bill | Extract line items (name, qty, cost) | Review list with confidence flags → user confirms |
| New product from photo | Photo of item | Suggest name/category; match against the shop's own catalog via image embeddings | Confirm card |
| Voice entry | "पाँच वटा अण्डा", "राम दाइलाई ३५० उधारो" | Speech-to-text → parse into a tool call | Confirm card |
| Ask Bhunte | "आज कति बिक्यो?", "कुन सामान सकिँदैछ?" | Answer from the shop's data (queries run in code) | Chat reply / stat card |

Checkout identification order: **barcode → tap grid → photo match against own catalog**. Never open-ended "what is this product" identification at checkout.

## Key features (MVP scope)

- Product catalog with pictures, prices, barcodes, stock count
- Sell screen: frequent-item grid, barcode scan, voice add, cart with −/qty/+, keypad for quantity
- Payment: cash (with change calculator from tendered notes), QR (Fonepay/eSewa/Khalti), udharo (credit)
- Udharo book: customers, balances, payments received, Viber/SMS reminder
- Stock entry: bill photo, product photo, voice
- Today's sales and simple reports; low-stock alerts

## Tech stack

- **App:** Flutter (Android, iOS, web)
- **Backend:** Firebase — Auth (phone OTP), Firestore (with offline persistence), Storage (photos), Cloud Functions
- **AI wrapper:** Cloud Functions hold the LLM API keys and tool definitions. Provider-agnostic interface; use a small, cheap model for routine parsing.
- **On-device:** barcode scanning (e.g. Google ML Kit)
- **Speech-to-text:** must handle ne-NP and Nepali–English code-switching. Test quality early (Google STT, Whisper).

See `docs/architecture.md` for data model and tool schema, `docs/roadmap.md` for phases.

## Risks to keep in mind

- Nepali speech recognition quality (numbers like "दुई दर्जन", "आधा केजी")
- LLM cost per shop vs. low willingness to pay — keep AI off the per-sale hot path
- Connectivity — offline-first is mandatory
- Firestore read costs once reports grow

## Design prototype

Clickable screens (Home, Sell, Stock from bill photo, Udharo, Talk to Munshi — the prototype still uses the old name):
https://claude.ai/artifact/9pH1Zd3ydNLFy8gXswoFsm (private to the owner)

The Flutter app in `app/` implements these screens; screen ↔ file map is in `app/README.md`.

Visual direction: light green-grey ground `#EEF2EF`, ink `#17201B`, primary green `#1D6B45`, action orange `#C2541B`, QR blue `#1E3E73`, warning bg `#FCE9DC` / text `#8A3A10`. Font: Mukta (Devanagari + Latin), bundled in `app/assets/fonts/` so it works offline.

Logo: `brand/` — green rounded tile, a round smiling "Bhunte" face wearing an orange Dhaka topi, with a small sparkle for AI. Wordmark "भुन्टे" over "Bhunte AI".

## Repo layout

- `app/` — Flutter app (Android, iOS, web). `flutter run` = in-memory demo; `--dart-define-from-file=firebase.local.json` (local, git-ignored) = Firestore with automatic anonymous sign-in (phone OTP login built but off: `PHONE_LOGIN=true`).
- `firestore.rules`, `firebase.json` — Firestore rules; tests in `rules-test/` (local emulator).
- `brand/` — logo SVGs and exported PNGs.
- `docs/` — architecture, roadmap, review; `docs/product-addition.md` = product/stock/price rules and the test scenarios they must pass.

## Code conventions

- Money is `int` paisa, quantity is `int` milli-units (`app/lib/core/`). Never `double` for either.
- All writes go through `ShopStore` methods; AI output is a `ProposedAction` that only `ShopStore.apply()` commits after a user tap.
- Each `ShopStore` write produces one `ShopChange`, saved by `FirestoreBackend` as one `WriteBatch` with `FieldValue.increment`. Never `runTransaction`, never await a commit (offline-first).
