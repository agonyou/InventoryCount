# Tally — on-device inventory counting (Couchbase Mobile, iOS)

*Tally is a working name; project/bundle id stay `InventoryCount` / `com.couchbase.InventoryCount` until the owner decides branding.*

A person walks a rack, shelf or room and records what they see by **voice**, **text** or **photo**.
Apple's on-device **Foundation Models** turn the input into sheet rows (item name, count, size ·
shape · color, annotation, site / rack / shelf / bin) and write a two-paragraph summary. Every row
is a Couchbase Lite document. Devices sync **peer-to-peer** (Wi-Fi/Bonjour with Bluetooth
fallback) and, optionally, with **Capella App Services** in the cloud. Works with no connectivity.

| Piece | Where |
|---|---|
| Xcode project — SwiftUI, iOS 26.0, Couchbase Lite Swift EE 4.1.x | `InventoryCount.xcodeproj`, `InventoryCount/` |
| Design tokens (Couchbase Design System: cream page, red highlighter, Figtree / Open Sans / JetBrains Mono) | `InventoryCount/App/Theme.swift`, `InventoryCount/Fonts/` |
| Access Control Functions (one per collection) | `sync-functions/{counts,catalogue,locations}-sync-function.js` |
| Backend provisioning (optional cloud) | `setup-capella.sh` + `provision.env` (teardown: `teardown-capella.sh`) |

## Screens

1. **Voice** — location chip (Rack · Shelf · Bin) and Sheet button in the header; live transcript with partial words dimmed (listening continues across pauses — the system endpointer ends each utterance after a short silence and the app immediately starts a new one on the same audio stream, so dictation ends only when you tap the mic again — or after a configurable silence, default 30 s, Model & sync → "Voice: stop after silence"; both send the un-parsed remainder to the model for preview). **Spoken commands** split bins hands-free: end a phrase with “next bin” / “next shelf” / “next rack”, “bin 15”, “shelf 2”, “rack B”, “location X” — the words before the command are parsed with the current location and added straight to the sheet (flagged if low confidence), the location chip updates (read aloud if that option is on) and listening continues; “done” / “that's all” stops; “scratch that” removes the last saved row); rows heard this session; amber dashed "≈" estimate card; Undo · mic (the one solid-red element) · Next bin.
2. **Text** — labelled multi-line field, **Add to sheet**, preview of parsed rows before saving.
3. **Photo** — camera or library; detected-bin overlay (tap to highlight); chips for QR (sets location) and UPC/EAN (names the product from the on-device catalogue, asks once for unknown codes); scene description; detected items with a **Review counts** badge; Retake / **Add N rows**.
4. **Sheet** — sticky-header table, horizontally scrollable; badges for current location and sync state; Filter, Summarise, Export (CSV share sheet).
5. **Summary** — stat tiles (distinct items, units, need review), model-written summary, **Flagged** list (estimates, low confidence, same item+bin counted by two devices), Regenerate / Share.
6. **Model & sync** — on-device model card (availability badge, keep-loaded switch), capture options (read counts aloud, flag low-confidence), peer-to-peer switch + nearby peers with Synced/Syncing badges, optional Capella sign-in, optional Claude API key.

Switch modes in one tap from the segmented control at the bottom of the capture screen.

## Data model (`inventory` scope)

