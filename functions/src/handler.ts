// readProductPhotos without Firebase: auth, input, quota, model, checks.
// index.ts wires in the real quota (Firestore) and model (Claude); tests pass fakes.
import { BILL_DAILY_LIMIT, BillAnswer, BillResult, CatalogItem, checkBillAnswer, checkBillInput } from "./bill";
import { checkAnswer, checkInput, DAILY_LIMIT, ModelAnswer, PhotoInput, PhotoReadResult, ReadError } from "./photos";

export interface ModelReader {
  /** The model's structured answer, or "unreadable" (refusal / nothing usable). Throws when unavailable. */
  read(images: PhotoInput[], barcodeOnPhone?: string): Promise<ModelAnswer | "unreadable">;
}

export interface BillModelReader {
  /** The model's structured answer, or "unreadable". Throws when unavailable. */
  read(pages: string[], catalog: CatalogItem[]): Promise<BillAnswer | "unreadable">;
}

/** Which daily counter in aiUsage/{day}. */
export type Counter = "photoReads" | "billReads";

export interface Quota {
  /** Adds one to the shop's [counter] today if under the limit; returns the new count, or null if the limit is reached. */
  take(shopId: string, counter: Counter, limit: number): Promise<number | null>;
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
  const today = await deps.quota.take(auth.uid, "photoReads", DAILY_LIMIT);
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

export type BillHandlerResult =
  | { ok: true; result: BillResult; usage: { today: number; limit: number } }
  | { ok: false; error: ReadError };

/** readBill: same order as photos — auth, input, limit (counted before the call), model, checks. */
export async function handleReadBill(
  auth: { uid: string } | undefined,
  data: unknown,
  deps: { model: BillModelReader; quota: Quota },
): Promise<BillHandlerResult> {
  if (!auth?.uid) return { ok: false, error: "unauthenticated" };
  const input = checkBillInput(data);
  if ("error" in input) return { ok: false, error: input.error };
  const today = await deps.quota.take(auth.uid, "billReads", BILL_DAILY_LIMIT);
  if (today === null) return { ok: false, error: "limit-reached" };
  let raw: BillAnswer | "unreadable";
  try {
    raw = await deps.model.read(input.pages, input.catalog);
  } catch {
    return { ok: false, error: "unavailable" };
  }
  if (raw === "unreadable") return { ok: false, error: "unreadable" };
  const result = checkBillAnswer(raw, new Set(input.catalog.map((c) => c.id)));
  if (result === "unreadable") return { ok: false, error: "unreadable" };
  return { ok: true, result, usage: { today, limit: BILL_DAILY_LIMIT } };
}
