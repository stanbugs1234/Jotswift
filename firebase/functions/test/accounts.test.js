// Tests erasing an account's data against the Firestore emulator.
import assert from "node:assert/strict";
import { after, test } from "node:test";

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { eraseUser } from "../lib/accounts.js";

const app = initializeApp({ projectId: "demo-notely" }, "accounts");
const db = getFirestore(app);
after(() => app.delete());

test("erases the account's documents, subcollections and files", async () => {
  const paths = [
    "users/sam",
    "users/sam/notebooks/n1",
    "users/sam/notebooks/n1/sections/s1",
    "users/sam/pages/p1",
    "users/sam/pages/p1/strokes/k1",
    "users/sam/pages/planner-2026-10-14/strokes/k2",
    "users/sam/tasks/t1",
    "users/sam/events/e1",
    "users/alex",
    "users/alex/tasks/t1",
  ];
  for (const p of paths) await db.doc(p).set({ x: 1 });
  // Ink on a planner page whose page document was never written.
  await db.doc("users/sam/pages/orphan/strokes/k3").set({ x: 1 });

  const deletedPrefixes = [];
  await eraseUser(db, async (prefix) => { deletedPrefixes.push(prefix); }, "sam");

  for (const p of [...paths.filter((p) => p.startsWith("users/sam")),
    "users/sam/pages/orphan/strokes/k3"]) {
    assert.equal((await db.doc(p).get()).exists, false, p);
  }
  assert.equal((await db.doc("users/alex/tasks/t1").get()).exists, true);
  assert.deepEqual(deletedPrefixes, ["users/sam/"]);
});

test("refuses ids that aren't a single document id", async () => {
  await assert.rejects(eraseUser(db, async () => {}, "sam/../alex"));
  await assert.rejects(eraseUser(db, async () => {}, ""));
});
