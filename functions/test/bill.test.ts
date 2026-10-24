// readBill (docs/stock-from-bill.md §4) with a fake model and quota. Run: npm test
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { BillAnswer, checkBillAnswer, checkBillInput, MAX_PAGE_BASE64_CHARS, nepalPhone } from "../src/bill";
import { BillModelReader, Counter, handleReadBill, Quota } from "../src/handler";

const PAGE = "/9j/4AAQSkZJRgABAQ==";
const catalog = [
  { id: "waiwai", ne: "वाइवाइ", en: "Wai Wai", unit: "packet", packName: "कार्टुन", packSize: 30 },
  { id: "sugar", ne: "चिनी", en: "Sugar", unit: "kg" },
];
const body = { pages: [PAGE], catalog };
const auth = { uid: "shop1" };

type Line = BillAnswer["lines"][number];
const line = (over: Partial<Line> = {}): Line => ({
  text: "WAI WAI CHK 2 CTN",
  qty: 2,
  qtyIn: "pack",
  packWord: "CTN",
  freeQty: null,
  rateRupees: 390,
  amountRupees: 780,
  productId: "waiwai",
  match: "high",
  nameNe: null,
  qtyConfidence: "high",
  rateConfidence: "high",
  amountConfidence: "high",
  note: null,
  ...over,
});
const answer = (over: Partial<BillAnswer> = {}): BillAnswer => ({
  readable: true,
  supplierName: "राम ट्रेडर्स",
  supplierPhone: "+977 9812345678",
  billNo: "1452",
  billDate: "2081/07/08",
  totalRupees: 3405,
  vatRupees: null,
  discountRupees: null,
  lines: [line(), line({ text: "चिनी 25 kg", qty: 25, qtyIn: "kg", packWord: null, rateRupees: 105, amountRupees: 2625, productId: "sugar" })],
  ...over,
});

const fakeModel = (result: BillAnswer | "unreadable" | Error): BillModelReader & { calls: number } => {
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
const fakeQuota = (used = 0): Quota & { counters: Counter[] } => {
  const q = {
    counters: [] as Counter[],
    async take(_shop: string, counter: Counter, limit: number) {
      q.counters.push(counter);
      return used >= limit ? null : ++used;
    },
  };
  return q;
};

describe("readBill", () => {
  it("BL-1: lines and header in paisa/milli-units, phone cleaned, counted as a bill read", async () => {
    const quota = fakeQuota();
    const out = await handleReadBill(auth, body, { model: fakeModel(answer()), quota });
    assert.ok(out.ok);
    assert.deepEqual(quota.counters, ["billReads"]);
    assert.deepEqual(out.usage, { today: 1, limit: 30 });
    const r = out.result;
    assert.equal(r.supplierPhone, "9812345678");
    assert.equal(r.billDateText, "2081/07/08");
    assert.equal(r.totalPaisa, 340500);
    const [ww, sugar] = r.lines;
    assert.equal(ww.qtyMilli, 2000);
    assert.equal(ww.qtyIn, "pack");
    assert.equal(ww.ratePaisa, 39000);
    assert.equal(ww.amountPaisa, 78000);
    assert.equal(ww.productId, "waiwai");
    assert.equal(sugar.qtyIn, "kg");
  });

  it("BR8/BL-18: a product id not in the catalog is dropped and the line becomes new", () => {
    const r = checkBillAnswer(answer({ lines: [line({ productId: "xyz", nameNe: "रियल जुस" })] }), new Set(["waiwai"]));
    assert.notEqual(r, "unreadable");
    if (r === "unreadable") return;
    assert.equal(r.lines[0].productId, undefined);
    assert.equal(r.lines[0].match, "none");
    assert.equal(r.lines[0].nameNe, "रियल जुस");
  });

  it("numbers out of range or invalid phones are dropped, the line kept", () => {
    const r = checkBillAnswer(
      answer({ supplierPhone: "12345", lines: [line({ qty: 0, rateRupees: 2_000_000, amountRupees: -5, freeQty: 1 })] }),
      new Set(["waiwai"]),
    );
    if (r === "unreadable") return assert.fail();
    assert.equal(r.supplierPhone, undefined);
    const l = r.lines[0];
    assert.equal(l.qtyMilli, undefined);
    assert.equal(l.ratePaisa, undefined);
    assert.equal(l.amountPaisa, undefined);
    assert.equal(l.freeQtyMilli, 1000);
  });

  it("BL-21: more than 80 lines are cut to 80 and flagged", () => {
    const r = checkBillAnswer(answer({ lines: Array.from({ length: 85 }, (_, i) => line({ text: `item ${i}` })) }), new Set());
    if (r === "unreadable") return assert.fail();
    assert.equal(r.lines.length, 80);
    assert.equal(r.tooManyLines, true);
  });

  it("BL-11: not a bill, or no lines, is unreadable", async () => {
    let out = await handleReadBill(auth, body, { model: fakeModel(answer({ readable: false })), quota: fakeQuota() });
    assert.deepEqual(out, { ok: false, error: "unreadable" });
    out = await handleReadBill(auth, body, { model: fakeModel(answer({ lines: [] })), quota: fakeQuota() });
    assert.deepEqual(out, { ok: false, error: "unreadable" });
  });

  it("BL-13: the 31st bill read of the day is refused without calling the model", async () => {
    const model = fakeModel(answer());
    const out = await handleReadBill(auth, body, { model, quota: fakeQuota(30) });
    assert.deepEqual(out, { ok: false, error: "limit-reached" });
    assert.equal(model.calls, 0);
  });

  it("AI down is unavailable; signed-out callers refused", async () => {
    assert.deepEqual(await handleReadBill(auth, body, { model: fakeModel(new Error("529")), quota: fakeQuota() }), {
      ok: false,
      error: "unavailable",
    });
    assert.deepEqual(await handleReadBill(undefined, body, { model: fakeModel(answer()), quota: fakeQuota() }), {
      ok: false,
      error: "unauthenticated",
    });
  });

  it("input: 1–3 pages within size, a catalog of at most 1,000 items with ids", () => {
    const bad = (d: unknown) => assert.deepEqual(checkBillInput(d), { error: "invalid-argument" });
    bad({ pages: [], catalog });
    bad({ pages: [PAGE, PAGE, PAGE, PAGE], catalog });
    bad({ pages: ["A".repeat(MAX_PAGE_BASE64_CHARS + 1)], catalog });
    bad({ pages: [PAGE], catalog: [{ ne: "no id" }] });
    bad({ pages: [PAGE], catalog: Array.from({ length: 1001 }, (_, i) => ({ id: `p${i}` })) });
    const ok = checkBillInput({ pages: [PAGE, PAGE], catalog: [] });
    assert.ok(!("error" in ok));
  });

  it("Nepali phone numbers", () => {
    assert.equal(nepalPhone("98-1234-5678"), "9812345678");
    assert.equal(nepalPhone("01-4412345"), "014412345");
    assert.equal(nepalPhone("5551234"), undefined);
  });
});
