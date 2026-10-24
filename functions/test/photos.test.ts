// Scenario tests for readProductPhotos (docs/product-photos.md §5) with a fake
// model and quota. Run: npm test
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { handleReadPhotos, ModelReader, Quota } from "../src/handler";
import { checkAnswer, checkInput, gtinValid, MAX_IMAGE_BASE64_CHARS, ModelAnswer, nepalDayKey } from "../src/photos";

const JPEG = "/9j/4AAQSkZJRgABAQ==";

function answer(over: Partial<ModelAnswer> = {}): ModelAnswer {
  return {
    readable: true,
    nameNe: "वाइवाइ चिकेन",
    nameEn: "Wai Wai Chicken",
    brand: "Wai Wai",
    sizeText: "70 g",
    unit: "packet",
    mrpRupees: 25,
    barcodeDigits: "8901234567890",
    confidence: { nameNe: "high", nameEn: "high", sizeText: "high", unit: "high", mrp: "high", barcode: "high" },
    notes: null,
    ...over,
  };
}

const fakeModel = (result: ModelAnswer | "unreadable" | Error): ModelReader & { calls: number } => {
  const m = {
    calls: 0,
    async read() {
      m.calls++;
      if (result instanceof Error) throw result;
      return result;
    },
  };
  return m;
};

const fakeQuota = (used = 0): Quota & { used: number } => {
  const q = {
    used,
    async take(_shop: string, limit: number) {
      if (q.used >= limit) return null;
      return ++q.used;
    },
  };
  return q;
};

const auth = { uid: "shop1" };
const body = { images: [{ role: "front", jpegBase64: JPEG }] };

describe("readProductPhotos", () => {
  it("F-1: reads name, size, unit, MRP and barcode from good photos", async () => {
    const out = await handleReadPhotos(auth, body, { model: fakeModel(answer()), quota: fakeQuota() });
    assert.ok(out.ok);
    assert.equal(out.result.nameNe, "वाइवाइ चिकेन");
    assert.equal(out.result.sizeText, "70 g");
    assert.equal(out.result.unit, "packet");
    assert.equal(out.result.mrpPaisa, 2500);
    assert.equal(out.result.barcode, "8901234567890");
    assert.equal(out.result.confidence.nameNe, "high");
    assert.deepEqual(out.usage, { today: 1, limit: 100 });
  });

  it("F-7: a refusal or an answer with nothing usable is 'unreadable'", async () => {
    let out = await handleReadPhotos(auth, body, { model: fakeModel("unreadable"), quota: fakeQuota() });
    assert.deepEqual(out, { ok: false, error: "unreadable" });
    out = await handleReadPhotos(auth, body, { model: fakeModel(answer({ readable: false })), quota: fakeQuota() });
    assert.deepEqual(out, { ok: false, error: "unreadable" });
    const empty = answer({ nameNe: null, nameEn: null, sizeText: null, mrpRupees: null, barcodeDigits: null });
    out = await handleReadPhotos(auth, body, { model: fakeModel(empty), quota: fakeQuota() });
    assert.deepEqual(out, { ok: false, error: "unreadable" });
  });

  it("F-8: the 101st read of the day is refused without calling the model", async () => {
    const model = fakeModel(answer());
    const out = await handleReadPhotos(auth, body, { model, quota: fakeQuota(100) });
    assert.deepEqual(out, { ok: false, error: "limit-reached" });
    assert.equal(model.calls, 0);
  });

  it("F-9: fields that fail the checks are dropped, the rest kept", () => {
    const r = checkAnswer(
      answer({
        nameEn: "x".repeat(61),
        mrpRupees: 0.5,
        barcodeDigits: "8901234567891", // wrong check digit
      }),
    );
    assert.notEqual(r, "unreadable");
    if (r === "unreadable") return;
    assert.equal(r.nameEn, undefined);
    assert.equal(r.mrpPaisa, undefined);
    assert.equal(r.barcode, undefined);
    assert.equal(r.confidence.barcode, undefined);
    assert.equal(r.nameNe, "वाइवाइ चिकेन");
  });

  it("F-9: MRP bounds, UPC-A normalised, whitespace collapsed", () => {
    const r = checkAnswer(answer({ mrpRupees: 100000.01, barcodeDigits: "0 36000 29145 2", nameNe: "  साबुन \t बट्टा " }));
    if (r === "unreadable") return assert.fail();
    assert.equal(r.mrpPaisa, undefined);
    assert.equal(r.barcode, "0036000291452");
    assert.equal(r.nameNe, "साबुन बट्टा");
    const top = checkAnswer(answer({ mrpRupees: 100000 }));
    if (top === "unreadable") return assert.fail();
    assert.equal(top.mrpPaisa, 10_000_000);
  });

  it("AI down is 'unavailable' and the read still counts (as in F-16)", async () => {
    const quota = fakeQuota();
    const out = await handleReadPhotos(auth, body, { model: fakeModel(new Error("529")), quota });
    assert.deepEqual(out, { ok: false, error: "unavailable" });
    assert.equal(quota.used, 1);
  });

  it("refuses callers who are not signed in", async () => {
    const quota = fakeQuota();
    const out = await handleReadPhotos(undefined, body, { model: fakeModel(answer()), quota });
    assert.deepEqual(out, { ok: false, error: "unauthenticated" });
    assert.equal(quota.used, 0);
  });
});

describe("checkInput", () => {
  const img = (role: string, data = JPEG) => ({ role, jpegBase64: data });
  const bad = (data: unknown) => assert.deepEqual(checkInput(data), { error: "invalid-argument" });

  it("accepts 1–3 images with distinct roles", () => {
    const r = checkInput({ images: [img("front"), img("barcode"), img("label")], barcodeOnPhone: "8901234567890" });
    assert.ok(!("error" in r));
    assert.equal(r.images.length, 3);
    assert.equal(r.barcodeOnPhone, "8901234567890");
  });

  it("refuses no images, too many, duplicate or unknown roles, oversize or non-base64 data", () => {
    bad(null);
    bad({ images: [] });
    bad({ images: [img("front"), img("barcode"), img("label"), img("front")] });
    bad({ images: [img("front"), img("front")] });
    bad({ images: [img("back")] });
    bad({ images: [img("front", "A".repeat(MAX_IMAGE_BASE64_CHARS + 1))] });
    bad({ images: [img("front", "not base64!")] });
  });
});

describe("helpers", () => {
  it("GTIN check digit", () => {
    assert.ok(gtinValid("8901234567890"));
    assert.ok(gtinValid("036000291452"));
    assert.ok(!gtinValid("8901234567891"));
    assert.ok(!gtinValid("12345"));
  });

  it("Nepal day rolls over at 18:15 UTC", () => {
    assert.equal(nepalDayKey(new Date("2026-10-24T18:14:00Z")), "2026-10-24");
    assert.equal(nepalDayKey(new Date("2026-10-24T18:15:00Z")), "2026-10-25");
  });
});
