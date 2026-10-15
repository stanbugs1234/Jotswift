# Setting up the store

Notely's store code is built and tested, but it stays switched off until the
accounts below exist. Until then, the Templates screen shows prices as
"Coming soon", Buy buttons are disabled, and there's no notebook limit.

Do the steps in order. Apple's and Google's approvals can take a few days,
so start step 1 early. Each step says what to send back to Claude.

**Names used below**

| | |
|---|---|
| iOS bundle id | `com.notelyapp.notely` |
| Android package | `com.notely.notely` |
| Firebase project | `notely-b1aec` |
| Pro subscriptions | `pro_yearly` ($19.99, 7-day free trial), `pro_monthly` ($2.99) |
| Packs | `pack_<id>` ($1.99 small, $2.99 collection), `planner_<id>_<year>` ($3.99), `bundle_<id>` ($5.99) |

Product ids can never be reused, even after deleting them, so type them
exactly as above.

---

## 1. App Store Connect (Apple)

At [appstoreconnect.apple.com](https://appstoreconnect.apple.com):

1. **Business → Agreements:** accept the **Paid Apps** agreement.
2. **Business:** add your **bank account** and fill in the **tax forms**
   (the US form W-9 for a US individual). Paid products won't load until
   these say *Active*. This is the step that takes days.
3. **Apps:** if Notely isn't listed, click **+ → New App**:
   - platform iOS, name *Notely*, bundle id `com.notelyapp.notely`
   - SKU `notely`
4. **Notely → Monetization → Subscriptions:**
   - Create a group called **Notely Pro**.
   - In it, add `pro_yearly` (1 year, $19.99) and `pro_monthly` (1 month, $2.99).
   - On `pro_yearly`, add an **Introductory Offer**: *Free*, 1 week, all countries.
   - Give each one a display name and description, such as "Notely Pro (yearly)".
5. **Notely → Monetization → In-App Purchases:** add each paid pack as
   **Non-Consumable**, with the product id from its catalog listing.
   - When creating the first one, set **Family Sharing** (recommended: **on**). Apple doesn't let you turn it off later.
6. **Users and Access → Integrations → In-App Purchase:**
   - Click **+** to generate an **In-App Purchase key**.
   - Download the `.p8` file (you can only download it once) and note its **Key ID** and the **Issuer ID** shown above it.
   - RevenueCat needs these in step 3.
7. **Users and Access → Sandbox → Test Accounts:** add a test Apple ID.
   - Use a new email address that isn't already an Apple ID.
   - On the iPad, sign in to it under **Settings → App Store → Sandbox Account**.

Note: the **first** in-app purchase has to be submitted for review together with an app version.

## 2. Google Play Console (Android, when you're ready)

At [play.google.com/console](https://play.google.com/console):

1. **Settings → Payments profile:** set up a merchant account.
2. **Create app**: Notely.
3. Upload a build to **Testing → Internal testing**. Products can only be added after a build that uses billing is uploaded; Claude can make that build.
4. **Monetize → Subscriptions:**
   - Add `pro_yearly` with a free-trial offer.
   - Add `pro_monthly`.
5. **Monetize → In-app products:** add each pack with the same ids.
6. RevenueCat's guide **"Creating Play Service Credentials"** walks you through making a service account JSON file for step 3.

## 3. RevenueCat

At [app.revenuecat.com](https://app.revenuecat.com) (free until you earn
$2,500 a month):

1. **Create a project** named Notely.
2. **Apps & providers:**
   - **App Store:** bundle id `com.notelyapp.notely`; upload the `.p8` key with its Key ID and Issuer ID.
   - **Play Store** (later): package `com.notely.notely`; upload the service account JSON.
   - **Web Billing** (for the web app, later): connect your **Stripe** account.
3. **Product catalog → Products:** import or add every product id.
4. **Product catalog → Entitlements:**
   - Create one entitlement with the identifier **`pro`**.
   - Attach `pro_yearly` and `pro_monthly` to it.
   - Don't attach packs. The app recognises them by their product ids.
5. **API keys:**
   - Copy the **public** SDK keys: `appl_…` for iOS, and later `goog_…` and `rcb_…`. These are safe to share, and they go into the app.
   - Also create a **secret** API key (`sk_…`, API version **v1**). Keep it private; it only goes into Firebase (step 4).

**Send Claude:** the public `appl_…` key (and `goog_…` / `rcb_…` once you have them).

## 4. Firebase function (the webhook)

When something is bought, refunded or renewed, RevenueCat tells a Firebase
function. The function then writes what the account owns, so purchases
appear on every device and on the web.

1. Make up a long random password for the webhook:
   ```sh
   openssl rand -hex 32
   ```
2. Store both secrets in Firebase. They already exist with placeholder values (Firebase needs them to deploy any function). These commands replace the placeholders, asking you to paste each value:
   ```sh
   cd ~/Motley
   firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH   # the random password
   firebase functions:secrets:set REVENUECAT_SECRET_KEY     # the sk_… key
   ```
3. Deploy the function. Claude can do this step for you once the secrets are set:
   ```sh
   firebase deploy --only functions
   ```
   It prints a URL ending in `/revenuecatWebhook`.
4. In RevenueCat, go to **Integrations → Webhooks → Add**:
   - URL: the one printed in step 3.
   - Authorization header value: the random password from step 1.
   - Click **Send test event**. A 200 response means it works.

## 5. Things Apple checks in review

- **A privacy policy URL**, and the **Terms of Use**.
  - Apple's standard EULA is fine for Terms of Use.
  - Both must be linked in the App Store description and on the paywall. Send Claude the URLs and they'll be added to the paywall.
- **Restore Purchases** is on the Templates screen, in Settings and on the paywall.
- **Account deletion** is in Settings.

## 6. Putting a paid item on sale

1. In its `catalog/<id>/listing.json`, set the product in `unlock`:
   ```json
   "unlock": { "pro": true, "products": ["pack_botanical"] }
   ```
   Items with `"collectionId": "botanical"` automatically include the collection's products and Pro.
2. Publish it hidden:
   `python3 tool/catalog.py publish <id> --hidden`
3. Create the product in App Store Connect (and Play) and in RevenueCat, and wait for Apple to approve it.
4. Publish it to testers, try a sandbox purchase, then publish it for everyone:
   `python3 tool/catalog.py publish <id> --public`

If a collection's products change, publish each item in it again.

## How it works (for reference)

- The app signs in to RevenueCat with the Firebase uid
  (`lib/core/purchases/`).
- **Unlocking:**
  - A purchase unlocks the item on this device straight away, from the store receipt.
  - A few seconds later the webhook writes `users/{uid}.entitlements` (`firebase/functions/src/entitlements.ts`), which unlocks it everywhere.
  - Downloads are checked against the same map (`firebase/storage.rules`).
- **The webhook:**
  - On any event, it asks RevenueCat for the customer's current state and rewrites `pro`, `proUntil` and `products`. So repeated, late or out-of-order events can't leave things wrong.
  - It never touches `grants`, which are given by hand.
- **Ending Pro or a refund:**
  - Notebooks and pages keep their covers, papers and templates.
  - Only new use is locked.
- **Builds:**
  - Keys go in at build time: `--dart-define=REVENUECAT_APPLE_KEY=appl_…`, and `REVENUECAT_GOOGLE_KEY` / `REVENUECAT_WEB_KEY` for the others.
  - A build without a key has the store switched off.
