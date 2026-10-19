# Docs & prototype review (2026-10-18)

Reviewed: `CLAUDE.md`, `README.md`, `docs/architecture.md`, `docs/roadmap.md` and the 5-screen design prototype.
Overall the product thinking is strong: tap-first checkout, "LLM proposes, user confirms", deterministic money and offline-first are the right foundations for this user. The gaps below are mostly things that will bite once real shops use it.

Items marked ✅ are already handled in the Flutter scaffold (`app/`) or in these docs.

## P0 — fix before building further

1. **Firestore transactions do not work offline.** `architecture.md` says stock and balance are "updated in transactions alongside the sale". `runTransaction` needs the server, so selling would fail with no network — breaking principle 7. Use **batched writes with `FieldValue.increment()`** (these queue offline) for sale + stock + ledger, and treat `stock`/`balance` as caches that a Cloud Function can reconcile from the ledger. ✅ architecture updated.
2. **Money type is unspecified.** Store all money as **integer paisa** (`int`), never `double`. Display rounds to rupees. ✅ scaffold uses `int` paisa (`lib/core/money.dart`).
3. **Loose goods need fractional quantities.** Kirana shops sell "आधा केजी चिनी", "२५० ग्राम जिरा". The model has `stock` and `qty` as plain numbers and the prototype keypad has no decimal key. Decide: either store quantity in **milli-units** (grams/ml as `int`) with a `unit` field, or allow one decimal place. Add a `.` / "आधा" key on the quantity keypad for kg/litre items. ✅ scaffold stores quantities as `int` milli-units (`Qty`).
4. **Bargaining and round-off.** Price haggling (मोलमोलाई) and "रु 5 छोडिदिनुस्" are everyday. Checkout needs a **discount / round-off** on the total (keypad, not text). Missing from MVP scope.
5. **Split payment.** "500 नगद, बाँकी उधारो" is common. Change `payment: "cash" | "qr" | "udharo"` to `payments: [{method, amount}]`. Udharo part writes a ledger credit in the same batch.

## P1 — product gaps

6. **Bikram Sambat dates.** Shopkeepers think in BS (२०८३ कात्तिक १). Show BS dates everywhere in the UI; store UTC + a `bsDate` key. Day boundaries must use **Asia/Kathmandu (UTC+5:45)**, including `dailySummaries/{date}` keys.
7. **"Today's sales" must work offline.** `dailySummaries` is written by a Cloud Function, so it lags until sync. Compute the Home card locally from today's cached sales; use the summary only for history/reports. ✅ done (sales carry a `day` field).
8. **Void / return a sale.** No way to undo a mistaken sale. Add "बिक्री रद्द" within N minutes, written as a reversing entry (never delete).
9. **Cash tender options.** Prototype offers exact / 500 / 1000 / 2000. For a रु 75 sale the customer hands over रु 100. Suggest the next 2–3 real notes above the total (50, 100, 500, 1000). ✅ scaffold does this (`suggestTenders`).
10. **QR confirmation is manual.** With a static QR the shopkeeper taps "पैसा आयो ✓" on trust; fake payment screenshots are a known fraud in Nepal. Keep it in Phase 1 but label it clearly, and prioritise Fonepay dynamic QR with server-side confirmation.
11. **New customers from voice.** `record_credit(newCustomerName)` will create "राम", "राम दाइ", "Ram dai" as three people. The confirm card must show *"नयाँ ग्राहक"* explicitly and offer the closest existing matches first.
12. **Customer consent & privacy.** Udharo stores names, phones and debts of third parties. Nepal's Individual Privacy Act 2075 applies; add a short consent line before sending Viber/SMS reminders and a data export/delete path.
13. **Pack sizes.** Wholesale bills say "वाइवाइ कार्टुन × 2" but the shop sells packets. Products need a `packSize` (1 carton = 30 packets) so bill lines convert to selling units; the bill review row should show both.
14. **Onboarding is the real first-run problem.** An empty catalog means the tap grid is empty. Plan "add your first 20 items in 5 minutes" (bill photo → catalog) as a Phase 1 deliverable, not Phase 3.

## P2 — engineering details

15. **Embeddings in the product doc** make every catalog read heavier. Keep them in a separate collection or use Firestore vector search on a dedicated field that is never fetched by the app.
16. **Timestamps offline.** `serverTimestamp()` is null until sync; write both `createdAt` (client) and `syncedAt` (server).
17. **Security rules and roles** are not mentioned. Owner vs helper roles affect who can void sales or edit udharo; design rules with the data model, not after. ✅ owner-only rules drafted and emulator-tested; roles still to do.
18. **Phone OTP cost and delivery in Nepal.** Firebase SMS to +977 is billed per message and deliverability varies; budget for it and keep a fallback (Google sign-in) for owners.
19. **Tool schema gaps.** Add `remove_from_cart`, `set_quantity`, `update_price` and an explicit `unclear` result so the model can say "I'm not sure" instead of guessing. Define `query` as a fixed enum the code implements.
20. **Ask Bhunte answers** should be templated from query results (code fills numbers into fixed sentences); let the model only choose the template. This keeps principle 3 for chat answers too.

## Doc hygiene

21. README linked `docs/architecture.md` and `docs/roadmap.md` but the files were at the repo root. ✅ moved into `docs/`.
22. There is a second, older copy of `CLAUDE.md` at `~/Downloads/CLAUDE.md` (outside this repo) still saying "Munshi". Delete it or keep it in sync, or AI sessions may read the stale one.
23. Repo folder is `Bhunty-AI` while the product is **Bhunte AI**. Rename the GitHub repo to `bhunte-ai` for consistency.
24. Roadmap has no success criteria. Add measurable gates, e.g. Phase 0: "≥ 85 % of voice samples parsed correctly", "checkout of 5 items in < 15 s with tap only"; pilot: "3 shops use it daily for 2 weeks".

25. **Font coverage.** Mukta has no ✓ / ✕ glyphs; they render as boxes, and offline there is no fallback font. The prototype uses them on most buttons. ✅ the app draws them as icons.

## Naming note (product)

"Bhunte" (भुन्टे) reads as a warm, cheeky nickname — "the little one" — which fits a friendly helper. Two checks before launch: (a) test it with shop owners outside Kathmandu valley, where the connotation can differ, and (b) app-store, `.com`/`.com.np` domain and trademark search, as the roadmap already says.
