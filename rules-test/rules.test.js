// Firestore rules tests. Run: npm test (starts the emulator, no real project needed).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, increment, serverTimestamp, setDoc, updateDoc, deleteDoc, writeBatch } from 'firebase/firestore';

let env;
const OWNER = 'owner-1';
const OTHER = 'someone-else';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-bhunte',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, `shops/${OWNER}`), { name: 'मेरो पसल', ownerUid: OWNER, currency: 'NPR' });
    await setDoc(doc(db, `shops/${OWNER}/products/egg`), { name_ne: 'अण्डा', pricePaisa: 2000, costPaisa: 1600, stockMilli: 90000 });
    await setDoc(doc(db, `shops/${OWNER}/customers/ram`), { name: 'राम दाइ', balancePaisa: 320000, lastNote: '' });
    await setDoc(doc(db, `shops/${OWNER}/sales/s1`), { totalPaisa: 2000, createdBy: OWNER });
    await setDoc(doc(db, `shops/${OWNER}/customers/ram/ledger/l1`), { type: 'credit', amountPaisa: 100 });
  });
});

const ownerDb = () => env.authenticatedContext(OWNER).firestore();
const otherDb = () => env.authenticatedContext(OTHER).firestore();
const anonDb = () => env.unauthenticatedContext().firestore();

describe('shop access', () => {
  it('owner can read their shop; others and signed-out users cannot', async () => {
    await assertSucceeds(getDoc(doc(ownerDb(), `shops/${OWNER}/products/egg`)));
    await assertFails(getDoc(doc(otherDb(), `shops/${OWNER}/products/egg`)));
    await assertFails(getDoc(doc(anonDb(), `shops/${OWNER}`)));
  });

  it('a new user can create only their own shop, owned by themselves', async () => {
    const db = otherDb();
    await assertSucceeds(setDoc(doc(db, `shops/${OTHER}`), { name: 'x', ownerUid: OTHER }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}-2`), { name: 'x', ownerUid: OTHER }));
    await assertFails(updateDoc(doc(ownerDb(), `shops/${OWNER}`), { ownerUid: OTHER }));
  });
});

describe('the app\'s sale batch', () => {
  it('cash + udharo batch with increments is allowed', async () => {
    const db = ownerDb();
    const batch = writeBatch(db);
    batch.set(doc(db, `shops/${OWNER}/sales/s2`), {
      totalPaisa: 10000, createdBy: OWNER, day: '2026-10-18', syncedAt: serverTimestamp(),
      payments: [{ method: 'udharo', amountPaisa: 10000 }],
    });
    batch.update(doc(db, `shops/${OWNER}/products/egg`), { stockMilli: increment(-5000) });
    batch.set(doc(db, `shops/${OWNER}/customers/ram/ledger/l2`), { type: 'credit', amountPaisa: 10000 });
    batch.set(doc(db, `shops/${OWNER}/customers/ram`), { balancePaisa: increment(10000), lastNote: 'आज' }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  it('money must be int paisa', async () => {
    const db = ownerDb();
    await assertFails(setDoc(doc(db, `shops/${OWNER}/sales/s3`), { totalPaisa: 99.5, createdBy: OWNER }));
    await assertFails(updateDoc(doc(db, `shops/${OWNER}/products/egg`), { pricePaisa: 20.5 }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}/customers/ram/ledger/l3`), { type: 'credit', amountPaisa: 0 }));
  });

  it('new products need a name and int pack size', async () => {
    const db = ownerDb();
    const base = { name_ne: 'नुन', pricePaisa: 2500, costPaisa: 2000, stockMilli: 0 };
    await assertSucceeds(setDoc(doc(db, `shops/${OWNER}/products/salt`), { ...base, packName: null, packSizeMilli: null }));
    await assertSucceeds(setDoc(doc(db, `shops/${OWNER}/products/salt2`), { ...base, packName: 'बोरा', packSizeMilli: 50000 }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}/products/salt3`), { ...base, packSizeMilli: 2.5 }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}/products/salt4`), { ...base, name_ne: '' }));
  });

  it('a sale must name the signed-in user as createdBy', async () => {
    await assertFails(setDoc(doc(ownerDb(), `shops/${OWNER}/sales/s4`), { totalPaisa: 100, createdBy: OTHER }));
  });
});

