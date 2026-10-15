// Tests for firebase/storage.rules. Run with `npm test` in this folder
// (starts the Storage emulator; needs Java).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-notely',
    storage: {
      rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'),
    },
  });
});

after(() => env.cleanup());
beforeEach(() => env.clearStorage());

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

  test('nothing outside the covers folder', async () => {
    await assertFails(uploadBytes(ref(sam(), 'users/sam/other.jpg'), jpeg, asJpeg));
  });
});
