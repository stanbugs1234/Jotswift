# Testing Notely on an iPad

You need a Mac with Xcode, the iPad, and a USB cable.

## One-time setup (about 20 minutes)

1. **Install Flutter.** In Terminal:
   ```sh
   brew install --cask flutter
   brew install cocoapods
   ```
   No Homebrew? Install it from https://brew.sh first.
   Then run `flutter doctor` and fix anything it marks with ✗ under Xcode.

2. **Get the code:**
   ```sh
   git clone https://github.com/stanbugs1234/Motley.git
   cd Motley
   flutter pub get
   ```

3. **Connect the iPad** with the cable. Unlock it and tap **Trust** when it asks.

4. **Turn on Developer Mode** on the iPad: **Settings → Privacy & Security → Developer Mode → On**. The iPad restarts.
   (The option only appears after the iPad has been connected to a Mac running Xcode.)

5. **Set up signing:**
   ```sh
   open ios/Runner.xcworkspace
   ```
   In Xcode, click **Runner** at the top of the left sidebar, then the **Runner** target, then **Signing & Capabilities**:
   - Tick **Automatically manage signing**
   - **Team:** pick your Apple Developer team
   - **Bundle Identifier** should read `com.notelyapp.notely`
   - **Sign in with Apple** should be listed under capabilities

## Run it

In Terminal, in the `Motley` folder:

```sh
flutter run --release
```

Pick the iPad when asked. `--release` matters: debug builds are much slower and would make the pen feel laggy.

The first build takes several minutes. After that, the Notely icon stays on the iPad.

To get the newest version later:

```sh
git pull
flutter run --release
```

## What to test

Before you start: publish the database rules in the Firebase console
(Firestore Database → Rules), or nothing will save.

**Sign-in**
- [ ] Create an account with email and password
- [ ] Sign out, then sign in with Apple

**Handwriting**
- [ ] Create a notebook and a page, and write with the Apple Pencil
- [ ] Does the line keep up with the pen tip, or does it trail behind?
- [ ] Do lines get thicker when you press harder?
- [ ] Rest your palm on the screen while writing: no stray marks?
- [ ] After using the Pencil, does one finger scroll the page?
- [ ] Pinch with two fingers to zoom in and out
- [ ] Highlighter, eraser, colors, sizes, undo and redo
- [ ] Fill a page with lots of writing: does it stay smooth?

**Saving**
- [ ] Close the app completely and reopen it: is everything still there?
- [ ] Turn on Airplane Mode, write something, turn it off: does it still save?
- [ ] Change the skin, then sign in on another device or the web: same skin?

Note anything that feels slow, wrong or confusing, and send it over.

## If something goes wrong

- **"No provisioning profile" or signing errors:** recheck step 5 (Team selected).
- **"Untrusted Developer" on the iPad:** Settings → General → VPN & Device
  Management → your developer account → Trust.
- **Anything else:** copy the last 30 lines from Terminal and send them over.