describe('stock batches and price history', () => {
  const now = new Date();
  it('a delivery with a batch and a price change is allowed', async () => {
    const db = ownerDb();
    const b = writeBatch(db);
    b.set(doc(db, `shops/${OWNER}/deliveries/d1`), { source: 'manual', totalCostPaisa: 13000, batchCount: 1, createdAt: now, createdBy: OWNER, supplierName: null, supplierPhone: null, billNo: null });
    b.set(doc(db, `shops/${OWNER}/batches/b1`), { deliveryId: 'd1', productId: 'egg', qtyMilli: 10000, unitCostPaisa: 1300, totalCostPaisa: 13000, salePricePaisa: 1800, createdAt: now, createdBy: OWNER });
    b.set(doc(db, `shops/${OWNER}/priceChanges/p1`), { productId: 'egg', oldPricePaisa: 1500, newPricePaisa: 1800, reason: 'stock', batchId: 'b1', createdAt: now, createdBy: OWNER });
    b.update(doc(db, `shops/${OWNER}/products/egg`), { stockMilli: increment(10000), pricePaisa: 1800 });
    await assertSucceeds(b.commit());
  });

  it('bad batches and price changes are refused', async () => {
    const db = ownerDb();
    const base = { deliveryId: 'd1', productId: 'egg', qtyMilli: 10000, unitCostPaisa: 1300, totalCostPaisa: 13000, salePricePaisa: 1800, createdAt: now, createdBy: OWNER };
    await assertFails(setDoc(doc(db, `shops/${OWNER}/batches/b2`), { ...base, qtyMilli: 0 }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}/batches/b3`), { ...base, salePricePaisa: 0 }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}/batches/b4`), { ...base, unitCostPaisa: 13.5 }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}/priceChanges/p2`), { productId: 'egg', newPricePaisa: 1800, reason: 'guess', createdAt: now, createdBy: OWNER }));
    await assertFails(setDoc(doc(db, `shops/${OWNER}/stockEntries/s1`), { totalPaisa: 1 }));
  });

  it('history cannot be edited or deleted', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `shops/${OWNER}/batches/old`), { qtyMilli: 1000, salePricePaisa: 1500 });
      await setDoc(doc(ctx.firestore(), `shops/${OWNER}/priceChanges/old`), { newPricePaisa: 1500, reason: 'initial' });
    });
    const db = ownerDb();
    await assertFails(updateDoc(doc(db, `shops/${OWNER}/batches/old`), { qtyMilli: 2000 }));
    await assertFails(deleteDoc(doc(db, `shops/${OWNER}/batches/old`)));
    await assertFails(updateDoc(doc(db, `shops/${OWNER}/priceChanges/old`), { newPricePaisa: 1 }));
  });
});

describe('append-only records', () => {
  it('sales and ledger entries cannot be edited or deleted', async () => {
    const db = ownerDb();
    await assertFails(updateDoc(doc(db, `shops/${OWNER}/sales/s1`), { totalPaisa: 1 }));
    await assertFails(deleteDoc(doc(db, `shops/${OWNER}/sales/s1`)));
    await assertFails(updateDoc(doc(db, `shops/${OWNER}/customers/ram/ledger/l1`), { amountPaisa: 1 }));
    await assertFails(deleteDoc(doc(db, `shops/${OWNER}/customers/ram`)));
  });

  it('daily summaries are read-only for the app', async () => {
    await assertFails(setDoc(doc(ownerDb(), `shops/${OWNER}/dailySummaries/2026-10-18`), { totalPaisa: 1 }));
  });
});

describe('product photos (docs/product-photos.md)', () => {
  const jpeg = 'A'.repeat(40000);

  it('the app saves a thumbnail with its product flag in one batch, and can remove it', async () => {
    const db = ownerDb();
    const b = writeBatch(db);
    b.set(doc(db, `shops/${OWNER}/productImages/egg`), { jpegBase64: jpeg, width: 256, height: 192, updatedAt: serverTimestamp(), updatedBy: OWNER });
    b.update(doc(db, `shops/${OWNER}/products/egg`), { hasImage: true, imageUpdatedAt: serverTimestamp() });
    await assertSucceeds(b.commit());
    await assertSucceeds(getDoc(doc(db, `shops/${OWNER}/productImages/egg`)));
    const r = writeBatch(db);
    r.delete(doc(db, `shops/${OWNER}/productImages/egg`));
    r.update(doc(db, `shops/${OWNER}/products/egg`), { hasImage: false });
    await assertSucceeds(r.commit());
  });

  it('thumbnails over 80,000 characters, of other shops, or without updatedBy are refused', async () => {
    const ok = { jpegBase64: jpeg, width: 256, height: 256, updatedBy: OWNER };
    await assertFails(setDoc(doc(ownerDb(), `shops/${OWNER}/productImages/egg`), { ...ok, jpegBase64: 'A'.repeat(80001) }));
    await assertFails(setDoc(doc(ownerDb(), `shops/${OWNER}/productImages/egg`), { ...ok, jpegBase64: '' }));
    await assertFails(setDoc(doc(ownerDb(), `shops/${OWNER}/productImages/egg`), { ...ok, updatedBy: OTHER }));
    await assertFails(setDoc(doc(otherDb(), `shops/${OWNER}/productImages/egg`), { ...ok, updatedBy: OTHER }));
    await assertFails(getDoc(doc(otherDb(), `shops/${OWNER}/productImages/egg`)));
  });

  it('AI usage is readable by the owner but only the Cloud Function writes it', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), `shops/${OWNER}/aiUsage/2026-10-24`), { photoReads: 3 });
    });
    await assertSucceeds(getDoc(doc(ownerDb(), `shops/${OWNER}/aiUsage/2026-10-24`)));
    await assertFails(getDoc(doc(otherDb(), `shops/${OWNER}/aiUsage/2026-10-24`)));
    await assertFails(setDoc(doc(ownerDb(), `shops/${OWNER}/aiUsage/2026-10-24`), { photoReads: 0 }));
    await assertFails(deleteDoc(doc(ownerDb(), `shops/${OWNER}/aiUsage/2026-10-24`)));
  });
});
