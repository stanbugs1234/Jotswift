// Tests for firebase/storage.rules. Run with `npm test` in this folder
// (starts the Storage emulator; needs Java).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-notely',
    // Pack rules look up the catalog and the user's purchases in Firestore.
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
    storage: {
      rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'),
    },
  });
});

after(() => env.cleanup());
beforeEach(async () => {
  await env.clearStorage();
  await env.clearFirestore();
});

const sam = () => env.authenticatedContext('sam').storage();
const alex = () => env.authenticatedContext('alex').storage();
const guest = () => env.unauthenticatedContext().storage();

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
const asJpeg = { contentType: 'image/jpeg' };

describe('users/{uid}/covers', () => {
  test('people can upload, read and delete their own cover photos', async () => {
    const photo = ref(sam(), 'users/sam/covers/1.jpg');
    await assertSucceeds(uploadBytes(photo, jpeg, asJpeg));
    await assertSucceeds(getBytes(photo));
    await assertSucceeds(deleteObject(photo));
  });

  test("nobody else can read or write them", async () => {
    await uploadBytes(ref(sam(), 'users/sam/covers/1.jpg'), jpeg, asJpeg);

    await assertFails(getBytes(ref(alex(), 'users/sam/covers/1.jpg')));
    await assertFails(uploadBytes(ref(alex(), 'users/sam/covers/2.jpg'), jpeg, asJpeg));
    await assertFails(getBytes(ref(guest(), 'users/sam/covers/1.jpg')));
  });

  test('only images under 5 MB', async () => {
    await assertFails(
      uploadBytes(ref(sam(), 'users/sam/covers/a.txt'), jpeg, {
        contentType: 'text/plain',
      }),
    );
    const big = new Uint8Array(5 * 1024 * 1024);
    await assertFails(uploadBytes(ref(sam(), 'users/sam/covers/big.jpg'), big, asJpeg));
  });

  test('photos on pages go in the images folder, the same way', async () => {
    const photo = ref(sam(), 'users/sam/images/1.jpg');
    await assertSucceeds(uploadBytes(photo, jpeg, asJpeg));
    await assertSucceeds(getBytes(photo));
    await assertFails(getBytes(ref(alex(), 'users/sam/images/1.jpg')));
    await assertFails(
      uploadBytes(ref(sam(), 'users/sam/images/a.txt'), jpeg, {
        contentType: 'text/plain',
      }),
    );
  });

  test('nothing outside those folders', async () => {
    await assertFails(uploadBytes(ref(sam(), 'users/sam/other.jpg'), jpeg, asJpeg));
    await assertFails(uploadBytes(ref(sam(), 'users/sam/docs/1.jpg'), jpeg, asJpeg));
  });
});

/** Writes as tool/catalog.py would: past the rules. */
const seedDoc = (path, data) =>
  env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), path), data));
const seedFile = (path) =>
  env.withSecurityRulesDisabled((ctx) => uploadBytes(ref(ctx.storage(), path), jpeg));

describe('catalog files', () => {
  const pack = (id) => `catalog/${id}/1/pack.zip`;

  beforeEach(async () => {
    await seedDoc('catalog/free_cover', { unlock: { free: true } });
    await seedDoc('catalog/pro_cover', { unlock: { pro: true } });
    await seedDoc('catalog/sold_cover', { unlock: { products: ['pack_x'] } });
    for (const id of ['free_cover', 'pro_cover', 'sold_cover']) {
      await seedFile(pack(id));
      await seedFile(`catalog/${id}/1/preview.webp`);
    }
  });

  test('previews are open to anyone signed in, not to visitors', async () => {
    await assertSucceeds(getBytes(ref(sam(), 'catalog/sold_cover/1/preview.webp')));
    await assertFails(getBytes(ref(guest(), 'catalog/sold_cover/1/preview.webp')));
  });

  test('free packs can be downloaded by anyone signed in', async () => {
    await assertSucceeds(getBytes(ref(sam(), pack('free_cover'))));
    await assertFails(getBytes(ref(guest(), pack('free_cover'))));
  });

  test('paid packs need the purchase, Pro or a grant', async () => {
    await seedDoc('users/sam', { activeSkinId: 'classic' });
    await assertFails(getBytes(ref(sam(), pack('pro_cover'))));
    await assertFails(getBytes(ref(sam(), pack('sold_cover'))));

    await seedDoc('users/sam', { entitlements: { pro: true, products: ['pack_x'] } });
    await assertSucceeds(getBytes(ref(sam(), pack('pro_cover'))));
    await assertSucceeds(getBytes(ref(sam(), pack('sold_cover'))));

    await seedDoc('users/alex', { entitlements: { grants: ['sold_cover'] } });
    await assertSucceeds(getBytes(ref(alex(), pack('sold_cover'))));
  });

  test('nobody can upload to the catalog from the app', async () => {
    await assertFails(uploadBytes(ref(sam(), pack('new_cover')), jpeg, asJpeg));
  });
});
