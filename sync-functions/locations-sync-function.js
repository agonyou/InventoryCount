/**
 * inventory.locations: reference locations, readable by everyone ("!"), written by admins only.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "location";
  var live = oldDoc && !oldDoc._deleted;

  requireRole("admin");
  if (doc._deleted) {
    if (!live || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a location" });
    return;
  }
  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only locations belong in inventory.locations" });
  if (live && oldDoc.type !== DOC_TYPE) throw ({ forbidden: "a document cannot become a location" });
  if (!doc.location || typeof doc.location !== "object") throw ({ forbidden: "location object is required" });
  channel("!");
}
