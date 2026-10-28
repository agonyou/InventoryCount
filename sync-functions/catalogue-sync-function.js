/**
 * catalogue-sync-function.js — inventory/catalogue, TEAM/GROUP (collaborative).
 * UPC/EAN → product name entries built on device. Same routing as counts:
 * channel(team) + channel("admin"); any team member or admin may write.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "catalogue_item", ADMIN_ROLE = "admin", ADMIN_CHANNEL = "admin";
  if (doc.type == DOC_TYPE || (doc._deleted && oldDoc && oldDoc.type == DOC_TYPE)) {
    var team = oldDoc ? oldDoc.team : doc.team;
    if (doc._deleted) { requireAccess([team, ADMIN_CHANNEL]); return; }
    if (!doc.team)  throw ({ forbidden: "team is required" });
    if (!doc.code || !doc.code.type || !doc.code.value) throw ({ forbidden: "code {type,value} is required" });
    if (!doc.name)  throw ({ forbidden: "name is required" });
    if (oldDoc && !oldDoc._deleted) {
      if (doc.type !== oldDoc.type) throw ({ forbidden: "type cannot be changed" });
      if (doc.team !== oldDoc.team) { requireRole(ADMIN_ROLE); team = doc.team; }
    }
    channel(team);
    channel(ADMIN_CHANNEL);
    requireAccess([team, ADMIN_CHANNEL]);
  }
}
