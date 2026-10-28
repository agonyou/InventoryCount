/**
 * locations-sync-function.js — inventory/locations, SHARED READ-ONLY.
 * Routed to the public "!" channel; only the admin role (manager) writes.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "location";
  if (doc.type == DOC_TYPE || (doc._deleted && oldDoc && oldDoc.type == DOC_TYPE)) {
    requireRole("admin");
    if (doc._deleted) { return; }
    if (!doc.location || typeof doc.location !== "object") throw ({ forbidden: "location object is required" });
    if (oldDoc && !oldDoc._deleted) {
      if (doc.type !== oldDoc.type) throw ({ forbidden: "type cannot be changed" });
    }
    channel("!");
  }
}
