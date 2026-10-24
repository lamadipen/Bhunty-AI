# Bhunte AI — Cloud Functions

Two callables (region `asia-south1`), both **Claude Haiku**, both read-only — the app shows the result and the shopkeeper saves:

- `readProductPhotos`: up to three product photos → suggested form fields (`docs/product-photos.md`).
- `readBill`: 1–3 bill pages + the shop's catalog → lines, matches and header (`docs/stock-from-bill.md`).

- `src/photos.ts` — input checks, the model's answer schema, the server-side checks on the answer (PR6), Nepal day.
- `src/bill.ts` — the same for bills: page/catalog limits, line and header checks, catalog-only product ids, Nepali phone numbers.
- `src/handler.ts` — the flow without Firebase: auth → input → daily limit → model → checks.
- `src/claude.ts` — the Claude call (structured outputs, low effort; a refusal counts as unreadable).
- `src/index.ts` — Firebase wiring: secret, Firestore counter at `shops/{uid}/aiUsage/{yyyy-mm-dd}`.

```bash
npm install
npm test          # compiles and runs test/ with a fake model and counter — no key, no network
```

## Deploy (one time per project)

1. Upgrade the Firebase project to the **Blaze** plan (functions need it) and add a **budget alert** (Google Cloud console → Billing → Budgets & alerts), e.g. $10/month.
2. Store the Anthropic API key in Secret Manager — never in the repo or the app:
   ```bash
   firebase functions:secrets:set ANTHROPIC_API_KEY --project <your-project>
   ```
3. From the repo root:
   ```bash
   firebase deploy --only functions,firestore:rules --project <your-project>
   ```

Each shop gets 100 product-photo reads and 30 bill reads per Nepal day (`DAILY_LIMIT` in `src/photos.ts`, `BILL_DAILY_LIMIT` in `src/bill.ts`), counted in `shops/{uid}/aiUsage/{day}` as `photoReads` / `billReads`. A read is counted before the model is called, so failed reads count too.
