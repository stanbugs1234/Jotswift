# Setting up the store

The full list of products and prices to create is in [pricing.md](pricing.md).

Jotswift's store code is built and tested, but it stays switched off until the
accounts below exist. Until then, the Templates screen shows prices as
"Coming soon", Buy buttons are disabled, and there's no notebook limit.

Do the steps in order. Apple's and Google's approvals can take a few days,
so start step 1 early. Each step says what Claude can do for you.

**Names used below**

| | |
|---|---|
| iOS bundle id | `com.notelyapp.notely` |
| Android package | `com.notely.notely` |
| Firebase project | `notely-b1aec` |
| Pro subscriptions | `pro_yearly` ($19.99, 7-day free trial), `pro_monthly` ($3.99), `pro_lifetime` ($49.99, non-consumable) |
| Packs | `pack_<id>` ($1.99 small, $4.99 collection), `planner_<id>_<year>` ($3.99), `bundle_<id>` ($5.99) |

Product ids can never be reused, even after deleting them, so type them
exactly as above.

---

## 1. App Store Connect (Apple)

At [appstoreconnect.apple.com](https://appstoreconnect.apple.com):

1. **Business → Agreements:** accept the **Paid Apps** agreement.
2. **Business:** add your **bank account** and fill in the **tax forms**
   (the US form W-9 for a US individual). Paid products won't load until
   these say *Active*. This is the step that takes days.
3. **Apps:** if Jotswift isn't listed, click **+ → New App**:
   - platform iOS, name *Jotswift*, bundle id `com.notelyapp.notely`
   - SKU `notely`
4. **Products.** Once step 2 says *Active*, Claude creates them for you with
   the App Store Connect API (ask first; it uses the key the TestFlight script
   already uses):
   ```sh
   python3 tool/asc_products.py check    # what exists, what's missing
   python3 tool/asc_products.py create   # the 30 launch products
   ```
   The launch products are:
   - the **Jotswift Pro** subscription group with `pro_yearly` ($19.99, one
     week free) and `pro_monthly` ($3.99);
   - `pro_lifetime` ($49.99, non-consumable);
   - the bestseller planners and the bundles.

   Everything else is included in Pro; `create --all` adds the rest of
   [pricing.md](pricing.md) later. Family Sharing is on for all of them
   (Apple doesn't let you turn it off later).
5. **Review screenshots (by hand):** each product needs one screenshot for
   Apple's reviewer under **Review Information**: a screenshot of the
   paywall for the Pro products, and of the item's store page for the others.
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
2. **Create app**: Jotswift.
3. Upload a build to **Testing → Internal testing**. Products can only be added after a build that uses billing is uploaded; Claude can make that build.
4. **Monetize → Subscriptions:**
   - Add `pro_yearly` with a free-trial offer.
   - Add `pro_monthly`.
5. **Monetize → In-app products:** add each pack with the same ids.
6. RevenueCat's guide **"Creating Play Service Credentials"** walks you through making a service account JSON file for step 3.

## 3. RevenueCat

At [app.revenuecat.com](https://app.revenuecat.com) (free until you earn
$2,500 a month):

1. **Create a project** named Jotswift.
2. **Apps & providers:**
   - **App Store:** bundle id `com.notelyapp.notely`; upload the `.p8` key with its Key ID and Issuer ID.
   - **Play Store** (later): package `com.notely.notely`; upload the service account JSON.
   - **Web Billing** (for the web app, later): connect your **Stripe** account.
3. **Product catalog → Products:** import or add every product id.
4. **Product catalog → Entitlements:**
   - Create one entitlement with the identifier **`jotswift_pro`**.
   - Attach `pro_yearly`, `pro_monthly` and `pro_lifetime` to it (and, in the
     Test Store, `yearly`, `monthly` and `lifetime`). Without the lifetime
     product, a lifetime buyer gets Pro only on the device they bought on.
   - Don't attach packs. The app recognises them by their product ids.
5. **Product catalog → Offerings:** make one offering, marked **Current**,
   with three packages: **Annual** (`$rc_annual`), **Monthly**
   (`$rc_monthly`) and **Lifetime** (`$rc_lifetime`), each holding that
   plan's product for each store. The app reads Pro's plans and prices from
   these packages, so the product behind a plan can change without an app
   update.
6. **Paywalls:** design the paywall for that offering. On iPhone and iPad
   the app shows it wherever Pro is offered (the web app keeps its own).
   Without a design, RevenueCat shows a plain default one.
7. **Customer Center:** turn it on (Tools → Customer Center). Pro
   subscribers open it from Settings → Manage subscription to change plan,
   cancel or ask for a refund.
8. **API keys:**
   - Copy the **public** SDK keys: `appl_…` for iOS, and later `goog_…` and `rcb_…`. These are safe to share, and they go into the app.
   - Also create a **secret** API key (`sk_…`, API version **v1**). Keep it private; it only goes into Firebase (section 4).

**Save the public `appl_…` key on this Mac** (don't paste it into a chat):
```sh
mkdir -p ~/.appstoreconnect
pbpaste > ~/.appstoreconnect/revenuecat_apple_key   # after copying the key
```
`tool/release_testflight.sh` reads it from there and says "Store on" when it
builds.

**Trying the store without real payments:** RevenueCat's **Test Store** key
(`test_…`) sells its test products with no App Store setup. Save it in
`~/.appstoreconnect/revenuecat_test_key` the same way, then run
`tool/run_test_store.sh` for a debug build on a device or simulator. Release
builds ignore a Test Store key, and the TestFlight script refuses one.

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

- **A privacy policy URL**, and the **Terms of Use**. They're in `web/`
  (privacy.html, terms.html, support.html) and served by Firebase Hosting at
  `https://notely-b1aec.web.app/privacy.html` and so on, once hosting is
  deployed.
  - The paywall, sign-in screen and Settings link to them.
  - In App Store Connect, put the privacy URL under **App Privacy**, the
    support URL under the version's **Support URL**, and add the terms link
    to the end of the App Store description ("Terms of Use: …").
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
