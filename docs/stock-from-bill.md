# Stock from a bill — photo (AI) and manual bill — spec and test scenarios

Status: **implemented** (2026-10-24) — `app/lib/data/bill.dart`, `app/lib/bills/`, `app/lib/screens/bill_screen.dart`, `bill_capture_screen.dart`, `functions/src/bill.ts`. Tests: `app/test/bill_test.dart` (MB, money), `app/test/bill_photo_test.dart` (BL), `functions/test/bill.test.ts`, `rules-test/`. The answers to the questions in §7 were accepted as recommended.
Builds on [product-addition.md](product-addition.md) — every rule there still applies (batches, price changes, packs, R1–R13) — and on [product-photos.md](product-photos.md) (photo capture, Cloud Function, daily limit).

Scope: receiving **one wholesaler delivery with several products in one save**, either by photographing the bill (AI reads it) or by building the bill by hand.
Out of scope: voice, correction entries (S-12), supplier records/ledger, purchase reports, Bikram Sambat date conversion.

---

## 1. Decisions (agreed)

| # | Decision |
|---|---|
| D1 | **One bill screen for both ways in.** A bill photo fills it with lines read by the AI; a manual bill starts it empty. Either way the shopkeeper checks the lines and saves once: **1 delivery, 1 batch per line** (S-10). |
| D2 | **Bill photo:** 1–3 photos per bill (long bills run over pages), from the camera, gallery/files, or the webcam on desktop browsers (same capture as product photos). |
| D3 | **AI = Claude Haiku** in a new Cloud Function `readBill`. It reads the lines (name as printed, quantity, pack word, free quantity, rate, amount) and the header (supplier name/phone, bill no., date, VAT, discount, bill total). |
| D4 | **Matching lines to products: code first, AI second.** (1) A **remembered bill name** for this shop (`billAliases`, D5) decides in code. (2) Otherwise the AI picks from the shop's catalog, which the app sends with the request. (3) Otherwise the line is **new**. |
| D5 | **The app learns bill names.** When the shopkeeper matches or corrects a line ("WAI WAI CHK" → वाइवाइ), that text is remembered for the shop, so the next bill from any supplier matches it without the AI choosing. |
| D6 | **Money is checked in code, never trusted from the AI** (principle 3). For each line, qty × rate is compared with the printed amount; the sum of lines is compared with the bill total. Any mismatch → the line is unticked and highlighted. Costs and totals saved are computed in code. |
| D7 | **Unsure lines start unticked** and orange (principle 8); new-product lines start unticked and blue. Only ticked lines are saved. |
| D8 | **New product from a line:** the row's "नयाँ सामान" opens the new-product form pre-filled (name, unit, pack, cost); the product is created **with no opening stock** and the row links to it — its stock arrives with the bill's batch. |
| D9 | **Bill photos aren't stored** (as with label photos). Only what is saved on the bill screen is kept. |
| D10 | **Separate daily limit for bills: 30 bill reads per shop per Nepal day** (a bill is several large photos; product photos keep their 100). |
| D11 | **Manual bill:** "हातैले बिल" on the stock screen. Add lines by tapping the product grid, scanning, or "सबै सामान" picker; each line uses the same keypad sheet as adding stock (qty in units or packs, cost, sale price). Tapping a tile outside the bill screen still does the quick single-product add. |

## 2. Flows

### 2.1 Bill photo
1. Stock → **बिलको फोटो** → capture screen "बिलको फोटो खिच्नुस्": up to 3 page slots (पेज १, २, ३), each camera / gallery-file; पढ्नुस्.
2. App shrinks each page (≤ 1600 px, JPEG ~85, ≤ 700 KB) and sends pages + catalog to `readBill`.
3. App applies remembered bill names, checks the AI's product ids against the catalog, does the money checks, converts packs, and opens the **bill screen**.
4. Bill screen: header (supplier, bill no., date — tagged "भुन्टेले भरेको"), the lines, footer totals, **स्टकमा थप्नुस् (n)**.
5. Save → one write: delivery + batches + price changes + remembered names (+ pack sizes the user chose to keep, BL-5).

