# Add a product from photos — spec and test scenarios

Status: **draft for review** (2026-10-24). Nothing here is implemented yet.
Builds on [product-addition.md](product-addition.md): every rule there still applies (codes, validation, batches, price changes). This spec only adds a faster way to **fill the new-product form**.

---

## 1. Decisions (agreed)

| # | Decision |
|---|---|
| D1 | Three labelled photo slots per product: **front** (thumbnail), **barcode** (optional), **label** (text: name, size, MRP). One photo per slot, replaceable. |
| D2 | Photos come from the **camera** or the **gallery / local files** (file picker on web). |
| D3 | The **front** photo is kept as the product's **thumbnail** (≈256 px). The barcode and label photos are used once to fill the form, then discarded. |
| D4 | Thumbnails live in **Firestore** (`productImages/{productId}`), so they save offline and sync like everything else. |
| D5 | The AI reads the **front + label** photos (and the barcode photo only if the phone couldn't read it). |
| D6 | AI = **Claude Haiku**, called from a **Cloud Function** (Firebase Blaze plan). The API key stays on the server (Secret Manager). |
| D7 | The AI **never sets prices, cost or stock**. MRP read from the packet is shown as a **hint only**; no warning when the selling price is above it. |
| D8 | **Daily limit: 100 AI reads per shop** (Nepal day), counted on the server. |

## 2. Flow

1. Entry points: Stock → **सामानको फोटो** card; New-product form → **फोटोबाट भर्नुस्** button.
2. **Capture screen — "फोटोबाट सामान थप्नुस्"**, three slots, each with 📷 *क्यामेरा* and 🖼️ *ग्यालरी/फाइल*, shown as a thumbnail with ✕ (remove) and ↻ (replace):
   - **१ सामानको फोटो** (front) — "ग्रिडमा देखिने फोटो"
   - **२ बारकोड** (optional) — "बारकोड भए खिच्नुस्"
   - **३ विवरण भएको फोटो** (label/back) — "नाम, तौल/मात्रा, MRP देखिने भाग"
3. **पढ्नुस्** (enabled when at least one photo is present):
   - Barcode photo → read **on the phone** (ML Kit; free, offline).
   - Front + label (+ barcode photo if not read) → Cloud Function → Claude Haiku → checked fields.
4. The **new-product form** opens pre-filled. AI-filled fields carry a small "भुन्टेले भरेको" tag; low-confidence ones are highlighted orange. MRP appears under the price field as "प्याकेटमा MRP: रु 25". The shopkeeper enters **selling price, cost and opening stock** on the keypad and saves as today.
5. On save: product (+ opening batch + initial price, as in product-addition.md) **and** the thumbnail, in the same write. Barcode and label photos are dropped from memory.

## 3. Rules

**PR1 — The AI only suggests.** Nothing is written until the shopkeeper taps save on the form. Every field stays editable.

**PR2 — Never prices.** The AI returns no selling price, cost or stock. If it reads an MRP, the app shows it as a hint; it is not saved and not pre-filled.

**PR3 — Barcode order.** (1) read on the phone from the barcode photo; (2) else the digits the AI read from any photo, kept only if they pass `checkProductCode` (check digit); (3) else empty — scan / type / own code as today. A barcode already in the shop opens "पहिल्यै छ: <name> — स्टक थप्ने?".

**PR4 — Name includes the size.** Different sizes are different products, so a read size is appended to the name: *वाइवाइ चिकेन 70g*. The shopkeeper can change it.

**PR5 — Unit.** The AI suggests one of वटा / प्याकेट / केजी / लिटर; anything else is dropped and the unit stays on the default.

**PR6 — Server checks the AI answer** before returning it: names ≤ 60 characters, no line breaks; unit in the enum; MRP an integer in paisa between रु 1 and रु 1,00,000; barcode passes the GTIN check; unknown fields dropped. Each field carries confidence `high` or `low`.

**PR7 — Images are shrunk on the phone** before anything else: photos sent to the AI ≤ 1024 px JPEG (quality ~80); thumbnail 256 px JPEG (quality ~70, target ≤ 30 KB, hard limit 60 KB).

**PR8 — Photos aren't stored except the thumbnail.** The Cloud Function doesn't save images; only the thumbnail is written to Firestore.

**PR9 — Daily limit.** Each successful AI read adds 1 to `aiUsage/{yyyy-mm-dd}` (Nepal day) for the shop; at 100 the function refuses with `limit-reached`. The app then says "आजको फोटो पढ्ने सीमा सकियो — हातैले भर्नुस्" and still keeps the thumbnail and on-phone barcode.

**PR10 — Offline.** Without internet: the thumbnail is kept, the barcode is read on the phone, and the form opens with "इन्टरनेट आएपछि फोटोबाट भर्न सकिन्छ"; the rest is filled by hand. No queue (the label photo isn't kept).

**PR11 — Thumbnails everywhere a product shows.** Grid tiles, cart rows and pickers show the thumbnail when there is one, else the letter tile. Edit product gains **फोटो थप्नुस् / बदल्नुस् / हटाउनुस्**.

## 4. Data and contract

```
productImages/{productId}            # one per product, separate so the catalog stays light
  jpegBase64        # ≤ 60 KB (rules), 256 px
  width, height, updatedAt, updatedBy

products/{productId}
  hasImage: bool    # tiles know to load the thumbnail
  imageUpdatedAt?   # cache key

aiUsage/{yyyy-mm-dd}                 # written only by the Cloud Function
  photoReads: int
```

**Cloud Function `readProductPhotos`** (callable; signed-in users only, the shop = their uid):

```
in:  { images: [ { role: "front" | "label" | "barcode", jpegBase64 } ],   # 1–3 images, ≤ 400 KB each
       barcodeOnPhone?: string }                                          # already read on the phone
out: { nameNe?, nameEn?, brand?, sizeText?,          # e.g. "70 g", "1 L", "12 pcs"
       unit?: "piece" | "packet" | "kg" | "litre",
       mrpPaisa?: int, barcode?: string,
       confidence: { <field>: "high" | "low" },
       notes?: string,                                # e.g. "नाम प्रस्ट भएन"
       usage: { today: int, limit: 100 } }
errors: unauthenticated | invalid-argument (too many / too big) | limit-reached | unreadable | unavailable
```

The model is called with a fixed tool/JSON schema, temperature 0, and told: read only what is printed; leave a field out rather than guess; never output prices other than MRP.

**Security rules (planned):** `productImages` — owner read/write/delete, `jpegBase64` is a string ≤ 80,000 chars; `aiUsage` — owner read-only (function writes with admin rights).

**Setup (one time):** upgrade the Firebase project to **Blaze**, add a **budget alert**, `firebase functions:secrets:set ANTHROPIC_API_KEY`, `firebase deploy --only functions,firestore:rules`.

---

## 5. Scenarios (test reference)

Format: Given → When → Then. "AI returns" means the (faked in tests) Cloud Function reply.

**F-1 All three photos (the main case)**
- When: front, barcode and label photos of Wai Wai Chicken 70g → पढ्नुस्.
- Phone reads barcode `8901234567890`*; AI returns nameNe "वाइवाइ चिकेन", nameEn "Wai Wai Chicken", sizeText "70 g", unit packet, mrp ₹25 (all high).
- Then: form shows name "वाइवाइ चिकेन 70g", English "Wai Wai Chicken 70g", unit प्याकेट, barcode filled, "प्याकेटमा MRP: रु 25" hint; price/cost/stock empty. User enters ₹25 / ₹18 / 30 → save → product + opening batch + initial price + `productImages` doc (≤ 60 KB); grid tile shows the photo; aiUsage today +1.
- \* any valid EAN-13 in tests.

**F-2 Front photo only**
- AI returns name from the front; no barcode, no MRP.
- Then: name filled; barcode empty (scan / type / own code still offered); thumbnail saved.

**F-3 Barcode photo unreadable on the phone**
- Phone read fails; AI returns barcode digits.
- Then: digits that pass the check digit are filled (tag "भुन्टेले भरेको"); digits that fail are dropped and the barcode field shows "बारकोड पढ्न सकिएन — स्क्यान वा नम्बर लेख्नुस्".

**F-4 Barcode already in the shop**
- Phone reads the barcode of existing वाइवाइ.
- Then: before the form, a sheet "पहिल्यै छ: वाइवाइ — स्टक थप्ने?" → yes opens the add-stock sheet; no returns to the capture screen.

**F-5 Offline**
- When: no internet → पढ्नुस्.
- Then: no AI call; barcode read on the phone; form opens with the offline note; thumbnail saved with the product and synced later; aiUsage unchanged.

**F-6 AI unsure**
- AI returns nameNe with confidence low (blurry).
- Then: name field highlighted orange; user must look at it (no extra blocking).

**F-7 Not a product**
- AI returns `unreadable`.
- Then: "फोटोबाट पढ्न सकिएन — अर्को फोटो खिच्नुस् वा हातैले भर्नुस्"; capture screen stays with photos.

**F-8 Daily limit reached**
- 100 reads already today.
- Then: `limit-reached` message; form opens for manual fill; thumbnail and on-phone barcode still used; the 101st read is not counted.

**F-9 AI answer with invalid fields**
- Model output: unit "box", mrp "25.5 rs", 120-character name.
- Then: server drops unit and MRP, rejects the name; app fills nothing for those.

**F-10 Loose goods**
- Label photo of a rice sack: "Jeera Masino Rice 25 kg".
- Then: name "जिरा मसिनो चामल" (AI's Nepali), unit केजी suggested, sizeText "25 kg" **not** appended to the name for केजी/लिटर (the unit already says it); opening stock entered by the user (e.g. 25).

**F-11 Thumbnail on an existing product**
- Edit product (sample चामल) → फोटो थप्नुस् → camera.
- Then: `productImages/rice` written; `products/rice.hasImage` true; grid shows the photo. Works offline.

**F-12 Remove / replace thumbnail**
- Replace → doc overwritten, `imageUpdatedAt` changes. Remove → doc deleted, `hasImage` false, letter tile returns.

**F-13 From files on the web**
- When: on web, pick three files from disk.
- Then: same flow; the barcode is read from its photo by the AI (the phone reader isn't available on web).

**F-14 AI never fills money or stock**
- Even with MRP printed and "Net qty 24 pcs" on the label.
- Then: price, cost and stock stay empty; MRP only as a hint; "24 pcs" goes to the name (and may suggest a pack of 24 only as a hint, not filled).

**F-15 Huge photo**
- 12 MP photo picked.
- Then: shrunk on the phone to ≤ 1024 px before sending and to 256 px for the thumbnail; the function never receives > 400 KB per image.

**F-16 Cancel**
- When: user leaves the capture screen or the form without saving.
- Then: nothing saved; the AI read (if it happened) still counts toward the day.

**F-17 Not signed in / function missing**
- Demo mode (no Firebase) or function not deployed.
- Then: the photo button still works for the thumbnail and barcode; AI fill shows "फोटोबाट भर्ने सुविधा अहिले उपलब्ध छैन". Demo mode uses a scripted fake reader so the flow can be tried.

---

## 6. Build order

1. `functions/` (TypeScript): `readProductPhotos`, schema + output checks, usage counter, tests with a fake model.
2. App: capture screen (image_picker: camera + gallery/files, resizing), on-phone barcode from image, `PhotoReader` interface (Cloud Function client + demo fake).
3. Form pre-fill with tags/highlights, MRP hint; thumbnail save with the product.
4. Thumbnails in tiles/cart/pickers; edit product add/replace/remove.
5. Rules for `productImages` / `aiUsage`, rules tests; setup docs (Blaze, secret, budget alert).
