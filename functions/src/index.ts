// Cloud Functions entry point. Setup: docs/product-photos.md §4 (Blaze plan,
// ANTHROPIC_API_KEY secret, budget alert).
import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { ClaudeReader } from "./claude";
import { handleReadPhotos, Quota } from "./handler";
import { nepalDayKey } from "./photos";

initializeApp();

const anthropicKey = defineSecret("ANTHROPIC_API_KEY");

/** Daily reads per shop in shops/{uid}/aiUsage/{yyyy-mm-dd} (Nepal day). Server-side transaction. */
const firestoreQuota: Quota = {
  async take(shopId, limit) {
    const db = getFirestore();
    const ref = db.doc(`shops/${shopId}/aiUsage/${nepalDayKey(new Date())}`);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.get("photoReads") as number | undefined) ?? 0;
      if (used >= limit) return null;
      tx.set(ref, { photoReads: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return used + 1;
    });
  },
};

export const readProductPhotos = onCall(
  { secrets: [anthropicKey], region: "asia-south1", memory: "512MiB", timeoutSeconds: 60, maxInstances: 20 },
  async (request) => {
    const outcome = await handleReadPhotos(request.auth ?? undefined, request.data, {
      model: new ClaudeReader(new Anthropic({ apiKey: anthropicKey.value() })),
      quota: firestoreQuota,
    });
    if (outcome.ok) return { ...outcome.result, usage: outcome.usage };
    switch (outcome.error) {
      case "unauthenticated":
        throw new HttpsError("unauthenticated", "Sign in first");
      case "invalid-argument":
        throw new HttpsError("invalid-argument", "1-3 JPEG images, each under 400 KB");
      case "limit-reached":
        throw new HttpsError("resource-exhausted", "limit-reached");
      case "unreadable":
        throw new HttpsError("failed-precondition", "unreadable");
      default:
        throw new HttpsError("unavailable", "ai-unavailable");
    }
  },
);