### 2.2 Manual bill
1. Stock → **हातैले बिल** → empty bill screen with the product grid / scan / सबै सामान to add lines.
2. Tap a product → the add-stock keypad sheet → **बिलमा थप्नुस्** → row added. Repeat.
3. Optional: supplier, bill no., and the **printed bill total** (keypad) to compare with the sum.
4. Save → same single write as 2.1 (source `manual`).

### 2.3 Bill screen rows

| Row state | Starts | Shows | Actions |
|---|---|---|---|
| **Ready** | ticked | product picture + name, "+ 60 प्याकेट · रु 13 दरले · रु 780", sale price | tap to edit (keypad sheet), untick |
| **Check** (orange) | unticked | what's wrong: "हिसाब मिलेन: 10 × 18 = 180, बिलमा 108", "3 हो कि 8?", "एक कार्टुनमा कति?", "सामान मिलेको पक्का छैन" | edit, change product, tick |
| **New** (blue) | unticked | the bill text, e.g. "Real Juice Mango 1L" | **नयाँ सामान बनाउनुस्**, **पसलको सामान छान्नुस्**, **छोड्नुस्** |

Footer: "छानिएको जम्मा रु Y" and, when a bill total is known, "बिलमा रु X" with the difference in orange when they don't match.
"+ सामान थप्नुस्" at the end of the list adds a line by hand (a line the AI missed).

## 3. Rules

**BR1 — Nothing is saved until "स्टकमा थप्नुस्".** Leaving the bill screen saves nothing (asks first if any row exists). Exception: a product created from a row (D8) exists from the moment its form is saved.

**BR2 — One save = one delivery = one write.** Ticked rows only. Each row = one batch with its own cost and sale price (R2); a changed sale price = a `stock` price change (R3). All in one `WriteBatch`, offline-safe.

**BR3 — Line money.** Quantity is in selling units after pack conversion (R10). Unit cost = line amount ÷ quantity (incl. free items), rounded to the paisa; the batch keeps the line amount exactly as total. If only the rate is known: amount = qty × rate, computed in code.

**BR4 — Line check.** When qty, rate and amount are all read: |qty × rate − amount| > रु 1 → row is **Check** and can't be ticked until opened; the row sheet starts from qty × rate. (Rounding on bills is common; ≤ रु 1 is accepted.)

**BR5 — Bill check.** When the bill total is read or typed: sum of all lines (ticked or not) − discount + VAT ≠ total (± रु 1) → orange banner "बिलको जम्मा मिलेन". Saving is still allowed.

**BR6 — Packs.** A line in packs ("2 कार्टुन", "1 box", "1 bora") uses the product's pack size. If the product has none, the row is **Check** with "एक <pack>मा कति <unit>?" (keypad); the answer is used for this batch, and a switch "यो सामानमा सधैं" (on) saves it as the product's pack in the same write.

**BR7 — Unit conflicts.** A line in kg/litre for a product sold in वटा/प्याकेट (or the reverse) is **Check** — never converted by guess.

**BR8 — Matching.** A product id from the AI is used only if it is in the catalog sent; a hidden product's id offers "लुकाइएको छ — फेरि देखाउने?". A remembered bill name beats the AI. A low-confidence AI match → **Check**.

**BR9 — Remembered names.** On save, every ticked row whose text came from the bill stores `billAliases`: normalised text → productId. Normalising: lower case, single spaces, punctuation removed. A later correction overwrites it.

**BR10 — Same product twice.** On a photo bill, two lines for one product stay two batches (they may have different rates); the last line's unit cost becomes the product's cost (R9). On a manual bill, adding a product already in the list opens its row instead.

**BR11 — Free items.** "12+1", "1 free" → quantity includes the free units; amount unchanged; so unit cost drops (BL-8).

**BR12 — Header fields are optional** (R11). Supplier name/phone, bill no. and the bill date (kept **as printed**, e.g. "२०८१/०७/०८", until BS dates are built) go on the delivery. Phone must be a valid Nepali number or it is dropped.

