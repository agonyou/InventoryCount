//  Delivery.swift
//  Deliveries and the fleet, from the store system: inventory.shipments (routed to the destination
//  store's crew) and inventory.trucks (everyone). Read-only on the phone.

import Foundation

struct Shipment: Identifiable, Hashable {
    struct Line: Hashable { var sku, name, temperatureClass: String; var cases, totalUnits: Int }

    var id: String
    var shipmentID: String
    var status: String
    var priority: String
    var temperatureClass: String
    var truckKey: String          // "truck::TRK-102"
    var storeID: String
    var destinationName: String
    var dockDoor: String
    var originName: String
    var estimatedDelivery: Date?
    var departedAt: Date?
    var totalUnits: Int
    var pallets: Int
    var lines: [Line]

    var truckID: String { truckKey.hasPrefix("truck::") ? String(truckKey.dropFirst(7)) : truckKey }

    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == "shipment" else { return nil }
        let destination = d["destination"] as? [String: Any] ?? [:]
        guard let store = destination["store_id"] as? String, !store.isEmpty else { return nil }
        self.id = id; storeID = store
        shipmentID = d["shipment_id"] as? String ?? id
        status = d["status"] as? String ?? ""
        priority = d["priority"] as? String ?? ""
        temperatureClass = d["temperature_class"] as? String ?? ""
        truckKey = d["assigned_truck"] as? String ?? ""
        destinationName = destination["name"] as? String ?? store
        dockDoor = destination["dock_door"] as? String ?? ""
        let origin = d["origin"] as? [String: Any] ?? [:]
        originName = origin["facility_name"] as? String ?? origin["site"] as? String ?? ""
        let schedule = d["schedule"] as? [String: Any] ?? [:]
        estimatedDelivery = (schedule["estimated_delivery"] as? String).flatMap(ISO8601DateFormatter.cblDate)
        departedAt = (schedule["departed_at"] as? String).flatMap(ISO8601DateFormatter.cblDate)
        let metrics = d["metrics"] as? [String: Any] ?? [:]
        totalUnits = (metrics["total_units"] as? NSNumber)?.intValue ?? 0
        pallets = (metrics["pallets"] as? NSNumber)?.intValue ?? 0
        lines = (d["manifest"] as? [Any] ?? []).compactMap { raw in
            guard let m = raw as? [String: Any] else { return nil }
            return Line(sku: m["sku"] as? String ?? "", name: m["name"] as? String ?? "",
                        temperatureClass: m["temperature_class"] as? String ?? "",
                        cases: (m["cases"] as? NSNumber)?.intValue ?? 0,
                        totalUnits: (m["total_units"] as? NSNumber)?.intValue ?? 0)
        }
    }
}

struct Truck: Identifiable, Hashable {
    var id: String
    var truckID: String
    var name: String
    var status: String
    var trailerType: String
    var temperatureZone: String
    var driverName: String
    var routeStops: [String]
    var reeferTempF: Double?
    var setPointF: Double?
    var speedMph: Double?
    var lastPing: Date?

    init?(id: String, dictionary d: [String: Any]) {
        guard (d["type"] as? String) == "truck", let truckID = d["truck_id"] as? String, !truckID.isEmpty else { return nil }
        self.id = id; self.truckID = truckID
        name = d["name"] as? String ?? truckID
        status = d["current_status"] as? String ?? ""
        trailerType = d["trailer_type"] as? String ?? ""
        temperatureZone = d["temperature_zone"] as? String ?? ""
        driverName = (d["driver"] as? [String: Any])?["name"] as? String ?? ""
        routeStops = ((d["current_route"] as? [String: Any])?["stops"] as? [Any] ?? []).compactMap { $0 as? String }
        let t = d["telematics"] as? [String: Any] ?? [:]
        reeferTempF = (t["reefer_temp_f"] as? NSNumber)?.doubleValue
        setPointF = (t["set_point_f"] as? NSNumber)?.doubleValue
        speedMph = (t["speed_mph"] as? NSNumber)?.doubleValue
        lastPing = (t["last_ping"] as? String).flatMap(ISO8601DateFormatter.cblDate)
    }

    /// Degrees off the set point, when the truck has a reefer reading.
    var driftF: Double? {
        guard let reeferTempF, let setPointF else { return nil }
        return reeferTempF - setPointF
    }
}
