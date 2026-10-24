# Product addition — spec and test scenarios

Status: **implemented (first version)**, 2026-10-19. Tests named by scenario ID: `app/test/batches_test.dart` (plus `product_complete_test.dart`, `labels_test.dart`, `rules-test/`). What is still planned is listed in §6.
Scope: adding products, receiving stock in **batches**, and the **sale price** rule.
Out of scope for now: profit, cost averaging, purchase reports (they will be built from the data recorded here).

---

## 1. Terms

| Term | Meaning |
|---|---|
| **Product** | One item the shop sells at one price, e.g. *वाइवाइ 70g*. Different sizes are different products. |
| **Selling unit** | How the product is counted and sold: वटा (piece), प्याकेट, केजी, लिटर. Stock is always in selling units. |
| **Pack** | How the wholesaler sells it, e.g. *कार्टुन = 30 प्याकेट*. Only used to enter stock; converted to selling units. |
| **Batch** | One arrival of stock for one product: quantity, **cost price**, **sale price**, date, who, how. Opening stock is the first batch. Batches are never edited or deleted. |
| **Delivery** | One bill / one save of the stock screen. Groups one or more batches (a 6-line wholesaler bill = 1 delivery with 6 batches). |
| **Price change** | Every time a product's sale price is set or changed: on creation, with a batch, or by editing the product. The full price history. |
| **Code** | A product's barcode/QR value: printed on the packet (scanned/typed) or made by the shop (**own code**, EAN-13 starting with 2). |

## 2. Rules

**R1 — One sale price per product, the latest one.** The product's sale price is the `newPrice` of its most recent **price change**. Every sale uses that price for all stock on the shelf, old and new batches alike.

**R2 — Every batch records its own cost and sale price.** Cost per selling unit (and the bill total exactly as written), and the sale price in effect after this batch.

**R3 — A batch whose sale price differs from the current price creates a price change** (reason `stock`, linked to the batch). A batch at the same price creates no price change.

**R4 — Editing the price without new stock creates a price change** (reason `manual`).

**R5 — Creating a product creates its first price change** (reason `initial`), with or without opening stock.

**R6 — "Latest" means latest by time recorded** (`createdAt`). Order of arrival at the server must not decide it (see S-14, offline).

**R7 — Sales keep the price they were sold at.** A later price change never alters past sales. The price used is the product's price **when the sale is completed** (payment confirmed), not when the item was put in the cart.

**R8 — History is append-only.** Batches, deliveries and price changes are never edited or deleted. A wrong batch is corrected by a **correction entry** (planned, see S-12).

**R9 — Cost is never averaged here.** The product shows the **last batch's cost per unit** as a reference (e.g. the default in the next stock entry). Profit and averages are computed later from batches.

**R10 — Money is integer paisa; quantity is integer milli-units.** Sale price is always **per selling unit**. Cost may be entered per pack and is converted: `unit cost = pack cost ÷ pack size`, rounded to the paisa; the batch keeps the exact bill total.

**R11 — Supplier and bill number are optional on a delivery.** Supplier is identified by phone number when given (supplier records come later).

**R12 — Codes.** A code may be saved only if it is a product code: GTIN (EAN-8, UPC-A, EAN-13, GTIN-14; typed ones must pass the check digit) or a short alphanumeric distributor code. UPC-A is stored as EAN-13 (leading 0); GTIN-14 with indicator 0 as its EAN-13. A code belongs to at most one product (hidden ones included).

**R13 — Unit is locked once the product has stock.** Changing it would change what the stored quantities mean.

## 3. Data model (Firestore)

All under `shops/{shopId}/`. Every write for one user action is **one batched write** (works offline).

```
products/{productId}
  name_ne, name_en, unit, packName?, packSizeMilli?
  pricePaisa            # current sale price  = newPrice of latest priceChanges (cache)
  priceSetAt            # createdAt of that price change (for R6)
  costPaisa             # unit cost of the latest batch (reference, R9)
  stockMilli            # cache; changed only by FieldValue.increment
  lowStockAtMilli, barcode?, ownCode, labelKind?, archived, isFavourite
  sortOrder, createdAt

deliveries/{deliveryId}              # one bill / one save
  source: opening | manual | bill_photo | voice
  supplierName?, supplierPhone?, billNo?, photoUrl?
  totalCostPaisa, batchCount, createdAt, createdBy

batches/{batchId}                    # one product in one delivery
  deliveryId, productId, productName      # name copied for reports
  qtyMilli                                # selling units added
  enteredAs: unit | pack, packName?, packSizeMilli?, packsMilli?
  unitCostPaisa                           # cost per selling unit (rounded)
  totalCostPaisa                          # exactly as on the bill
  salePricePaisa                          # sale price in effect after this batch
  source, createdAt, createdBy
  # planned: correctsBatchId?, expiry?

priceChanges/{changeId}
  productId, oldPricePaisa?, newPricePaisa
  reason: initial | stock | manual
  batchId?, createdAt, createdBy

sales/{saleId}            # unchanged: items[].pricePaisa is the price used (R7)
```

