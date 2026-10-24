# Bhunte AI — Cloud Functions

`readProductPhotos` (callable, region `asia-south1`): reads up to three product photos with **Claude Haiku** and returns suggested form fields. It never writes products, prices or stock — the app shows the result and the shopkeeper saves (spec: `docs/product-photos.md`).

- `src/photos.ts` — input checks, the model's answer schema, the server-side checks on the answer (PR6), Nepal day.
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

Each shop gets 100 photo reads per Nepal day (`DAILY_LIMIT` in `src/photos.ts`). A read is counted before the model is called, so failed reads count too.
