// Claude Haiku reads the product photos and answers in a fixed shape
// (structured outputs). It only suggests; the app shows the result for the
// shopkeeper to check, and nothing is saved by the model (principle 2).
import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { ModelReader } from "./handler";
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