Replaces today's `stockEntries` (one doc with a `lines` array). Separate `batches` docs can be queried per product, which purchase reports need.

**Security rules (planned):** `deliveries`, `batches`, `priceChanges` are create-only for the shop owner. Money fields must be int; `qtyMilli > 0` (until corrections exist); `newPricePaisa > 0`.

## 4. What each action writes

| Action | products | deliveries | batches | priceChanges |
|---|---|---|---|---|
| New product, no stock | create (stock 0) | — | — | 1 × `initial` |
| New product + opening stock | create (stock 0 → +qty) | 1 × `opening` | 1 | 1 × `initial` (linked to the batch) |
| Add stock, same price | stock +, lastCost | 1 | 1 per product | — |
| Add stock, new price | stock +, lastCost, price | 1 | 1 per product | 1 × `stock` per changed product |
| Bill photo, 6 lines ticked | 6 products updated | 1 × `bill_photo` | 6 | one per line whose price changed |
| Edit price only | price | — | — | 1 × `manual` |
| Edit other details | details (never stock) | — | — | — |

---

## 5. Scenarios (test reference)

Format: **Given** (starting data) → **When** (what the shopkeeper does) → **Then** (what must be true). Money in rupees for readability; stored as paisa. "Price" = sale price.

### A. Creating products

**A-1 New product with a barcode on the packet and opening stock**
- Given: no product "कोक 250ml".
- When: Stock → नयाँ सामान → scan `4006381333931` → name कोक 250ml, unit वटा, cost ₹50, price ₹60, opening stock 24 → सामान थप्नुस्.
- Then:
  - product: price ₹60, lastCost ₹50, stock 24, barcode `4006381333931`, ownCode false.
  - delivery: source `opening`, total ₹1,200, 1 batch.
  - batch: qty 24, unitCost ₹50, total ₹1,200, salePrice ₹60.
  - priceChange: `initial`, old —, new ₹60, linked to the batch.
  - Scanning `4006381333931` on Sell adds कोक to the cart at ₹60.

**A-2 New product, no barcode, shop's own code**
- When: नयाँ सामान → name जिरा 50g, प्याकेट, cost ₹30, price ₹40, opening 10 → **आफ्नै कोड** → QR → save.
- Then: code is EAN-13 starting with `2`, check digit valid, unique in the shop; ownCode true; labelKind `qr`; one `opening` batch (10 @ ₹30, price ₹40); `initial` price ₹40; the label screen opens.

**A-3 New product without stock**
- When: name मह 500g, cost ₹400, price ₹450, opening stock 0 → save.
- Then: product stock 0, price ₹450, lastCost ₹400; **no** delivery or batch; priceChange `initial` ₹450.

**A-4 New product bought in cartons**
- When: name वाइवाइ, प्याकेट, pack कार्टुन × 30; opening stock entered as 2 कार्टुन at ₹540/कार्टुन; price ₹25/प्याकेट.
- Then: stock 60 प्याकेट; batch enteredAs `pack` (2 कार्टुन × 30), unitCost ₹18, total ₹1,080, salePrice ₹25.

**A-5 Loose goods (kg)**
- When: name चिनी, unit केजी, opening 25 kg at ₹105/kg, price ₹120/kg.
- Then: stock 25 kg; batch total ₹2,625. Selling 0.5 kg charges ₹60; stock 24.5 kg.

**A-6 Pack cost that doesn't divide evenly**
- When: carton of 24 at ₹1,000; 1 carton.
- Then: unitCost ₹41.67 (rounded), batch total **exactly ₹1,000**.

**A-7 Unknown code at the counter**
- Given: code `0036000291452` unknown.
- When: Sell → स्क्यान (UPC-A `036000291452` read) → "यो सामान पसलमा छैन" → नयाँ सामान थप्नुस् → name, price ₹80 → save.
- Then: product saved with code `0036000291452` (EAN-13 form); it's in the cart at ₹80; priceChange `initial` ₹80.

