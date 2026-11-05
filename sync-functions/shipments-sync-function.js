/**
 * inventory.shipments: deliveries (type "shipment"), written only by an admin (imports),
 * routed to the destination store's channel + "admin". Fails closed.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "shipment", ADMIN_CHANNEL = "admin";
  var live = oldDoc && !oldDoc._deleted;

  requireRole("admin");
  if (doc._deleted) {
    if (!live || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a shipment" });
    return;
  }
  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only shipments belong in inventory.shipments" });
  if (live && oldDoc.type !== DOC_TYPE) throw ({ forbidden: "a document cannot become a shipment" });
  var store = doc.destination && doc.destination.store_id;
  if (typeof store !== "string" || !store) throw ({ forbidden: "destination.store_id is required" });
  channel(store);
  channel(ADMIN_CHANNEL);
}
