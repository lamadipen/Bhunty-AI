// Claude Haiku reads the product photos and answers in a fixed shape
// (structured outputs). It only suggests; the app shows the result for the
// shopkeeper to check, and nothing is saved by the model (principle 2).
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { BillAnswer, BillAnswerSchema, CatalogItem } from "./bill";
import { BillModelReader, ModelReader } from "./handler";
import { ModelAnswer, ModelAnswerSchema, PhotoInput } from "./photos";

export const MODEL = "claude-haiku-5-5";

const SYSTEM = `You read photos of retail products for a small shop in Nepal and fill a product form.
Rules:
- Read only what is printed on the product. Leave a field null rather than guess.
- nameNe: the product name in Nepali (Devanagari); transliterate a printed English brand if there is no Nepali text (e.g. "Wai Wai" -> "वाइवाइ"). Do not include the size.
- nameEn: the name in English/Latin as printed, without the size.
- sizeText: net weight, volume or count exactly as printed (e.g. "70 g", "1 L", "12 pcs").
- unit: how a shop sells one item: packet for packaged snacks/noodles/biscuits, piece for single items (soap, bottle, can), kg or litre only for loose goods sold by weight/volume.
- mrpRupees: only the printed MRP / maximum retail price, in rupees. Never estimate a price.
- barcodeDigits: only if the digits under a barcode are clearly readable.
- confidence: "low" for anything blurry, partly hidden or inferred.
- readable: false if this is not a retail product or nothing can be read.`;

const ROLE_LABEL: Record<PhotoInput["role"], string> = {
  front: "Photo 1 — front of the product:",
  barcode: "Photo 2 — barcode:",
  label: "Photo 3 — label with name, size and MRP:",
};

export class ClaudeReader implements ModelReader {
  constructor(private readonly client: Anthropic) {}

  async read(images: PhotoInput[], barcodeOnPhone?: string): Promise<ModelAnswer | "unreadable"> {
    const content: Anthropic.ContentBlockParam[] = [];
    for (const img of images) {
      content.push({ type: "text", text: ROLE_LABEL[img.role] });
      content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data: img.jpegBase64 } });
    }
    content.push({
      type: "text",
      text: barcodeOnPhone
        ? `The phone already read the barcode as ${barcodeOnPhone}. Fill the form.`
        : "Fill the form.",
    });

    const response = await this.client.messages.parse({
      model: MODEL,
      max_tokens: 4096,
      system: SYSTEM,
      // Reading printed text, not reasoning: low effort keeps it fast and cheap.
      output_config: { effort: "low", format: zodOutputFormat(ModelAnswerSchema) },
      messages: [{ role: "user", content }],
    });

    // Haiku has no server-side refusal fallback: a declined request is just unreadable here.
    if (response.stop_reason === "refusal") return "unreadable";
    return response.parsed_output ?? "unreadable";
  }
}

const BILL_SYSTEM = `You read photos of a wholesaler's bill (invoice, estimate or handwritten slip) for a small shop in Nepal.
Rules:
- Read only what is written. Leave a field null rather than guess. Never invent lines.
- One entry in "lines" per item line, in the order printed; skip headings, subtotals, VAT and discount lines.
- qty: the quantity as written. If the line is in packs (carton, crate, box, bora, dozen, kartun...), qtyIn "pack" and packWord as written. Loose goods in kg or litre: qtyIn "kg"/"litre". Otherwise qtyIn "unit".
- freeQty: free items such as "12+1" (qty 12, freeQty 1) or "1 free".
- rateRupees and amountRupees exactly as written, in rupees. Do not compute missing numbers.
- productId: pick from the shop's catalog only when the line is clearly that product (same item and size); match "high" when sure, "low" when likely. Otherwise null and match "none", and give nameNe: a short Nepali name.
- Confidence "low" for any number that is blurry, overwritten or handwritten unclearly; add a short Nepali note.
- Header: supplier name and phone, bill number, date exactly as printed (often Bikram Sambat like 2081/07/08), grand total, VAT and bill discount if printed.
- readable: false if this is not a bill.`;

export class ClaudeBillReader implements BillModelReader {
  constructor(private readonly client: Anthropic) {}

  async read(pages: string[], catalog: CatalogItem[]): Promise<BillAnswer | "unreadable"> {
    const list = catalog
      .map((c) => [c.id, c.ne, c.en, c.unit, c.packName && c.packSize ? `${c.packName}=${c.packSize}` : ""].join(" | "))
      .join("\n");
    const content: Anthropic.ContentBlockParam[] = [
      { type: "text", text: `The shop's catalog (id | Nepali name | English name | unit | pack):\n${list || "(empty)"}` },
    ];
    pages.forEach((data, i) => {
      content.push({ type: "text", text: `Bill page ${i + 1} of ${pages.length}:` });
      content.push({ type: "image", source: { type: "base64", media_type: "image/jpeg", data } });
    });
    content.push({ type: "text", text: "Read the bill." });

    const response = await this.client.messages.parse({
      model: MODEL,
      max_tokens: 16000,
      system: BILL_SYSTEM,
      output_config: { effort: "low", format: zodOutputFormat(BillAnswerSchema) },
      messages: [{ role: "user", content }],
    });
    if (response.stop_reason === "refusal") return "unreadable";
    return response.parsed_output ?? "unreadable";
  }
}
