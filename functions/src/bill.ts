// Pure logic for readBill (docs/stock-from-bill.md §4): input checks, the
// model's answer schema and the server-side checks on it. No Firebase or
// network here, so it is unit-tested directly.
import * as z from "zod/v4";
import { ReadError } from "./photos";

export const BILL_DAILY_LIMIT = 30;
export const MAX_PAGES = 3;
/** ≈ 1600 px JPEG at quality 85. */
export const MAX_PAGE_BASE64_CHARS = 700 * 1024;
export const MAX_CATALOG = 1000;
export const MAX_LINES = 80;

export interface CatalogItem {
  id: string;
  ne: string;
  en: string;
  unit: string;
  packName?: string;
  packSize?: number;
}

export interface BillInput {
  pages: string[];
  catalog: CatalogItem[];
}

const str = (v: unknown, max: number): string | undefined =>
  typeof v === "string" && v.trim().length > 0 && v.length <= max ? v.trim() : undefined;

export function checkBillInput(data: unknown): BillInput | { error: ReadError } {
  if (typeof data !== "object" || data === null) return { error: "invalid-argument" };
  const { pages, catalog } = data as { pages?: unknown; catalog?: unknown };
  if (!Array.isArray(pages) || pages.length < 1 || pages.length > MAX_PAGES) return { error: "invalid-argument" };
  for (const p of pages) {
    if (typeof p !== "string" || p.length === 0 || p.length > MAX_PAGE_BASE64_CHARS) return { error: "invalid-argument" };
    if (!/^[A-Za-z0-9+/]+=*$/.test(p)) return { error: "invalid-argument" };
  }
  if (!Array.isArray(catalog) || catalog.length > MAX_CATALOG) return { error: "invalid-argument" };
  const items: CatalogItem[] = [];
  for (const c of catalog) {
    if (typeof c !== "object" || c === null) return { error: "invalid-argument" };
    const m = c as Record<string, unknown>;
    const id = str(m.id, 64);
    if (!id) return { error: "invalid-argument" };
    items.push({
      id,
      ne: str(m.ne, 80) ?? "",
      en: str(m.en, 80) ?? "",
      unit: str(m.unit, 20) ?? "piece",
      packName: str(m.packName, 30),
      packSize: typeof m.packSize === "number" && m.packSize > 0 ? m.packSize : undefined,
    });
  }
  return { pages: pages as string[], catalog: items };
}

const conf = z.enum(["high", "low"]);

/** What the model must return (structured outputs). Null rather than guess. */
export const BillAnswerSchema = z.object({
  readable: z.boolean().describe("false if this is not a bill/invoice/estimate or nothing can be read"),
  supplierName: z.string().nullable(),
  supplierPhone: z.string().nullable(),
  billNo: z.string().nullable(),
  billDate: z.string().nullable().describe("Exactly as printed, e.g. 2081/07/08"),
  totalRupees: z.number().nullable().describe("Grand total printed on the bill"),
  vatRupees: z.number().nullable(),
  discountRupees: z.number().nullable().describe("Bill-level discount, positive number"),
  lines: z.array(
    z.object({
      text: z.string().describe("The item text as printed"),
      qty: z.number().nullable().describe("Quantity as printed (packs if sold in packs), excluding free items"),
      qtyIn: z.enum(["unit", "pack", "kg", "litre"]).nullable(),
      packWord: z.string().nullable().describe('The pack word as printed, e.g. "carton", "crate", "bora", "box"'),
      freeQty: z.number().nullable().describe('Free items, e.g. 1 for "12+1"'),
      rateRupees: z.number().nullable().describe("Price per unit/pack as printed"),
      amountRupees: z.number().nullable().describe("Line amount as printed"),
      productId: z.string().nullable().describe("id from the shop's catalog if this line is clearly that product, else null"),
      match: z.enum(["high", "low", "none"]),
      nameNe: z.string().nullable().describe("Short Nepali (Devanagari) name, only when no catalog product matches"),
      qtyConfidence: conf,
      rateConfidence: conf,
      amountConfidence: conf,
      note: z.string().nullable().describe("Short note in Nepali when something is unclear, e.g. '3 हो कि 8?'"),
    }),
  ),
});
export type BillAnswer = z.infer<typeof BillAnswerSchema>;