**BR13 — Offline.** Bill photo needs the internet: offline, पढ्नुस् says "इन्टरनेट आएपछि बिल पढ्न सकिन्छ" and offers **हातैले बिल बनाउनुस्**. The manual bill works fully offline.

**BR14 — Daily limit.** Each bill read counts 1 in `aiUsage/{day}.billReads`; at 30: "आजको बिल पढ्ने सीमा सकियो — हातैले बिल बनाउनुस्".

**BR15 — The AI never writes and never decides money or stock.** It returns text and numbers as read; the app computes, the shopkeeper confirms (principles 2, 3).

## 4. Data and contract

```
deliveries/{id}                      # existing; new optional fields
  source: "bill_photo" | "manual"
  billDateText?, billTotalPaisa?,    # as printed / typed
  vatPaisa?, discountPaisa?          # see Q1

batches/{id}                         # existing; new optional field
  billLineText?                      # the line as printed (photo bills)

billAliases/{aliasId}                # new; aliasId = the normalised text, URI-encoded (same on every device)
  text, productId, updatedAt, updatedBy

aiUsage/{yyyy-mm-dd}
  photoReads, billReads              # billReads new, function-only
```

**Cloud Function `readBill`** (callable, signed-in, region asia-south1):

```
in:  { pages: [ jpegBase64 ],                                   # 1–3, ≤ 700 KB each
       catalog: [ { id, ne, en, unit, packName?, packSize? } ] } # all products, hidden too (BR8), ≤ 1,000
out: { supplierName?, supplierPhone?, billNo?, billDateText?,
       totalPaisa?, vatPaisa?, discountPaisa?,
       lines: [ { text,                                          # as printed, ≤ 80 chars
                  qtyMilli?, qtyIn?: "unit"|"pack"|"kg"|"litre", packWord?,
                  freeQtyMilli?, ratePaisa?, amountPaisa?,
                  productId?, match: "high"|"low"|"none",
                  nameNe?,                                       # suggestion for a new product
                  confidence: { qty, rate, amount: "high"|"low" },
                  note? } ],                                     # ≤ 80 lines
       usage: { today, limit: 30 } }
errors: unauthenticated | invalid-argument | limit-reached | unreadable | unavailable
```

Server checks (as PR6): integers and ranges (qty 0.001–100,000 units; money रु 0.01–रु 10,00,000), productId must be in the catalog sent, texts trimmed/limited, at most 80 lines, unknown fields dropped. Structured outputs, low effort; refusal = unreadable.

Security rules: `billAliases` owner read/write, `text` string ≤ 120, `productId` string; `aiUsage` stays function-only.

---

## 5. Scenarios (test reference)

Catalog for all scenarios: the demo shop — वाइवाइ (प्याकेट, pack कार्टुन × 30), अण्डा (वटा, ₹20), चिनी (केजी, ₹120), तेल (लिटर, ₹280), साबुन (वटा, ₹60), बिस्कुट (प्याकेट, ₹30) — plus Coke 500ml (वटा, no pack, ₹60). "AI returns" = the faked function reply in tests.

### BL — Bill photo

**BL-1 Printed bill, everything matches (main case)**
- AI returns 4 lines, all `match: high`, checks pass: वाइवाइ 2 कार्टुन @ 390 = 780; चिनी 25 kg @ 105 = 2,625; साबुन 24 @ 45 = 1,080; बिस्कुट 40 @ 22 = 880. Header: "राम ट्रेडर्स", 98XXXXXXXX, bill no. 1452, total 5,365.
- Then: 4 rows ticked; header filled and tagged; footer "छानिएको जम्मा रु 5,365 · बिलमा रु 5,365".
- When: change चिनी sale price ₹120 → ₹125, save.
- Then: 1 delivery (`bill_photo`, 4 batches, total ₹5,365, supplier/phone/bill no.); वाइवाइ +60 (2 × 30, unit cost ₹13, total ₹780, enteredAs pack); चिनी +25, 1 priceChange `stock` ₹120 → ₹125; 4 `billAliases`; aiUsage.billReads +1.

