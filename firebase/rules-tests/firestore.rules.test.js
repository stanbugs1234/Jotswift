// Tests for firebase/firestore.rules. Run with `npm test` in this folder
// (starts the Firestore emulator; needs Java).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, updateDoc } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-notely',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const sam = () => env.authenticatedContext('sam').firestore();
const alex = () => env.authenticatedContext('alex').firestore();
const guest = () => env.unauthenticatedContext().firestore();

/** Writes data directly, as a Cloud Function or the console would. */
const seed = (path, data) =>
  env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));

describe('users/{uid}', () => {
  test('people can create, read, update and delete their own doc', async () => {
    const ref = doc(sam(), 'users/sam');
    await assertSucceeds(setDoc(ref, { activeSkinId: 'kraft' }));
    await assertSucceeds(getDoc(ref));
    await assertSucceeds(updateDoc(ref, { activeSkinId: 'pastel' }));
    await assertSucceeds(deleteDoc(ref));
  });

  test("people cannot read or write someone else's doc", async () => {
    await seed('users/sam', { activeSkinId: 'kraft' });
    await assertFails(getDoc(doc(alex(), 'users/sam')));
    await assertFails(setDoc(doc(alex(), 'users/sam'), { activeSkinId: 'x' }));
    await assertFails(deleteDoc(doc(alex(), 'users/sam')));
  });

  test('signed-out visitors cannot read or write any user doc', async () => {
    await seed('users/sam', { activeSkinId: 'kraft' });
    await assertFails(getDoc(doc(guest(), 'users/sam')));
    await assertFails(setDoc(doc(guest(), 'users/sam'), { activeSkinId: 'x' }));
  });

  test('people cannot give themselves purchases', async () => {
    await assertFails(
      setDoc(doc(sam(), 'users/sam'), { entitlements: { pro: true } }),
    );
    await seed('users/sam', { activeSkinId: 'kraft', entitlements: { pro: false } });
    await assertFails(
      updateDoc(doc(sam(), 'users/sam'), { 'entitlements.pro': true }),
    );
  });

  test('people cannot mark themselves as testers', async () => {
    await assertFails(setDoc(doc(sam(), 'users/sam'), { tester: true }));
  });

  test('people can still change other fields when they have purchases', async () => {
    await seed('users/sam', { activeSkinId: 'kraft', entitlements: { pro: true } });
    await assertSucceeds(
      updateDoc(doc(sam(), 'users/sam'), { activeSkinId: 'botanical' }),
    );
  });

  test('activeSkinId must be a short string', async () => {
    const ref = doc(sam(), 'users/sam');
    await assertFails(setDoc(ref, { activeSkinId: 42 }));
    await assertFails(setDoc(ref, { activeSkinId: 'x'.repeat(65) }));
  });

  test('appearance must be system, light or dark', async () => {
    const ref = doc(sam(), 'users/sam');
    for (const appearance of ['system', 'light', 'dark']) {
      await assertSucceeds(setDoc(ref, { appearance }));
    }
    await assertFails(setDoc(ref, { appearance: 'sepia' }));
    await assertFails(setDoc(ref, { appearance: 1 }));
  });

  test('the calendar template and month animation are short strings', async () => {
    const ref = doc(sam(), 'users/sam');
    await assertSucceeds(setDoc(ref, { calendarTemplate: 'wall', monthAnimation: 'wallFlip' }));
    await assertFails(setDoc(ref, { calendarTemplate: 'x'.repeat(65) }));
    await assertFails(setDoc(ref, { monthAnimation: 3 }));
  });
});

describe('data under users/{uid}', () => {
  test('owners can read and write anything below their doc', async () => {
    const ref = doc(sam(), 'users/sam/notebooks/nb1');
    await assertSucceeds(setDoc(ref, { title: 'Ideas' }));
    await assertSucceeds(getDoc(ref));
  });

  test('nobody else can', async () => {
    await seed('users/sam/notebooks/nb1', { title: 'Ideas' });
    await assertFails(getDoc(doc(alex(), 'users/sam/notebooks/nb1')));
    await assertFails(setDoc(doc(alex(), 'users/sam/notebooks/nb2'), {}));
    await assertFails(getDoc(doc(guest(), 'users/sam/notebooks/nb1')));
  });
});

describe('catalog/{itemId}', () => {
  test('signed-in people can read the catalog but not change it', async () => {
    await seed('catalog/night_sky', { name: 'Night sky' });
    await assertSucceeds(getDoc(doc(sam(), 'catalog/night_sky')));
    await assertFails(setDoc(doc(sam(), 'catalog/night_sky'), { name: 'Hacked' }));
  });

  test('signed-out visitors cannot read the catalog', async () => {
    await seed('catalog/night_sky', { name: 'Night sky' });
    await assertFails(getDoc(doc(guest(), 'catalog/night_sky')));
  });
});

test('other collections are closed', async () => {
  await assertFails(setDoc(doc(sam(), 'anything/else'), { a: 1 }));
  await assertFails(getDoc(doc(sam(), 'anything/else')));
});
