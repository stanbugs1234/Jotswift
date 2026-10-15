// Turns what RevenueCat knows about a customer into users/{uid}.entitlements
// (docs/skins-plan.md §7). The app reads that map; only this code writes it.

import { FieldValue, Timestamp, type Firestore } from "firebase-admin/firestore";

/** RevenueCat's entitlement for Notely Pro. */
export const PRO = "pro";

/** The parts of RevenueCat's GET /v1/subscribers/{id} response we use. */
export interface Subscriber {
  entitlements?: Record<
    string,
    { expires_date?: string | null; grace_period_expires_date?: string | null }
  >;
  non_subscriptions?: Record<string, Array<{ refunded_at?: string | null }>>;
}

export interface Entitlements {
  pro: boolean;
  /** When Pro ends unless it renews; null for no end (or no Pro). */
  proUntil: Date | null;
  /** Packs, planners and bundles bought and not refunded. */
  products: string[];
}

/** What [subscriber] may use at [now]. */
export function entitlementsOf(subscriber: Subscriber, now: Date): Entitlements {
  const pro = subscriber.entitlements?.[PRO];
  let until: Date | null = null;
  let active = false;
  if (pro) {
    const ends = [pro.expires_date, pro.grace_period_expires_date]
      .filter((d): d is string => !!d)
      .map((d) => new Date(d));
    if (pro.expires_date == null) {
      active = true; // Never expires (a lifetime grant).
    } else {
      until = new Date(Math.max(...ends.map((d) => d.getTime())));
      active = until > now;
    }
  }
  const products = Object.entries(subscriber.non_subscriptions ?? {})
    .filter(([, purchases]) => purchases.some((p) => !p.refunded_at))
    .map(([id]) => id)
    .sort();
  return { pro: active, proUntil: active ? until : null, products };
}

/** A RevenueCat webhook body (only what we use). */
export interface WebhookBody {
  event?: {
    type?: string;
    app_user_id?: string;
    transferred_from?: string[];
    transferred_to?: string[];
  };
}

/** The Firebase uids an event changes. Anonymous RevenueCat ids (before
 * sign-in) aren't accounts and are skipped. */
export function usersOf(body: WebhookBody): string[] {
  const event = body.event ?? {};
  const ids =
    event.type === "TRANSFER"
      ? [...(event.transferred_from ?? []), ...(event.transferred_to ?? [])]
      : [event.app_user_id];
  return [
    ...new Set(
      ids.filter(
        (id): id is string =>
          typeof id === "string" &&
          id.length > 0 &&
          id.length <= 128 &&
          !id.startsWith("$RCAnonymousID") &&
          !id.includes("/"),
      ),
    ),
  ];
}

export type FetchSubscriber = (uid: string) => Promise<Subscriber>;

/** Rewrites users/{uid}.entitlements from RevenueCat for everyone [body]
 * concerns. Every event is handled the same way: ask RevenueCat for the
 * customer's current state. That copes with events arriving twice or out of
 * order, refunds, renewals, expiry and transfers alike. `grants` (given by
 * support) is left alone. */
export async function applyWebhook(
  db: Firestore,
  body: WebhookBody,
  fetchSubscriber: FetchSubscriber,
  now: () => Date = () => new Date(),
): Promise<string[]> {
  const uids = usersOf(body);
  for (const uid of uids) {
    const e = entitlementsOf(await fetchSubscriber(uid), now());
    await db.doc(`users/${uid}`).set(
      {
        entitlements: {
          pro: e.pro,
          proUntil: e.proUntil ? Timestamp.fromDate(e.proUntil) : null,
          products: e.products,
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    );
  }
  return uids;
}

/** Reads a customer from RevenueCat's REST API with the secret key. */
export function revenueCatFetcher(secretKey: string): FetchSubscriber {
  return async (uid) => {
    const res = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}`,
      { headers: { Authorization: `Bearer ${secretKey}` } },
    );
    if (!res.ok) {
      throw new Error(`RevenueCat answered ${res.status} for ${uid}`);
    }
    const json = (await res.json()) as { subscriber?: Subscriber };
    return json.subscriber ?? {};
  };
}
