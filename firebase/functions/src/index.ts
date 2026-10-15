// Notely's Cloud Functions.

import { timingSafeEqual } from "node:crypto";

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import * as functionsV1 from "firebase-functions/v1";
import { defineSecret } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

import { eraseUser } from "./accounts.js";
import { applyWebhook, revenueCatFetcher } from "./entitlements.js";

initializeApp();

/** The Authorization header value set on the webhook in RevenueCat. */
const webhookAuth = defineSecret("REVENUECAT_WEBHOOK_AUTH");

/** RevenueCat's secret API key (v1), to read customers. */
const revenueCatKey = defineSecret("REVENUECAT_SECRET_KEY");

function sameSecret(given: string | undefined, expected: string): boolean {
  const a = Buffer.from(given ?? "");
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** RevenueCat calls this after every purchase, renewal, refund, expiry and
 * transfer. It updates users/{uid}.entitlements. */
export const revenuecatWebhook = onRequest(
  { secrets: [webhookAuth, revenueCatKey], maxInstances: 10 },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("POST only");
      return;
    }
    if (!sameSecret(req.get("Authorization"), webhookAuth.value())) {
      res.status(401).send("Wrong authorization");
      return;
    }
    try {
      const uids = await applyWebhook(
        getFirestore(),
        req.body,
        revenueCatFetcher(revenueCatKey.value()),
      );
      logger.info("Entitlements updated", { type: req.body?.event?.type, uids });
      res.status(200).send("ok");
    } catch (e) {
      // RevenueCat retries failed deliveries.
      logger.error("Webhook failed", e);
      res.status(500).send("error");
    }
  },
);

/** When an account is deleted (from Settings, or in the Firebase console),
 * erases its notebooks, pages, ink, tasks, events, settings and files. */
export const deleteUserData = functionsV1.auth.user().onDelete(async (user) => {
  await eraseUser(getFirestore(), (prefix) =>
    getStorage().bucket().deleteFiles({ prefix }), user.uid);
  logger.info("Account data erased", { uid: user.uid });
});