export interface BillLine {
  text: string;
  qtyMilli?: number;
  qtyIn?: "unit" | "pack" | "kg" | "litre";
  packWord?: string;
  freeQtyMilli?: number;
  ratePaisa?: number;
  amountPaisa?: number;
  productId?: string;
  match: "high" | "low" | "none";
  nameNe?: string;
  confidence: { qty: "high" | "low"; rate: "high" | "low"; amount: "high" | "low" };
  note?: string;
}

export interface BillResult {
  supplierName?: string;
  supplierPhone?: string;
  billNo?: string;
  billDateText?: string;
  totalPaisa?: number;
  vatPaisa?: number;
  discountPaisa?: number;
  lines: BillLine[];
  tooManyLines?: boolean;
}

const MAX_PAISA = 100_000_000; // रु 10,00,000

function paisa(rupees: number | null | undefined): number | undefined {
  if (typeof rupees !== "number" || !Number.isFinite(rupees)) return undefined;
  const p = Math.round(rupees * 100);
  return p >= 1 && p <= MAX_PAISA ? p : undefined;
}

function milli(qty: number | null | undefined): number | undefined {
  if (typeof qty !== "number" || !Number.isFinite(qty)) return undefined;
  const m = Math.round(qty * 1000);
  return m >= 1 && m <= 100_000_000 ? m : undefined;
}

function text(v: string | null | undefined, max: number): string | undefined {
  if (v == null) return undefined;
  const t = v.replace(/\s+/g, " ").trim();
  return t.length === 0 ? undefined : t.slice(0, max);
}

/** Nepali mobile (98/97/96…) or landline (0…); "+977" dropped. Anything else is dropped (BR12). */
export function nepalPhone(raw: string | null | undefined): string | undefined {
  if (!raw) return undefined;
  let d = raw.replace(/\D/g, "");
  if (d.startsWith("977")) d = d.slice(3);
  return /^9[678]\d{8}$/.test(d) || /^0\d{7,9}$/.test(d) ? d : undefined;
}

/** Server-side checks on the model's answer. Anything that fails is dropped. */
export function checkBillAnswer(raw: BillAnswer, catalogIds: Set<string>): BillResult | "unreadable" {
  if (!raw.readable) return "unreadable";
  const lines: BillLine[] = [];
  for (const l of raw.lines.slice(0, MAX_LINES)) {
    const t = text(l.text, 80);
    if (!t) continue;
    const productId = l.productId && catalogIds.has(l.productId) ? l.productId : undefined;
    lines.push({
      text: t,
      qtyMilli: milli(l.qty),
      qtyIn: l.qtyIn ?? undefined,
      packWord: text(l.packWord, 20),
      freeQtyMilli: milli(l.freeQty),
      ratePaisa: paisa(l.rateRupees),
      amountPaisa: paisa(l.amountRupees),
      productId,
      match: productId ? (l.match === "none" ? "low" : l.match) : "none",
      nameNe: productId ? undefined : text(l.nameNe, 60),
      confidence: { qty: l.qtyConfidence, rate: l.rateConfidence, amount: l.amountConfidence },
      note: text(l.note, 80),
    });
  }
  if (lines.length === 0) return "unreadable";
  const out: BillResult = { lines };
  const keep = <K extends keyof BillResult>(k: K, v: BillResult[K] | undefined) => {
    if (v !== undefined) out[k] = v;
  };
  keep("supplierName", text(raw.supplierName, 60));
  keep("supplierPhone", nepalPhone(raw.supplierPhone));
  keep("billNo", text(raw.billNo, 30));
  keep("billDateText", text(raw.billDate, 20));
  keep("totalPaisa", paisa(raw.totalRupees));
  keep("vatPaisa", paisa(raw.vatRupees));
  keep("discountPaisa", paisa(raw.discountRupees));
  if (raw.lines.length > MAX_LINES) out.tooManyLines = true;
  return out;
}
