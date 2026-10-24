// Cloud Functions entry point. Setup: docs/product-photos.md §4 (Blaze plan,
// ANTHROPIC_API_KEY secret, budget alert).
import Anthropic from "@anthropic-ai/sdk";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { defineSecret } from "firebase-functions/params";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { ClaudeBillReader, ClaudeReader } from "./claude";
import { handleReadBill, handleReadPhotos, Quota } from "./handler";
import { ReadError } from "./photos";
import { nepalDayKey } from "./photos";

initializeApp();

const anthropicKey = defineSecret("ANTHROPIC_API_KEY");

/** Daily reads per shop in shops/{uid}/aiUsage/{yyyy-mm-dd} (Nepal day). Server-side transaction. */
const firestoreQuota: Quota = {
  async take(shopId, counter, limit) {
    const db = getFirestore();
    const ref = db.doc(`shops/${shopId}/aiUsage/${nepalDayKey(new Date())}`);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.get(counter) as number | undefined) ?? 0;
      if (used >= limit) return null;
      tx.set(ref, { [counter]: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
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
    throw toHttpsError(outcome.error);
  },
);

export const readBill = onCall(
  { secrets: [anthropicKey], region: "asia-south1", memory: "512MiB", timeoutSeconds: 120, maxInstances: 20 },
  async (request) => {
    const outcome = await handleReadBill(request.auth ?? undefined, request.data, {
      model: new ClaudeBillReader(new Anthropic({ apiKey: anthropicKey.value() })),
      quota: firestoreQuota,
    });
    if (outcome.ok) return { ...outcome.result, usage: outcome.usage };
    throw toHttpsError(outcome.error);
  },
);

/** The app reads the reason from the message (app/lib/photos/cloud_photo_reader.dart). */
function toHttpsError(error: ReadError): HttpsError {
  switch (error) {
    case "unauthenticated":
      return new HttpsError("unauthenticated", "Sign in first");
    case "invalid-argument":
      return new HttpsError("invalid-argument", "Too many or too large images");
    case "limit-reached":
      return new HttpsError("resource-exhausted", "limit-reached");
    case "unreadable":
      return new HttpsError("failed-precondition", "unreadable");
    default:
      return new HttpsError("unavailable", "ai-unavailable");
  }
}
