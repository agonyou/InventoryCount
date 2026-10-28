/**
 * counts-sync-function.js — inventory/counts, TEAM/GROUP (collaborative).
 * Deployment: Capella App Services (no "role:" prefix on requireRole).
 *
 * Every row carries `team`; routed to channel(team) + channel("admin").
 * Any team member creates/updates/deletes the team's rows; manager (admin role) sees all teams.
 * Immutable for non-admins: type, team, captured_by, captured_at. Admin may re-team a row.
 * Static grants (Admin REST API): role admin → ["admin"]; user bob → ["bob","crew-a"].
 */
function (doc, oldDoc) {
  var DOC_TYPE = "count", ADMIN_ROLE = "admin", ADMIN_CHANNEL = "admin";
  if (doc.type == DOC_TYPE || (doc._deleted && oldDoc && oldDoc.type == DOC_TYPE)) {
    var team = oldDoc ? oldDoc.team : doc.team;
    if (doc._deleted) { requireAccess([team, ADMIN_CHANNEL]); return; }

    if (!doc.team)                        throw ({ forbidden: "team is required" });
    if (!doc.item_name)                   throw ({ forbidden: "item_name is required" });
    if (typeof doc.count !== "number")    throw ({ forbidden: "count must be a number" });
    if (!doc.location || typeof doc.location !== "object") throw ({ forbidden: "location object is required" });
    if (!doc.captured_by)                 throw ({ forbidden: "captured_by is required" });
    if (!doc.captured_at)                 throw ({ forbidden: "captured_at is required" });

    if (oldDoc && !oldDoc._deleted) {
      if (doc.type !== oldDoc.type)               throw ({ forbidden: "type cannot be changed" });
      if (doc.captured_by !== oldDoc.captured_by) throw ({ forbidden: "captured_by cannot be changed" });
      if (doc.captured_at !== oldDoc.captured_at) throw ({ forbidden: "captured_at cannot be changed" });
      if (doc.team !== oldDoc.team) { requireRole(ADMIN_ROLE); team = doc.team; }
    }
    channel(team);
    channel(ADMIN_CHANNEL);
    requireAccess([team, ADMIN_CHANNEL]);
  }
}
