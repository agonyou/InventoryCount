/**
 * inventory.proposals: what Nomad saved after a person approved it (type "proposal"), written
 * only by an admin (Nomad writes with the SDK; App Services imports it), read-only on phones.
 * Routed to the stores it is about, plus "admin". Fails closed on an unknown kind.
 * - purchase_order, count_check, shift_summary, refrigeration_alert, network_alert: one store
 *   (store_id; the last two are Nomad's store IoT workflows, and a site can be dc-01).
 * - replenishment: every store a transfer goes to (transfers[].to_store_ids).
 * - cold_chain_alert: every store crew (channel "stores"; a truck serves several stores), not drivers.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "proposal", ADMIN_CHANNEL = "admin";
  var live = oldDoc && !oldDoc._deleted;

  requireRole("admin");
  if (doc._deleted) {
    if (!live || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a proposal" });
    return;
  }
  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only proposals belong in inventory.proposals" });
  if (live && oldDoc.type !== DOC_TYPE) throw ({ forbidden: "a document cannot become a proposal" });
  if (typeof doc.day !== "string" || !doc.day) throw ({ forbidden: "day is required" });

  var STORE_KINDS = ["purchase_order", "count_check", "shift_summary", "refrigeration_alert", "network_alert"];
  if (STORE_KINDS.indexOf(doc.kind) >= 0) {
    if (typeof doc.store_id !== "string" || !doc.store_id) throw ({ forbidden: "store_id is required" });
    channel(doc.store_id);
  } else if (doc.kind === "replenishment") {
    var transfers = Array.isArray(doc.transfers) ? doc.transfers : [];
    var stores = [];
    for (var i = 0; i < transfers.length; i++) {
      var to = transfers[i] && transfers[i].to_store_ids;
      if (!Array.isArray(to)) continue;
      for (var j = 0; j < to.length; j++) {
        if (typeof to[j] === "string" && to[j] && stores.indexOf(to[j]) < 0) stores.push(to[j]);
      }
    }
    for (var k = 0; k < stores.length; k++) channel(stores[k]);
  } else if (doc.kind === "cold_chain_alert") {
    channel("stores");
  } else {
    throw ({ forbidden: "unknown proposal kind" });
  }
  channel(ADMIN_CHANNEL);
}
