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
- [x] Add stock by hand: tap or scan a product, units or packs (carton/bora), cost; latest cost kept
- [x] New product form (name typed once; price, cost, unit, pack size, opening stock, low-stock alert, barcode)
- [x] Shop's own code for products without a barcode (in-store EAN-13, printed as barcode or QR); A4 sticker labels to print or share
- [x] Real camera scanning (ML Kit / web) with fallbacks: type the number (check digit), camera denied/missing, non-product QR refused
- [x] Edit a product (name, prices, unit while no stock, pack, low-stock, code: scan / own / remove), hide/unhide, reprint prompt
- [x] Unknown code on Sell offers to add the product; hidden product's code offers to show it again
- [x] Labels: show-price switch; A4 sheet or thermal 50×30
- [x] Stock in batches (own cost + sale price each), price history, latest price wins; optional supplier/bill no. — `docs/product-addition.md`
- [ ] Manual bill (several products in one save), batch corrections, supplier records
- [ ] Product photos; choosing what's on the Sell grid; stock count correction; several codes per product
- [ ] Shop setup (name) + first-20-items onboarding from a bill photo
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
- [ ] Add a product from photos: front (thumbnail), barcode, label → AI fills the form (Claude Haiku via Cloud Function) — spec `docs/product-photos.md` (in review)
- [ ] Product photo matching against the shop's own catalog

## Phase 3 — Polish & growth
- [ ] Dynamic Fonepay/eSewa/Khalti QR with auto-confirm
- [ ] Receipts via Viber/SMS; udharo reminders
- [ ] Owner + helper accounts on multiple devices
- [ ] Reports (weekly/monthly profit, best sellers)
- [ ] Pricing model and onboarding flow
