/**
 * inventory.trucks: the fleet (type "truck"), written only by an admin (data loads and
 * telematics arrive as imports). Store crews and the manager see every truck (channel
 * "stores"); a driver sees only their own (channel "truck-<truck_id>"). Fails closed.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "truck";
  var live = oldDoc && !oldDoc._deleted;

  requireRole("admin");
  if (doc._deleted) {
    if (!live || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a truck" });
    return;
  }
  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only trucks belong in inventory.trucks" });
  if (live && oldDoc.type !== DOC_TYPE) throw ({ forbidden: "a document cannot become a truck" });
  if (typeof doc.truck_id !== "string" || !doc.truck_id) throw ({ forbidden: "truck_id is required" });
  channel("stores");
  channel("truck-" + doc.truck_id);
  channel("admin");
}
