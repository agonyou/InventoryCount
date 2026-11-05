/**
 * inventory.catalog: two kinds of document. Fails closed.
 * - A team's catalog item (type "catalog_item", team): UPC/EAN to a name the crew gave it,
 *   routed to channel(team) + "admin".
 * - A store-system product (sku, name, code {type, value}, no team): written only by an admin
 *   (data loads arrive as imports), readable by store crews and the manager (channel "stores")
 *   but not by drivers.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "catalog_item", ADMIN_ROLE = "admin", ADMIN_CHANNEL = "admin";
  var live = oldDoc && !oldDoc._deleted;

  function isProduct(d) {
    return !!d && d.team === undefined && typeof d.sku === "string" && d.sku !== "" &&
      typeof d.name === "string" && d.name !== "" && !!d.code && !!d.code.value;
  }

  if (doc._deleted) {
    if (live && isProduct(oldDoc)) { requireRole(ADMIN_ROLE); return; }
    if (!live || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a catalog item" });
    requireAccess([oldDoc.team, ADMIN_CHANNEL]);
    return;
  }

  if (isProduct(doc)) {
    if (live && !isProduct(oldDoc)) throw ({ forbidden: "a document cannot become a product" });
    requireRole(ADMIN_ROLE);
    channel("stores");
    channel(ADMIN_CHANNEL);
    return;
  }
  if (live && isProduct(oldDoc)) throw ({ forbidden: "a product cannot become a catalog item" });

  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only catalog items belong in inventory.catalog" });
  if (live && oldDoc.type !== DOC_TYPE) throw ({ forbidden: "a document cannot become a catalog item" });

  if (!doc.team) throw ({ forbidden: "team is required" });
  if (!doc.code || !doc.code.type || !doc.code.value) throw ({ forbidden: "code {type,value} is required" });
  if (!doc.name) throw ({ forbidden: "name is required" });

  var team = live ? oldDoc.team : doc.team;
  if (live && doc.team !== oldDoc.team) { requireRole(ADMIN_ROLE); team = doc.team; }
  requireAccess([team, ADMIN_CHANNEL]);
  channel(team);
  channel(ADMIN_CHANNEL);
}