**BL-2 Line amount doesn't add up**
- AI returns साबुन qty 24, rate 45, amount 108 (misread).
- Then: row **Check** "हिसाब मिलेन: 24 × 45 = 1,080, बिलमा 108", unticked.
- When: user opens it, keeps 24 @ 45 → row ticks; total used = ₹1,080 (computed).

**BL-3 Bill total doesn't match**
- Lines sum to ₹5,365, printed total ₹5,465.
- Then: banner "बिलको जम्मा मिलेन: लाइन रु 5,365 · बिलमा रु 5,465"; save still allowed.

**BL-4 Packs with a known pack size** — covered in BL-1 (वाइवाइ कार्टुन × 30).

**BL-5 Pack size unknown**
- AI returns "Coke 500ml 1 crate @ 1,080 = 1,080" (`qtyIn: pack`, packWord "crate"); Coke has no pack.
- Then: row **Check** "एक crateमा कति वटा?".
- When: user enters 24, switch "यो सामानमा सधैं" on, saves the bill.
- Then: batch +24 वटा, unit cost ₹45, total ₹1,080; Coke now has pack crate × 24 (same write).

**BL-6 Item not in the shop → new product from the row**
- AI returns "Real Juice Mango 1L 12 @ 300 = 3,600", `match: none`, nameNe "रियल जुस आँप".
- Then: row **New**.
- When: नयाँ सामान बनाउनुस् → form pre-filled: name "रियल जुस आँप 1L", unit वटा, cost ₹300, opening stock hidden (0); user enters price ₹360, saves.
- Then: product exists with stock 0; back on the bill the row is linked and **ticked**; saving the bill adds +12 @ ₹300 as a batch of this delivery.

**BL-7 Wrong match corrected and remembered**
- AI matches "WAI WAI CHK 70G" to बिस्कुट (`low`).
- When: पसलको सामान छान्नुस् → वाइवाइ; save.
- Then: alias "wai wai chk 70g" → waiwai. Next bill with the same text: matched to वाइवाइ by code (Ready), whatever the AI suggests.

**BL-8 Free items**
- AI returns "बिस्कुट 12+1 @ 22 = 264" (qty 12, free 1).
- Then: +13 प्याकेट, unit cost ₹20.31, total ₹264 exactly.

**BL-9 Handwritten, unclear quantity**
- AI returns अण्डा qty 30, confidence qty low, note "3 हो कि 8?".
- Then: row **Check** with the note, unticked; user confirms or changes on the keypad.

**BL-10 Two-page bill**
- Two pages; AI returns 9 lines in order; the total is on page 2.
- Then: one bill screen, 9 rows, one delivery on save.

**BL-11 Not a bill**
- AI returns `unreadable`.
- Then: "बिल पढ्न सकिएन — फेरि खिच्नुस् वा हातैले बिल बनाउनुस्"; pages stay; **हातैले बिल बनाउनुस्** opens an empty manual bill.

**BL-12 Offline**
- Then: no call; offline message + हातैले बिल बनाउनुस्; billReads unchanged.

**BL-13 Daily limit**
- 30 bill reads today.
- Then: limit message + हातैले बिल; product-photo reads unaffected.

**BL-14 VAT and discount** (Q1: spread into cost)
- Bill: lines ₹10,000, discount ₹200, VAT 13% ₹1,274, total ₹11,074.
- Then: each batch's total = its share of ₹11,074 (proportional, rounding difference on the last line), so the delivery total = ₹11,074 and unit costs include VAT and discount. The printed line amounts stay on the rows for the check (BR4).

**BL-15 Same product on two lines**
- AI returns वाइवाइ 1 कार्टुन @ 390 and वाइवाइ 10 @ 14.
- Then: two batches (+30 @ ₹13, +10 @ ₹14); product cost ₹14 (last line).

**BL-16 Loose goods** — चिनी 25 kg in BL-1: +25 केजी, no pack conversion.

**BL-17 Unit conflict**
- AI returns "चिनी 2 pcs @ 105" matched to चिनी (केजी).
- Then: row **Check** "एकाइ मिलेन: बिलमा pcs, सामान केजीमा"; nothing converted.