**A-8 Created offline**
- When: A-1 with no internet.
- Then: the product is usable immediately (Sell, Stock); all docs are written when back online, as one batch; nothing duplicated.

### B. Codes (validation)

| # | Input | Expected |
|---|---|---|
| B-1 | Typed `4006381333932` (wrong last digit) | Refused: "अङ्क मिलेन, एक पटक फेरि हेर्नुस्" |
| B-2 | Scanned Fonepay QR | Refused: "यो सामानको कोड होइन…", scanner stays open |
| B-3 | Scanned `https://…` | Refused, scanner stays open |
| B-4 | Code already on वाइवाइ | "यो बारकोड "वाइवाइ" मा छ" |
| B-5 | Code on a hidden product साबुन | "यो कोड लुकाइएको "साबुन" मा छ" |
| B-6 | Scanned `2100001234560` (real weighed-item code) | Saved as a normal code, ownCode **false**, no label printing offered |
| B-7 | Camera permission denied | Message + retry; "नम्बर हातैले लेख्नुस्" works |
| B-8 | Distributor code ` ab-123 ` | Saved as `AB-123` |

### C. Validation of the product form

| # | Input | Expected |
|---|---|---|
| C-1 | Name empty | "सामानको नाम लेख्नुस्" |
| C-2 | Name = existing चिनी | "यो नामको सामान पहिल्यै छ" |
| C-3 | Name = hidden साबुन | Points to "लुकाइएका सामान" |
| C-4 | Price 0 | "बेच्ने मूल्य लेख्नुस्" |
| C-5 | Pack बोरा chosen, size empty | "एक बोरामा कति छ, लेख्नुस्" |
| C-6 | Price ₹25 below cost ₹30 | Allowed, warning shown ("किनेको भन्दा सस्तो…") |

### S. Receiving stock (batches)

All start from: **वाइवाइ — stock 10, lastCost ₹10, price ₹15** (one earlier batch: 10 @ ₹10, price ₹15).

**S-1 Same cost, same price**
- When: Stock → वाइवाइ → 20 प्याकेट, cost ₹10 (pre-filled), price ₹15 (pre-filled) → save.
- Then: stock 30; new batch 20 @ ₹10, salePrice ₹15; **no** price change; price stays ₹15.

**S-2 Cost up, price up — the main case**
- When: 10 प्याकेट, cost ₹13, price changed to ₹18 → save.
- Then:
  - stock 20; lastCost ₹13; **price ₹18**.
  - batch #2: 10 @ ₹13, total ₹130, salePrice ₹18.
  - priceChange: `stock`, ₹15 → ₹18, linked to batch #2.
  - batch #1 still says 10 @ ₹10, salePrice ₹15 (history unchanged).
  - Selling 3 packets now charges ₹54 (3 × ₹18), whichever batch they physically came from.
  - A sale completed before this delivery still shows ₹15 per packet.

**S-3 Cost up, price kept**
- When: 10 @ ₹13, price left at ₹15.
- Then: batch salePrice ₹15; no price change; price ₹15; lastCost ₹13.

**S-4 Cost down, price down**
- When: 10 @ ₹9, price ₹14.
- Then: priceChange `stock` ₹15 → ₹14; price ₹14.

**S-5 Entered in cartons, priced per packet**
- Given: वाइवाइ pack = कार्टुन × 30.
- When: 2 कार्टुन at ₹390/कार्टुन, price ₹18/प्याकेट.
- Then: stock +60; batch enteredAs pack (2 × 30), unitCost ₹13, total ₹780, salePrice ₹18; priceChange ₹15 → ₹18.

**S-6 Bill photo with several products**
- Given: bill read with 6 lines; 2 unsure lines unticked.
- When: shopkeeper ticks 4 lines; changes the price on one of them (चिनी ₹120 → ₹125); save.
- Then: 1 delivery (`bill_photo`, 4 batches, total = sum of the 4 lines); 4 batches with their own cost; 1 priceChange (चिनी); unticked lines write nothing.

**S-7 Voice**
- When: "२० वटा साबुन आयो" → confirm card → ठीक छ.
- Then: 1 delivery (`voice`), 1 batch 20 @ last cost, salePrice = current price; no price change.

**S-8 Stock had gone negative**
- Given: वाइवाइ stock −3 (sold more than recorded).
- When: 10 arrive.
- Then: stock 7; batch qty 10 (batches record what arrived, not the gap).

