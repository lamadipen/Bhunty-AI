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

  it('a sale must name the signed-in user as createdBy', async () => {
    await assertFails(setDoc(doc(ownerDb(), `shops/${OWNER}/sales/s4`), { totalPaisa: 100, createdBy: OTHER }));
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
