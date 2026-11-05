# Adding the cold-chain follow-up to App Services

The phone app can now follow up a Nomad cold-chain alert: the store crew asks the truck's driver
for the reefer temperature, the driver replies in the app, the crew sends the case to the
manager, and the manager acknowledges. Every step is a small document in a new collection,
`inventory.coldchain`, so the manager can see who did what and when, including requests the driver
has not answered yet.

Drivers are a new kind of user, and they must see only their own truck and its requests. Today
four kinds of store data go to the public channel `!`, which every signed-in user can read: store
products, locations, trucks and the cold-chain alert. This change moves them to a channel
`stores`, which store crews and the manager get and drivers do not.

All of it is on the endpoint that is already live
(`wss://gdpqyltlbvh5ubbb.apps.cloud.couchbase.com/inventorycount`). Allow about 30 minutes; phones
cannot sync while the endpoint is offline (steps 2 to 7).

| What | Value |
|---|---|
| Cluster | `cb.6acsrqvgndtvtmx.cloud.couchbase.com` |
| Bucket / scope | `inventorycount` / `inventory` |
| New collection | `coldchain` |
| Access rules | 5 files in this folder: 1 new, 4 changed |
| New channel | `stores` (replaces `!`) |
| New App Role | `driver` |
| New App User | `marcus` (the demo driver, Marcus Vance, truck TRK-101) |

## 1. Create the collection in the bucket

Capella → the cluster → **Data Tools** (or Buckets) → `inventorycount` → scope `inventory` →
**Add collection** → `coldchain`. It starts empty.

## 2. Take the endpoint offline

App Services → the App Service → endpoint `inventorycount` → **Pause** (Take offline). Wait until
it shows Offline.

## 3. Link the collection

The endpoint → Settings (scope and collections) → add `coldchain`, so it links eight collections.
Save.

## 4. Paste the access rules

The endpoint → **Access and Validation**. For each collection below, replace the function with the
whole content of its file, then Save. `counts`, `reviews` and `shipments` are unchanged.

| Collection | File | Change |
|---|---|---|
| `coldchain` | `coldchain-sync-function.js` | new |
| `catalog` | `catalog-sync-function.js` | store products to `stores` instead of `!` |
| `locations` | `locations-sync-function.js` | to `stores` instead of `!` |
| `trucks` | `trucks-sync-function.js` | to `stores` and `truck-<truck_id>` instead of `!` |
| `proposals` | `proposals-sync-function.js` | the cold-chain alert to `stores` instead of `!` |

What the cold-chain rules allow:

| Event | Who may write it |
|---|---|
| `request`, `escalate`, `share` | the store's crew (channel = the event's `store_id`), or an admin |
| `reply` | a user with role `driver` and channel `truck-<truck_id>`, with a numeric reefer reading |
| `ack` | role `admin` (the manager) |

Everyone signs their own events (`by` must be the signed-in user), events can never be edited,
and only an admin can delete one. Each event goes to the store, `truck-<truck_id>` and `admin`.

## 5. Roles and users

App Services → the endpoint → **App Roles**:
- **Create** role `driver`. It needs no channels of its own.
- Role `admin`: on `coldchain`, `catalog`, `locations` and `trucks`, make sure it has channel
  `admin` (as on the other collections), so the manager keeps seeing everything.

**App Users**:
- **Create** `marcus`: role `driver`; channel `truck-TRK-101` on **two** collections, `coldchain`
  and `trucks`; nothing on the others. Pick a password and send it to Jason directly (not in
  this thread).
- `bob`: add channel **`stores`** on `catalog`, `locations`, `trucks` and `proposals`, and channels
  `bob`, `crew-a`, `store-001` on `coldchain` (as on the other collections). Without `stores`,
  bob's phone loses the products, trucks and the cold-chain alert.
- Any other store crew user: add `stores` the same way.
- `manager`: nothing to change (role `admin`).

## 6. Resync the four changed collections

The existing products, locations, trucks and alert were routed to `!`; a resync routes them to
`stores` (and each truck to its `truck-<id>`). The endpoint (still offline) → **Resync** → select
`catalog`, `locations`, `trucks`, `proposals` → start. Wait until it finishes (minutes).

## 7. Bring the endpoint online

**Resume** (bring the endpoint online).

## 8. Check it worked

- The endpoint's Logs: no `forbidden` errors from the rules during the resync.
- Reply to this note. I then turn the feature on in the app (`TallyColdChain` in `Info.plist`) and
  test with two phones:
  - `bob` (crew `store-001`) still gets products, trucks and the alert, and asks the driver;
  - `marcus` (crew `truck-TRK-101`) gets only his truck and the request, and replies;
  - the manager acknowledges.

## Undo

Paste back the previous `catalog`, `locations`, `trucks` and `proposals` functions (from tally-ios
`main`, `git show main:capella/sync-functions/<file>`), remove `coldchain` from the endpoint, and
resync those four. The app only asks for `coldchain` once `TallyColdChain` is on.