**S-9 Supplier and bill number (optional)**
- When: S-2 with supplier "राम ट्रेडर्स", phone 98XXXXXXXX, bill no. 1452.
- Then: delivery stores supplierName, supplierPhone, billNo. Without them, the delivery saves the same and the fields are empty.

**S-10 Two products in one save**
- When: on the same screen, receive वाइवाइ 10 @ ₹13 (price ₹18) and अण्डा 30 @ ₹16 (price kept).
- Then: 1 delivery, 2 batches, 1 priceChange (वाइवाइ).
- First version: works for bill-photo saves and in the data layer; by hand, the Stock screen saves one product per entry (a "manual bill" screen for several products is planned).

**S-11 Quantity zero / no cost**
- When: qty 0 → save is disabled. Cost blank → batch saved with cost ₹0 and marked "cost missing" (shows in reports for follow-up).

**S-12 Wrong batch (planned: correction entry)**
- When: 100 entered instead of 10, noticed later.
- Then: a correction entry −90 linked to the original batch (reason, who, when). The original batch is not edited. *(Planned; not part of the first implementation.)*

### P. Price changes without stock

**P-1 Manual price change**
- When: Edit product → price ₹15 → ₹17 → save.
- Then: priceChange `manual` ₹15 → ₹17; price ₹17; no batch; stock unchanged.

**P-2 Latest by time, whichever kind**
- 10:00 batch with price ₹18 → price ₹18.
- 11:00 manual change to ₹17 → price ₹17.
- 12:00 batch, price field pre-filled ₹17 and kept → no new priceChange; price ₹17.

**P-3 Same price "changed"**
- When: edit and save with the same price.
- Then: no priceChange is written.

**P-4 Price changed while an item is in the cart**
- Given: cart has 2 वाइवाइ at ₹15.
- When: on another phone the price becomes ₹18; then this phone completes the sale.
- Then: the sale uses the price known to this phone **at payment**; if the change has synced, ₹36, otherwise ₹30. The sale records the price it used (R7).

**P-5 Own-code product with price printed on labels**
- When: price ₹40 → ₹45 (manual or with a batch).
- Then: "नयाँ लेबल छाप्ने?" is offered; printed labels are not changed automatically, and scanning always gives ₹45.

**P-6 Two phones, offline (R6)**
- Phone A (offline) at 10:00 receives वाइवाइ with price ₹18. Phone B (online) at 10:05 changes price to ₹17. Phone A comes online at 10:30.
- Expected: price **₹17** (B's change is later by time).
- Known limit of the first version: without a server function, the last write to *arrive* wins (₹18). Planned fix: a Cloud Function on `priceChanges` that sets the product price to the newest `createdAt`.

### E. Editing and hiding

| # | Action | Expected |
|---|---|---|
| E-1 | Rename वाइवाइ → वाइवाइ चाउचाउ | Name changes; history (batches, sales) keeps the name it had at the time |
| E-2 | Change unit while stock > 0 | Not allowed: "स्टक भएकोले एकाइ बदल्न मिल्दैन" |
| E-3 | Change unit while stock = 0 | Allowed |
| E-4 | Replace a scanned code | New code saved; old code no longer finds it |
| E-5 | Remove an own code that has printed labels | Confirmation first: "छापिएका लेबल अब स्क्यान हुँदैनन्" |
| E-6 | Hide a product | Leaves Sell/Stock grids and low-stock list; batches, price history and sales stay |
| E-7 | Scan a hidden product's code | "लुकाइएको छ — फेरि देखाउने?" → yes → visible and usable |
| E-8 | Edit never changes stock | Another phone's sale during the edit is not overwritten |

---

## 6. Status

Done in the first version:
1. `deliveries` + `batches` + `priceChanges` replace `stockEntries` (old `stockEntries` stay readable, no new writes).
2. Add-stock sheet: **sale price** field pre-filled with the current price, change note, cost-missing note (S-1…S-5, S-11).
3. Bill-photo review: sale price per line, pre-filled; optional supplier/bill (S-6, S-9).
4. Product creation writes the `initial` price change (linked to the opening batch); edit writes `manual` only when the price changes (A-3, P-1, P-3).
5. Product keeps `costPaisa` (latest batch's unit cost) and `priceSetAt`.
6. Opening stock and its cost can be entered in packs on the new-product form (A-4).
7. Security rules for the new collections, with emulator tests.

Still planned:
- A "manual bill" screen to receive several products in one save by hand (S-10).
- Correction entries (S-12), supplier records, server-side "latest price wins" across offline phones (P-6).
- Purchase reports and profit, built from `batches` and `priceChanges`.