**BL-18 AI points to an unknown or hidden product**
- AI returns productId "xyz" (not in catalog) → row **New**.
- AI returns a hidden product's id → row **Check** with "लुकाइएको छ — फेरि देखाउने?".

**BL-19 Leaving without saving**
- When: back with rows on screen → "बिल नसकी जाने? पढेको हराउँछ" → हो.
- Then: no delivery, no batches, no aliases; the read still counted; a product created in BL-6 stays (stock 0).

**BL-20 Nothing ticked** — स्टकमा थप्नुस् disabled.

**BL-21 Very long bill** — AI returns 80 lines and a note → all 80 shown with "धेरै लाइन — बाँकी अर्को फोटोमा खिच्नुस्".

**BL-22 Money never from the AI alone**
- AI returns qty 10, rate 18, no amount.
- Then: amount ₹180 computed; batch total ₹180; row Ready if the rest is high confidence.

### MB — Manual bill

**MB-1 Three products by tap**
- When: हातैले बिल → वाइवाइ 2 कार्टुन @ ₹390 → बिलमा थप्नुस्; अण्डा 90 @ ₹16; साबुन 24 @ ₹45 → save.
- Then: 1 delivery (`manual`, 3 batches, total ₹3,300); stock +60 / +90 / +24; no aliases.

**MB-2 Scan to add; unknown code**
- Scan वाइवाइ's code → its keypad sheet → row.
- Scan an unknown code → new-product form (code filled, no opening stock) → back with the row's sheet open for qty/cost.

**MB-3 Same product again** — tap अण्डा already in the list → its row's sheet opens (edit), no second row.

**MB-4 Edit and remove before saving** — change a row's qty; remove a row (✕) → totals update; nothing written until save.

**MB-5 Price change on one row** — साबुन sale price ₹60 → ₹65 → 1 priceChange `stock` on save.

**MB-6 Printed total typed** — total ₹3,400 typed, sum ₹3,300 → banner "बिलको जम्मा मिलेन" (BR5).

**MB-7 Cost missing** — row with no cost → saved, batch flagged cost missing (S-11).

**MB-8 Leave with rows** — "बिल नसकी जाने? थपेका ३ सामान हराउँछन्" → रद्द keeps the screen; हो discards.

**MB-9 Offline** — whole flow offline; delivery saved locally and synced later; stock updates at once.

**MB-10 Supplier and bill no.** — optional, as S-9.

---

## 6. Build order

1. Bill screen (shared): rows, row sheet (reuse add-stock sheet in "add to bill" mode), totals and checks, save as one delivery — **manual bill first** (no AI needed, works offline).
2. Data: `billAliases`, new optional delivery/batch fields, rules + tests; store method `receiveBill(...)` producing one `ShopChange`.
3. `readBill` Cloud Function (schema, checks, billReads limit, tests with a fake model).
4. Bill capture (1–3 pages), client + demo reader, mapping AI lines → rows (aliases, catalog check, packs, money checks).
5. New-product-from-row, change-product, remembered names.
6. Scenario tests BL-1…BL-22, MB-1…MB-10; web build + browser check.

## 7. Questions (answered: recommendation accepted)

| # | Question | Answer |
|---|---|---|
| Q1 | VAT and bill discount: spread into each batch's cost, or record on the delivery only? | **Spread** (BL-14) — most kirana shops aren't VAT-registered, so VAT is part of what the goods cost them. A shop switch for VAT-registered shops can come later. |
| Q2 | Keep the bill photo for the record? | **Not in v1** (D9). Later in Firebase Storage if shops ask for proof. |
| Q3 | 30 bill reads per day, separate from the 100 product-photo reads? | **Yes** (D10). |
| Q4 | Keep an unfinished manual bill if the app is closed (e.g. a customer comes)? | **v1: kept while the app is open** (leaving the bill screen asks first). Saving drafts across restarts later if needed. |
| Q5 | New product from a bill row: create it at once (D8), or only when the bill is saved, in the same write? | **At once** — reuses the form as is, and the product is useful even if the bill is abandoned. |
