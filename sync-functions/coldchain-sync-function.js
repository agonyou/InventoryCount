/**
 * inventory.coldchain: the follow-up on a cold-chain alert, one event per action (type
 * "cold_chain_event"), never edited, so it is the record of who did what and when.
 *   request   store crew asks the truck's driver to confirm the reefer temperature
 *   reply     the truck's driver reports the reading (role "driver", channel "truck-<id>")
 *   escalate  store crew sends the case to the manager
 *   share     store crew shared a written summary (Messages or Mail)
 *   ack       the manager (role "admin") acknowledged
 * Everyone signs their own events (by = their user name). Each event goes to the store, the
 * truck's driver and the manager. Fails closed on anything else.
 */
function (doc, oldDoc) {
  var DOC_TYPE = "cold_chain_event", ADMIN = "admin", DRIVER = "driver";
  var KINDS = ["request", "reply", "escalate", "share", "ack"];
  var live = oldDoc && !oldDoc._deleted;

  if (doc._deleted) {
    if (!live || oldDoc.type !== DOC_TYPE) throw ({ forbidden: "not a cold-chain event" });
    requireRole(ADMIN);
    return;
  }
  if (doc.type !== DOC_TYPE) throw ({ forbidden: "only cold-chain events belong in inventory.coldchain" });
  if (live) throw ({ forbidden: "a logged event cannot change" });

  function text(field) {
    if (typeof doc[field] !== "string" || !doc[field]) throw ({ forbidden: field + " is required" });
    return doc[field];
  }
  var truck = text("truck_id"), store = text("store_id"), by = text("by");
  text("at");
  if (text("case_id").indexOf("coldchain::" + truck + "::") !== 0) {
    throw ({ forbidden: "case_id must start with coldchain::<truck_id>::" });
  }
  if (KINDS.indexOf(doc.kind) < 0) throw ({ forbidden: "kind must be one of " + KINDS.join(", ") });

  requireUser(by);
  if (doc.kind === "reply") {
    requireRole(DRIVER);
    requireAccess(["truck-" + truck]);
    if (typeof doc.reefer_temp_f !== "number" || isNaN(doc.reefer_temp_f)) {
      throw ({ forbidden: "a reply needs reefer_temp_f as a number" });
    }
  } else if (doc.kind === "ack") {
    requireRole(ADMIN);
  } else {
    requireAccess([store, ADMIN]);
    if (doc.kind === "share" && ["messages", "mail", "other"].indexOf(doc.channel) < 0) {
      throw ({ forbidden: "a share needs channel messages, mail or other" });
    }
  }

  channel(store);
  channel("truck-" + truck);
  channel(ADMIN);
}
