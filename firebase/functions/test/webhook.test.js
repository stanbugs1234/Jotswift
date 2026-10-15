// Tests the RevenueCat webhook with recorded events against the Firestore
// emulator. RevenueCat itself is faked: each test says what it knows.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, beforeEach, describe, test } from "node:test";

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import { applyWebhook, entitlementsOf, usersOf } from "../lib/entitlements.js";

const event = (name) =>
  JSON.parse(readFileSync(new URL(`events/${name}.json`, import.meta.url)));

const NOW = new Date("2026-10-14T12:00:00Z");
const LATER = "2026-11-14T12:00:00Z";
const EARLIER = "2026-10-01T12:00:00Z";

describe("entitlementsOf", () => {
  test("an active Pro subscription", () => {
    const e = entitlementsOf({ entitlements: { pro: { expires_date: LATER } } }, NOW);
    assert.deepEqual(e, { pro: true, proUntil: new Date(LATER), products: [] });
  });

  test("an expired Pro subscription", () => {
    const e = entitlementsOf({ entitlements: { pro: { expires_date: EARLIER } } }, NOW);
    assert.equal(e.pro, false);
    assert.equal(e.proUntil, null);
  });

  test("Pro in its billing grace period", () => {
    const e = entitlementsOf(
      { entitlements: { pro: { expires_date: EARLIER, grace_period_expires_date: LATER } } },
      NOW,
    );
    assert.equal(e.pro, true);
    assert.deepEqual(e.proUntil, new Date(LATER));
  });

  test("Pro without an end date (a lifetime grant)", () => {
    const e = entitlementsOf({ entitlements: { pro: { expires_date: null } } }, NOW);
    assert.deepEqual(e, { pro: true, proUntil: null, products: [] });
  });

  test("bought packs, without refunded ones", () => {
    const e = entitlementsOf(
      {
        non_subscriptions: {
          pack_botanical: [{}],
          planner_botanical_2027: [{ refunded_at: EARLIER }],
          bundle_all: [{ refunded_at: EARLIER }, {}],
        },
      },
      NOW,
    );
    assert.deepEqual(e.products, ["bundle_all", "pack_botanical"]);
  });
});

describe("usersOf", () => {
  test("the buyer of an ordinary event", () => {
    assert.deepEqual(usersOf(event("pack_purchase")), ["uid_sam"]);
  });

  test("both sides of a transfer, without anonymous ids", () => {
    assert.deepEqual(usersOf(event("transfer")), ["uid_old", "uid_new"]);
  });

  test("nobody for an anonymous purchase", () => {
    assert.deepEqual(usersOf(event("anonymous_purchase")), []);
  });

  test("nobody for ids that aren't document ids", () => {
    assert.deepEqual(usersOf({ event: { type: "RENEWAL", app_user_id: "a/b" } }), []);
    assert.deepEqual(usersOf({}), []);
  });
});

describe("applyWebhook (Firestore emulator)", () => {
  const app = initializeApp({ projectId: "demo-notely" });
  const db = getFirestore(app);

  /** A fake RevenueCat that answers with [customers][uid]. */
  const revenueCat = (customers) => async (uid) => customers[uid] ?? {};
  const entitlements = async (uid) =>
    (await db.doc(`users/${uid}`).get()).data()?.entitlements;

  beforeEach(async () => {
    for (const uid of ["uid_sam", "uid_old", "uid_new"]) {
      await db.doc(`users/${uid}`).delete();
    }
  });
  after(() => app.delete());

  test("a Pro trial starts Pro", async () => {
    await applyWebhook(
      db,
      event("initial_purchase_pro"),
      revenueCat({ uid_sam: { entitlements: { pro: { expires_date: LATER } } } }),
      () => NOW,
    );
    const e = await entitlements("uid_sam");
    assert.equal(e.pro, true);
    assert.deepEqual(e.proUntil.toDate(), new Date(LATER));
    assert.deepEqual(e.products, []);
  });

  test("a pack purchase, then its refund", async () => {
    await db.doc("users/uid_sam").set({ appearance: "dark" });
    await applyWebhook(
      db,
      event("pack_purchase"),
      revenueCat({ uid_sam: { non_subscriptions: { pack_botanical: [{}] } } }),
      () => NOW,
    );
    assert.deepEqual((await entitlements("uid_sam")).products, ["pack_botanical"]);

    await applyWebhook(
      db,
      event("pack_refund"),
      revenueCat({ uid_sam: { non_subscriptions: {} } }),
      () => NOW,
    );
    assert.deepEqual((await entitlements("uid_sam")).products, []);
    // Settings on the same document are kept.
    assert.equal((await db.doc("users/uid_sam").get()).data().appearance, "dark");
  });

  test("an expired subscription ends Pro but keeps packs and grants", async () => {
    await db.doc("users/uid_sam").set({
      entitlements: { pro: true, products: ["pack_botanical"], grants: ["study_pack"] },
    });
    await applyWebhook(
      db,
      event("pro_expiration"),
      revenueCat({
        uid_sam: {
          entitlements: { pro: { expires_date: EARLIER } },
          non_subscriptions: { pack_botanical: [{}] },
        },
      }),
      () => NOW,
    );
    const e = await entitlements("uid_sam");
    assert.equal(e.pro, false);
    assert.equal(e.proUntil, null);
    assert.deepEqual(e.products, ["pack_botanical"]);
    assert.deepEqual(e.grants, ["study_pack"]);
  });

  test("a transfer moves purchases between accounts", async () => {
    await db.doc("users/uid_old").set({ entitlements: { pro: false, products: ["pack_botanical"] } });
    const uids = await applyWebhook(
      db,
      event("transfer"),
      revenueCat({ uid_new: { non_subscriptions: { pack_botanical: [{}] } } }),
      () => NOW,
    );
    assert.deepEqual(uids, ["uid_old", "uid_new"]);
    assert.deepEqual((await entitlements("uid_old")).products, []);
    assert.deepEqual((await entitlements("uid_new")).products, ["pack_botanical"]);
  });

  test("an anonymous purchase writes nothing", async () => {
    const uids = await applyWebhook(
      db,
      event("anonymous_purchase"),
      () => assert.fail("RevenueCat shouldn't be asked"),
      () => NOW,
    );
    assert.deepEqual(uids, []);
  });
});
