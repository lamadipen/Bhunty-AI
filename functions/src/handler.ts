// readProductPhotos without Firebase: auth, input, quota, model, checks.
// index.ts wires in the real quota (Firestore) and model (Claude); tests pass fakes.
import { checkAnswer, checkInput, DAILY_LIMIT, ModelAnswer, PhotoInput, PhotoReadResult, ReadError } from "./photos";

export interface ModelReader {
  /** The model's structured answer, or "unreadable" (refusal / nothing usable). Throws when unavailable. */
  read(images: PhotoInput[], barcodeOnPhone?: string): Promise<ModelAnswer | "unreadable">;
}

export interface Quota {
  /** Adds one read for the shop today if under the limit; returns the new count, or null if the limit is reached. */
  take(shopId: string, limit: number): Promise<number | null>;
}

export type HandlerResult =
  | { ok: true; result: PhotoReadResult; usage: { today: number; limit: number } }
  | { ok: false; error: ReadError };

export async function handleReadPhotos(
  auth: { uid: string } | undefined,
  data: unknown,
  deps: { model: ModelReader; quota: Quota },
): Promise<HandlerResult> {
  if (!auth?.uid) return { ok: false, error: "unauthenticated" };
  const input = checkInput(data);
  if ("error" in input) return { ok: false, error: input.error };

  // Counted before the call, so a burst can't exceed the limit; a read that
  // fails still counts (it cost a model call) — see F-16.
  const today = await deps.quota.take(auth.uid, DAILY_LIMIT);
  if (today === null) return { ok: false, error: "limit-reached" };

  let raw: ModelAnswer | "unreadable";
  try {
    raw = await deps.model.read(input.images, input.barcodeOnPhone);
  } catch {
    return { ok: false, error: "unavailable" };
  }
  if (raw === "unreadable") return { ok: false, error: "unreadable" };
  const result = checkAnswer(raw);
  if (result === "unreadable") return { ok: false, error: "unreadable" };
  return { ok: true, result, usage: { today, limit: DAILY_LIMIT } };
}
