# Architecture (draft v2)

## Overview

```
Flutter app (Android / iOS / web)          app/
 ├─ Local: Firestore offline cache, ML Kit barcode, keypad/tap-grid checkout
 ├─ Firebase Auth (phone OTP)
 ├─ Firestore  ── shops/{shopId}/...
 ├─ Storage    ── bill + product photos
 └─ Cloud Functions (AI wrapper)             functions/ (not yet created)
       ├─ parseVoice(audio | transcript)  → proposed actions
       ├─ parseBill(photoUrl)             → proposed stock lines + confidence
       ├─ matchProduct(photoUrl)          → candidate products from this shop's catalog
       └─ askBhunte(question)             → answer built from code-run queries
```

The app never sends a model's output straight to Firestore. Flow for every AI feature:

1. App sends input (audio/transcript/photo) to a Cloud Function.
2. Function calls the LLM with tool definitions; the model returns tool calls.
3. Function validates each call (product exists, qty > 0, customer exists, prices from the catalog not the model).
4. App shows confirmation card(s). User taps ✓.
5. App writes the transaction to Firestore (works offline; syncs later).

## Units

- **Money:** integer **paisa** (`int`). रु 25 = `2500`. Never `double`.
- **Quantity:** integer **milli-units** (`int`). 1 piece = `1000`, आधा केजी = `500` with `unit: "kg"`. Lets loose goods (kg, litre) and pieces share one code path.
- **Time:** UTC timestamps; day boundaries and `yyyy-mm-dd` keys in **Asia/Kathmandu (UTC+5:45)**. UI shows Bikram Sambat dates.

## Firestore data model (draft)

```
shops/{shopId}                        # shopId = owner's uid for now (one owner, one shop)
  name, ownerUid, currency: "NPR", createdAt
  products/{productId}
    name_ne, name_en, pricePaisa, costPaisa, barcode?, unit: "pc"|"kg"|"l"|"packet",
    stockMilli, photoUrl?, isFavourite, lowStockAtMilli, letter, tileBg, tileInk
  productEmbeddings/{productId}       # kept apart so catalog reads stay small
    vector, model, updatedAt
  sales/{saleId}                      # id generated on device (idempotent sync)
    items: [{productId, name, qtyMilli, pricePaisa, lineTotalPaisa}],
    subtotalPaisa, discountPaisa, totalPaisa,
    payments: [{method: "cash"|"qr"|"udharo", amountPaisa}],
    tenderedPaisa?, changePaisa?, customerId?,
    createdAt (client), syncedAt (server), day (yyyy-mm-dd, NPT), createdBy (uid), voidedAt?
  stockEntries/{entryId}
    source: "bill_photo" | "product_photo" | "voice" | "manual",
    photoUrl?, lines: [{productId, qtyMilli, costPaisa}], totalPaisa, createdAt, createdBy
  customers/{customerId}
    name, initial, phone?, balancePaisa, lastNote, lastActivityAt
    ledger/{entryId}
      type: "credit" | "payment", amountPaisa, saleId?, note?, createdAt
  dailySummaries/{yyyy-mm-dd}         # NPT day; history/reports only
    totalPaisa, cashPaisa, qrPaisa, udharoPaisa, saleCount, topItems
```

Notes:
- **Offline writes use batched writes with `FieldValue.increment()`**, not `runTransaction` (transactions need the server and fail offline). A sale is one batch: the sale doc, `stockMilli` decrements per product, and for udharo a ledger entry + `balancePaisa` increment. In the app: `ShopStore` builds a `ShopChange`, `FirestoreBackend.commit` turns it into one `WriteBatch` and does not await it (offline it completes only after sync).
- The app listens to `products`, `customers` and `sales where day == today`; the `day` field makes "today" one equality query on a single-field index.
- Security rules (`firestore.rules`, tested in `rules-test/`): owner-only access, int money fields, sales/ledger/stockEntries append-only, `dailySummaries` server-only.
- `stockMilli` and `balancePaisa` are caches. A Cloud Function reconciles them from `stockEntries`/`sales`/`ledger` nightly and flags drift.
- The Home "today's sales" card is computed on device from today's cached sales, so it is right offline. `dailySummaries` are maintained by a Cloud Function trigger for history and reports (keeps Firestore read costs down).
- Mistakes are corrected with reversing entries (`voidedAt`, a negative ledger entry), never deletes.

## LLM tool definitions (draft)

| Tool | Arguments | Effect after user confirms |
|---|---|---|
| `add_to_cart` | productId, qtyMilli | Adds line to current cart |
| `set_quantity` / `remove_from_cart` | productId, qtyMilli? | Edits the cart |
| `record_credit` | customerId \| newCustomerName, amountPaisa | Ledger credit + balance up |
| `record_payment` | customerId, amountPaisa | Ledger payment + balance down |
| `add_stock` | lines: [{productId \| newProductName, qtyMilli, costPaisa, confidence}] | Stock entry + stock up |
| `create_product` | name_ne, name_en?, pricePaisa, unit | New catalog item |
| `query` | metric: "sales_today" \| "low_stock" \| "customer_balance" \| "top_items", params | Read-only; answer computed in code and filled into a fixed sentence |
| `unclear` | reason | Nothing; app asks the user to repeat |

The model resolves names to IDs using the shop's catalog/customer list passed in context (keep it small: favourites + fuzzy-matched candidates). A `newCustomerName` / `newProductName` is always shown as "नयाँ" on the confirm card with the closest existing matches offered first.

In the app, these map to `ProposedAction` subclasses (`app/lib/ai/proposed_action.dart`); only `ShopStore.apply()` commits them, after the user taps ✓.

## Open questions

- LLM provider and model choice (cost per shop per month target?)
- Speech-to-text provider for Nepali
- Payment integration route: Fonepay dynamic QR vs eSewa/Khalti merchant APIs
- Multi-device per shop (owner + helper), roles in security rules, and conflict handling
- Receipt delivery: Viber, SMS, or printed (Bluetooth thermal printer)