- **`counts`** — one doc per row: `item_name`, `count`, `count_is_estimate`, `attributes`, `annotation`, `location {site, rack, shelf, bin}`, `source` (`voice|text|photo|code`), `code {type: qr|upc|ean, value}`, `confidence`, `needs_review`, `captured_at`, `captured_by` (device id), `team`, optional `photo` blob. Doc id = `count::<device>::<uuid>`, so two devices never write the same document: **same bin counted twice = two rows kept, flagged in Summary** (the owner's conflict decision).
- **`catalogue`** — `catalogue_item`: UPC/EAN → product name, built on device, team-shared.
- **`locations`** — reference locations (optionally with a QR payload); manager-authored, everyone reads.

Capella access pattern: **Team/Group** for `counts` and `catalogue` (route to `channel(team)` + `admin`; any crew member writes; manager sees all crews), **Shared read-only** for `locations`. Static grants: role `admin` → `admin`; user `bob` → `bob`, `crew-a`.

## Model runtime

- **Primary: Apple Foundation Models** (iOS 26+, Apple Intelligence on). Typed output via `@Generable`; a `prewarm()` backs the "Keep model loaded" switch. Needs a device/simulator with Apple Intelligence; the Model & sync card shows why if unavailable.
- **Photos — two-stage pipeline (`VisionAnalyzer`):** stage 1 *item detection* is a cascade — (a) **label-anchored**: OCR runs in overlapping native-resolution tiles (Vision downsamples big frames and loses small labels), stacked lines become label cards, the horizontal band with the most cards is the *label rail* (staggered front/back sub-rows supported) and each rail card = one item whose box extends up over the product it sits under; labels are cleaned deterministically (`LabelCleaner`: category words like ICE CREAM/GELATO move to *kind*, fragments are dropped, names proper-cased); other text bands (menu boards, signs) go to the model as context, never as items; (b) **foreground instances** (Apple subject lifting, any shape: tubs, bottles, bags) as masks → boxes; (c) **rectangles** for bins/boxes as fallback — merged with overlap suppression, boxes drawn and numbered on the photo, tap to highlight; stage 2 *sub-detection* per item: OCR of the label under/inside it (3× upscaled crop), classification tags, dominant colour. Whole-frame OCR, barcodes and scene tags are added. The text model then gets a structured item list and makes **one row per item or per distinct label** with colour/kind in attributes. **Image input to Foundation Models arrives with the iOS 27 SDK** (this build: Xcode 26.3 / iOS 26.2 SDK), so when a Claude key is present photos are sent to the cloud model by default ("Send photos to cloud model" in Model & sync), which returns real item boxes with name, colour, material and count. Perspective shots of pans/bins are hard for rectangle detection; the cloud path is the accurate one until iOS 27.
- **Fallback: Claude API** (`claude-opus-5-5`, raw HTTPS, key in Keychain) when the on-device model is unavailable or when "Prefer cloud model" is on.
- Speech: `SFSpeechRecognizer` with on-device recognition required when supported. Barcodes live: VisionKit `DataScannerViewController` (device only).

## Setup guide (fresh clone)

### What you need

| Need | For | Notes |
|---|---|---|
| A Mac with **Xcode 26.x** (iOS 26 SDK) and an **iOS 26** simulator | everything | The project targets iOS 26.0. |
| **Apple Intelligence** turned on (Mac for the simulator, or an eligible iPhone) | the on-device model | Without it, use the Claude fallback. |
| A **Claude API key** (optional) | cloud fallback, accurate photo detection | Pasted in the app (Model & sync), stored in the Keychain. Never in a file. |
| An Apple developer team (free or paid) | running on a real iPhone | Not needed for the simulator. |
| A **Capella** account, plus `jq` and `curl` (`brew install jq`) | optional cloud sync only | The free tier is enough. |

Swift packages resolve on first open. The app uses **Couchbase Lite Swift Enterprise Edition 4.1.x**
(`couchbase-lite-swift-ee`), which is free for development; production use needs a Couchbase licence.

### What is in the repo, and what is not

Committed: the app source, the Xcode project, the fonts, the three Access Control Functions, the Capella
setup and teardown scripts, `provision.env.example` and `tools/` (Foundation Models smoke tests).

Not committed (see `.gitignore`):
- `provision.env`: your Capella API key and the generated admin password. Create it from `provision.env.example`.
- `build/`: Xcode build output.
- `test-photos/`: large local test images. Use your own photos.

### Files to update before you run

| File | Setting | What to do | When |
|---|---|---|---|
| Xcode project, **Signing & Capabilities** | Team (`DEVELOPMENT_TEAM`) | Pick your own team. | Real iPhone only |
| Xcode project and `InventoryCount/Info.plist` | Bundle id `com.couchbase.InventoryCount` | Change it to one you own, in both places (`PRODUCT_BUNDLE_IDENTIFIER` and `CFBundleIdentifier`). | Real iPhone only |
| `InventoryCount/Info.plist` | `AppServicesEndpointURL` | It points at the author's demo endpoint. `setup-capella.sh` replaces it with yours. For peer-to-peer only, set it to `wss://PLACEHOLDER`: the app then shows cloud sync as "Not provisioned". | Cloud sync |
| `provision.env` (from `provision.env.example`) | `CB_API_KEY` | Paste your Capella API secret (see the cloud sync steps below). | Cloud sync |
| `provision.env` | `MANAGER_PASS`, `BOB_PASS` | Set your own passwords. Left blank they default to `Password1!`, which is published here, so anyone with your endpoint URL could sign in. | Cloud sync |
| `InventoryCount/App/AppConfig.swift` | scope, collection names, `peerGroupID`, `defaultTeam` | Keep as is. If you rename collections, change `COLLECTIONS` in `provision.env` and the `sync-functions/*-sync-function.js` file names to match. If you run your own fork next to this one, change `peerGroupID` so the two don't sync with each other. | Only if you rename |

Adding a Swift file: add it through Xcode (**File → Add Files**) so it lands in the project.

### First run, in order

1. `git clone https://github.com/agonyou/InventoryCount.git && cd InventoryCount`
2. Simulator run, below ("Run it"). No accounts or keys needed; try `-tallyDemo` for sample rows.
3. Optional: peer-to-peer between two simulators or devices ("Peer-to-peer sync").
4. Optional: cloud sync ("Optional cloud sync — Capella").
5. Optional: a real iPhone. Set your team and bundle id, connect the phone, pick it as the run destination,
   **Cmd+R**. On-device Foundation Models and the live barcode scanner work only on a device.

## Run it (iOS Simulator, no signing)

1. Open `InventoryCount.xcodeproj` in Xcode 26.x.
2. **File → Packages → Resolve Package Versions**.
3. Pick an iPhone simulator running **iOS 26**, **Cmd+Shift+K**, then **Cmd+R**. The app opens straight on Voice capture; no login.
4. Model & sync → check the on-device model badge. If "Apple Intelligence off"/"not eligible" on the simulator, either enable Apple Intelligence on the Mac (simulators borrow the host model) or paste a Claude API key as the cloud fallback.
5. Voice mode needs a microphone — on the simulator use the Mac mic (Simulator → I/O → Audio Input). Photo mode on the simulator uses the photo library (no camera).

Debug launch arguments (Scheme → Run → Arguments): `-tallyDemo` seeds three sample rows; `-tallyRoute sheet|summary|modelSync|location` opens a screen directly.

## Peer-to-peer sync (two devices or two simulators)

1. Model & sync → **Peer-to-peer sync** on, on both devices. iOS asks for Local Network (and Bluetooth) permission.
2. Nearby peers appear within seconds with **Synced / Syncing** badges. Count on one device; rows appear on the other.
3. Transport is DNS-SD over Wi-Fi with BLE fallback (`MultipeerReplicator`, peer group `com.couchbase.tally`). Every device gets a self-signed TLS identity; the authenticator accepts any peer in the group (tighten with `MultipeerCertificateAuthenticator(rootCerts:)` for production).

## Optional cloud sync — Capella (you run this, ~20–45 min, free tier)

1. **Create a Capella API key**: cloud.couchbase.com → your **Organization → Settings → API Keys → Generate Key** → name it → check **Organization Owner** → **Generate** → **download the key** (shown once).
2. **Create `provision.env`**: `cp provision.env.example provision.env`, then paste the key's `APIKeyToken` (shown as *API Secret* in the UI) into `CB_API_KEY=''` and set your own `MANAGER_PASS` and `BOB_PASS`. Leave `APPSVC_ADMIN_PASS` blank (the script generates and saves it). Endpoint, collections and `SYNC_FUNCTIONS_DIR` are already filled in. `provision.env` is gitignored; never commit it.
3. From this folder: `source provision.env && ./setup-capella.sh`. It creates the free-tier cluster, bucket `inventorycount`, scope/collections, App Service + endpoint `inventorycount`, uploads the three Access Control Functions, creates `manager` / `bob` with the passwords from `provision.env` (`Password1!` if left blank), brings the endpoint Online and writes the WSS URL into `InventoryCount/Info.plist`.
4. Rebuild, open **Model & sync → Cloud sync**, sign in as `bob` (crew `crew-a`) or `manager`.

**Project-scoped key or an existing standard cluster?** Set these in `provision.env` before running (IDs come from the Capella console URL `/organizations/<id>/projects/<id>/clusters/<id>/…`): `CB_ORGANIZATION_ID` (required for a Project Owner key, which cannot list organizations), `CB_PROJECT_ID` and optionally `CB_CLUSTER_ID` (adopted directly, never created or altered), `FREE_TIER='false'` (auto-detected if the cluster turns out not to be free tier), `APP_SERVICE_NODES` (2–12 on standard clusters) and `CB_BUCKET_RAM_MB` (default 128). `CB_API_KEY` is the base64 `APIKeyToken` / API Secret, never the 32-character Key ID.

Tear down only on request: `source provision.env && ./teardown-capella.sh`.

## Decisions recorded (2026-10-22)

Sync: P2P **and** Capella · Model: Apple Foundation Models (iOS 27 target when the SDK ships), Claude as fallback · UPC names: on-device catalogue · Conflicts: keep both rows, flag for review · Branding/bundle id: owner's call (placeholder "Tally").

## Troubleshooting

- `Library not loaded: CouchbaseLiteSwift` → Resolve Package Versions, Cmd+Shift+K, Cmd+R.
- "On-device model unavailable" → Apple Intelligence off / device not eligible / model still downloading. Add a Claude key or enable Apple Intelligence.
- **Simulator shows the model as Ready but every request fails** (`GenerationError -1`; the unified log shows `modelmanagerd … no underlying assets` and `HostInferenceProviderService … '_requestConfiguration' not found`): the iOS 26.3 simulator runtime and the host Mac's inference service disagree on the request format, and the simulator has no model assets. Not an app bug — the identical request succeeds on the Mac (run `swiftc -O -o /tmp/fm tools/fm_smoke.swift && /tmp/fm` on this Mac). Test Foundation Models on a physical iPhone with Apple Intelligence, or use the Claude fallback on the simulator.
- P2P shows no peers → both devices on the same Wi-Fi (or Bluetooth on), Local Network permission granted, P2P switch on both.
- Cloud 401 → wrong App User password; 404 → endpoint Offline or URL not written; 403 → ACF not deployed or user not on the row's `team` (re-run `setup-capella.sh`).
