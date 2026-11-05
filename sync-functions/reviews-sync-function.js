/**
 * inventory.reviews: Nomad-written reviews (imported with admin rights), read by the team.
 * Phones cannot write in phase 1. Fails closed on any other document type.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "review", ADMIN_ROLE = "admin", ADMIN_CHANNEL = "admin";
  var KINDS = ["reconciliation", "digest"];

  if (doc._deleted) {
    if (!oldDoc || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a review" });
    requireRole(ADMIN_ROLE);
    return;
  }
  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only reviews belong in inventory.reviews" });
  if (oldDoc && !oldDoc._deleted && oldDoc.type !== DOC_TYPE) {
    throw ({ forbidden: "a document cannot become a review" });
  }

  if (typeof doc.team !== "string" || !doc.team) throw ({ forbidden: "team is required" });
  if (KINDS.indexOf(doc.kind) < 0) throw ({ forbidden: "kind must be reconciliation or digest" });
  if (typeof doc.day !== "string" || !doc.day) throw ({ forbidden: "day is required" });

  requireRole(ADMIN_ROLE);
  channel(doc.team);
  channel(ADMIN_CHANNEL);
}
