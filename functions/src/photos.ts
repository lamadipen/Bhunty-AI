// Pure logic for readProductPhotos: input checks, the model's answer schema,
// and the server-side checks on that answer (docs/product-photos.md PR6).
// No Firebase or network here, so it is unit-tested directly.
import * as z from "zod/v4";

export type PhotoRole = "front" | "label" | "barcode";
export interface PhotoInput {
  role: PhotoRole;
  jpegBase64: string;
}

export const MAX_IMAGES = 3;
/** ≈ 1024 px JPEG at quality 80 is well under this. */
export const MAX_IMAGE_BASE64_CHARS = 400 * 1024;
export const DAILY_LIMIT = 100;

/** Nepali reason-free error codes the app maps to messages. */
export type ReadError = "unauthenticated" | "invalid-argument" | "limit-reached" | "unreadable" | "unavailable";

/** Checks the request body; returns the images or an error. */
export function checkInput(data: unknown): { images: PhotoInput[]; barcodeOnPhone?: string } | { error: ReadError } {
  if (typeof data !== "object" || data === null) return { error: "invalid-argument" };
  const { images, barcodeOnPhone } = data as { images?: unknown; barcodeOnPhone?: unknown };
  if (!Array.isArray(images) || images.length < 1 || images.length > MAX_IMAGES) return { error: "invalid-argument" };
  const out: PhotoInput[] = [];
  const seen = new Set<string>();
  for (const img of images) {
    if (typeof img !== "object" || img === null) return { error: "invalid-argument" };
    const { role, jpegBase64 } = img as { role?: unknown; jpegBase64?: unknown };
    if (role !== "front" && role !== "label" && role !== "barcode") return { error: "invalid-argument" };
    if (seen.has(role)) return { error: "invalid-argument" };
    seen.add(role);
    if (typeof jpegBase64 !== "string" || jpegBase64.length === 0 || jpegBase64.length > MAX_IMAGE_BASE64_CHARS) {
      return { error: "invalid-argument" };
    }
    if (!/^[A-Za-z0-9+/]+=*$/.test(jpegBase64)) return { error: "invalid-argument" };
    out.push({ role, jpegBase64 });
  }
  const code = typeof barcodeOnPhone === "string" && barcodeOnPhone.length <= 30 ? barcodeOnPhone : undefined;
  return { images: out, barcodeOnPhone: code };
}

/** What the model must return (structured outputs). Everything optional: leave out rather than guess. */
export const ModelAnswerSchema = z.object({
  readable: z.boolean().describe("false if the photos do not show a retail product or nothing can be read"),
  nameNe: z.string().nullable().describe("Product name in Nepali (Devanagari), without size. null if unknown."),
  nameEn: z.string().nullable().describe("Product name in English as printed, without size. null if unknown."),
  brand: z.string().nullable(),
  sizeText: z.string().nullable().describe('Net size or count as printed, e.g. "70 g", "1 L", "12 pcs". null if not printed.'),
  unit: z.enum(["piece", "packet", "kg", "litre"]).nullable().describe("How a small shop sells one of these"),
  mrpRupees: z.number().nullable().describe("Maximum retail price printed on the pack, in rupees. null if not printed."),
  barcodeDigits: z.string().nullable().describe("Digits printed under a barcode, if clearly visible. null otherwise."),
  confidence: z.object({
    nameNe: z.enum(["high", "low"]),
    nameEn: z.enum(["high", "low"]),
    sizeText: z.enum(["high", "low"]),
    unit: z.enum(["high", "low"]),
    mrp: z.enum(["high", "low"]),
    barcode: z.enum(["high", "low"]),
  }),
  notes: z.string().nullable().describe("Short note in Nepali if something was unclear, else null"),
});
export type ModelAnswer = z.infer<typeof ModelAnswerSchema>;

export interface PhotoReadResult {
  nameNe?: string;
  nameEn?: string;
  brand?: string;
  sizeText?: string;
  unit?: "piece" | "packet" | "kg" | "litre";
  mrpPaisa?: number;
  barcode?: string;
  confidence: Record<string, "high" | "low">;
  notes?: string;
}

const MAX_TEXT = 60;

function cleanText(v: string | null | undefined, max = MAX_TEXT): string | undefined {
  if (v == null) return undefined;
  const t = v.replace(/\s+/g, " ").trim();
  if (t.length === 0 || t.length > max || /[\r\n]/.test(v.trim())) return undefined;
  return t;
}

/** GTIN check digit (EAN-8/12/13/14). Same rule as the app's checkProductCode. */
export function gtinValid(digits: string): boolean {
  if (!/^\d+$/.test(digits) || ![8, 12, 13, 14].includes(digits.length)) return false;
  const body = digits.slice(0, -1);
  let sum = 0;
  for (let i = 0; i < body.length; i++) {
    const d = body.charCodeAt(body.length - 1 - i) - 48;
    sum += d * (i % 2 === 0 ? 3 : 1);
  }
  return (10 - (sum % 10)) % 10 === digits.charCodeAt(digits.length - 1) - 48;
}

/** UPC-A → EAN-13 (leading 0), GTIN-14 with indicator 0 → EAN-13; as the app stores them. */
export function normaliseGtin(digits: string): string {
  if (digits.length === 12) return `0${digits}`;
  if (digits.length === 14 && digits.startsWith("0")) return digits.slice(1);
  return digits;
}

/** Server-side checks on the model's answer (PR6). Anything that fails is dropped. */
export function checkAnswer(raw: ModelAnswer): PhotoReadResult | "unreadable" {
  if (!raw.readable) return "unreadable";
  const out: PhotoReadResult = { confidence: {} };
  const keep = <K extends keyof PhotoReadResult>(key: K, value: PhotoReadResult[K] | undefined, conf?: "high" | "low") => {
    if (value === undefined) return;
    out[key] = value;
    if (conf) out.confidence[key as string] = conf;
  };
  keep("nameNe", cleanText(raw.nameNe), raw.confidence.nameNe);
  keep("nameEn", cleanText(raw.nameEn), raw.confidence.nameEn);
  keep("brand", cleanText(raw.brand));
  keep("sizeText", cleanText(raw.sizeText, 20), raw.confidence.sizeText);
  if (raw.unit && ["piece", "packet", "kg", "litre"].includes(raw.unit)) keep("unit", raw.unit, raw.confidence.unit);
  if (typeof raw.mrpRupees === "number" && Number.isFinite(raw.mrpRupees)) {
    const paisa = Math.round(raw.mrpRupees * 100);
    if (paisa >= 100 && paisa <= 10_000_000) keep("mrpPaisa", paisa, raw.confidence.mrp);
  }
  if (raw.barcodeDigits) {
    const digits = raw.barcodeDigits.replace(/[\s-]/g, "");
    if (gtinValid(digits)) keep("barcode", normaliseGtin(digits), raw.confidence.barcode);
  }
  keep("notes", cleanText(raw.notes, 120));
  if (!out.nameNe && !out.nameEn && !out.sizeText && !out.barcode && !out.mrpPaisa) return "unreadable";
  return out;
}

/** "2026-10-24" in Nepal time (UTC+5:45), the key for the daily limit. */
export function nepalDayKey(now: Date): string {
  const t = new Date(now.getTime() + (5 * 60 + 45) * 60 * 1000);
  return t.toISOString().slice(0, 10);
}
