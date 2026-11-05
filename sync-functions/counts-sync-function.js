/**
 * inventory.counts: two kinds of document, routed to channel(team or store) + "admin". Fails closed.
 * - A phone count (type "count"): written by the team's crew. For a store, team is the store id
 *   (like "store-001") and the count may carry store_id (the same) and sku.
 * - A store stock record (store_id, sku, numeric stock_quantity, no captured_by, or null): the store
 *   system's on-hand, written only by an admin (Nomad and data loads arrive as imports),
 *   read by that store's crew.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "count", ADMIN_ROLE = "admin", ADMIN_CHANNEL = "admin";
  var live = oldDoc && !oldDoc._deleted;

  function isStock(d) {
    return !!d && typeof d.stock_quantity === "number" && typeof d.store_id === "string" &&
      d.store_id !== "" && typeof d.sku === "string" && d.sku !== "" && d.captured_by == null;  // missing or null
  }

  if (doc._deleted) {
    if (live && isStock(oldDoc)) { requireRole(ADMIN_ROLE); return; }
    if (!live || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a count" });
    requireAccess([oldDoc.team, ADMIN_CHANNEL]);
    return;
  }

  if (isStock(doc)) {
    if (live && !isStock(oldDoc)) throw ({ forbidden: "a document cannot become a stock record" });
    requireRole(ADMIN_ROLE);
    channel(doc.store_id);
    channel(ADMIN_CHANNEL);
    return;
  }
  if (live && isStock(oldDoc)) throw ({ forbidden: "a stock record cannot become a count" });

  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only counts belong in inventory.counts" });
  if (live && oldDoc.type !== DOC_TYPE) throw ({ forbidden: "a document cannot become a count" });

  if (!doc.team) throw ({ forbidden: "team is required" });
  if (!doc.item_name) throw ({ forbidden: "item_name is required" });
  if (typeof doc.count !== "number") throw ({ forbidden: "count must be a number" });
  if (!doc.location || typeof doc.location !== "object") throw ({ forbidden: "location object is required" });
  if (!doc.captured_by) throw ({ forbidden: "captured_by is required" });
  if (!doc.captured_at) throw ({ forbidden: "captured_at is required" });
  if (doc.store_id !== undefined && doc.store_id !== doc.team) {
    throw ({ forbidden: "store_id must be the count's team" });
  }
  if (doc.sku !== undefined && (typeof doc.sku !== "string" || doc.sku === "")) {
    throw ({ forbidden: "sku must be text" });
  }

  var team = live ? oldDoc.team : doc.team;
  if (live) {
    if (doc.captured_by !== oldDoc.captured_by) throw ({ forbidden: "captured_by cannot be changed" });
    if (doc.captured_at !== oldDoc.captured_at) throw ({ forbidden: "captured_at cannot be changed" });
    if (doc.team !== oldDoc.team) { requireRole(ADMIN_ROLE); team = doc.team; }
  }
  requireAccess([team, ADMIN_CHANNEL]);
  channel(team);
  channel(ADMIN_CHANNEL);
}
