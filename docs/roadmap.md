# Roadmap

## Phase 0 — Validate (before code)
Gate: ≥ 85 % of voice samples and bill lines parsed correctly; 5-item tap checkout in < 15 s.

- [ ] Show the clickable prototype to 3–4 real shopkeepers; note where they hesitate
- [ ] Record 20–30 real voice samples (quantities, udharo phrases) and test Nepali speech-to-text accuracy
- [ ] Photograph 10 real wholesaler bills and test LLM extraction accuracy
- [ ] Check name availability (Play Store, App Store, domain, trademark)

## Phase 1 — Offline POS core (no AI)
- [x] Flutter project setup (Android, iOS, web) — `app/`, screens from the prototype on demo data
- [x] Firestore backend behind `ShopStore` (batched offline writes), security rules + emulator tests
- [x] Automatic anonymous sign-in (phone OTP login built, off behind `PHONE_LOGIN`)
- [ ] Create the Firebase project, run `flutterfire configure`, test on a real phone
- [ ] Turn on phone login, linking the anonymous account so shops keep their data
- [ ] Shop setup + product catalog (photo, price, barcode, stock); first-20-items onboarding from a bill photo
- [ ] Sell screen: favourites grid, barcode scan, cart, quantity keypad
- [ ] Payment: cash with change calculator, QR (static first), udharo, split payment, discount/round-off
- [ ] Void a sale (reversing entry); kg/litre quantities on the keypad
- [ ] Udharo book: customers, balances, payments
- [ ] Today's sales + low-stock alerts
- [ ] Bikram Sambat dates, Asia/Kathmandu day boundaries
- [ ] Offline mode verified end to end (batched writes, no transactions)

Gate: 3 pilot shops use it daily for 2 weeks.

## Phase 2 — AI assist
- [ ] Cloud Functions AI wrapper with tool calling + validation
- [ ] Stock from bill photo (review list with confidence flags)
- [ ] Voice entry on Sell, Stock and Udharo screens
- [ ] Ask Bhunte chat (sales, stock, udharo questions)
- [ ] Product photo matching against the shop's own catalog

## Phase 3 — Polish & growth
- [ ] Dynamic Fonepay/eSewa/Khalti QR with auto-confirm
- [ ] Receipts via Viber/SMS; udharo reminders
- [ ] Owner + helper accounts on multiple devices
- [ ] Reports (weekly/monthly profit, best sellers)
- [ ] Pricing model and onboarding flow
