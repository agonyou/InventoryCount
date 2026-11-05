//  RootView.swift

import SwiftUI
import CouchbaseLiteSwift

enum Route: Hashable { case sheet, summary, modelSync, locationPicker, nomad, snapshot, deliveries, bay, lookup, scanProduct, entry(CountEntry) }

struct RootView: View {
    @State private var path = NavigationPath()
    @EnvironmentObject private var database: DatabaseManager
    @EnvironmentObject private var session: CaptureSession

    var body: some View {
        NavigationStack(path: $path) {
            CaptureScreen(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .sheet: SheetView(path: $path)
                    case .summary: SummaryView()
                    case .modelSync: ModelSyncView()
                    case .locationPicker: LocationPickerView()
                    case .nomad: NomadView()
                    case .snapshot: StoreSnapshotView(path: $path)
                    case .deliveries: DeliveriesView()
                    case .bay: BayView(path: $path)
                    case .lookup: ProductLookupView()
                    case .scanProduct: ScanProductView()
                    case .entry(let e): EntryDetailView(entry: e)
                    }
                }
        }
        .background(CDS.surfaceSunken)
        .onAppear { applyDebugLaunchArguments() }
    }

    /// DEBUG only: `-tallyRoute sheet|summary|modelSync|location` opens a screen directly;
    /// `-tallyDemo` seeds local rows when the sheet is empty, and today's three approved Nomad
    /// proposals (shortened) when there are none; local only, never pushed. Add `-tally.team store-001`
    /// to see them as store-001's crew. Used for screenshots.
    private func applyDebugLaunchArguments() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        try? database.open()
        if args.contains("-tallyDemo"), database.localEntryCount == 0 {
            let loc = ItemLocation(site: "Location X", rack: "A", shelf: "S2", bin: "B15")
            let rows = [
                CountEntry(itemName: "Blue storage bin", count: 30, attributes: "Medium · rectangular · blue", annotation: "Three shelves of 30 bins; two bins cracked", location: loc, source: .voice, confidence: 92),
                CountEntry(itemName: "Cardboard carton", count: 12, countIsEstimate: true, attributes: "Large · brown", annotation: "Top shelf, partly hidden", location: loc, source: .photo, confidence: 48, needsReview: true),
                CountEntry(itemName: "Blue storage bin", count: 28, attributes: "Medium · rectangular · blue", annotation: "", location: loc, source: .text, confidence: 90, capturedBy: "peer-b2", capturedByName: "Crew iPhone 2"),
            ]
            try? database.saveAll(rows)
            session.sessionRows = rows
        }
        if args.contains("-tallyDemo"), database.proposals.isEmpty, (database.proposalsColl?.count ?? 0) == 0 {
            seedDemoProposals()
        }
        // Seed once: the live queries fill in after launch, so check the stored document itself.
        if args.contains("-tallyDemo"), (try? database.counts?.document(id: "count::store-001::SKU-GRC-DAIR-1027")) == nil {
            seedDemoStock()
        }
        if args.contains("-tallyDemo"), database.trucks.isEmpty, (database.trucksColl?.count ?? 0) == 0 {
            seedDemoDeliveries()
        }
        if args.contains("-tallyDemo"), (try? database.catalogColl?.document(id: "catalogue::upc::010000100280")) == nil {
            seedDemoProducts()
        }
        if let i = args.firstIndex(of: "-tallyRoute"), i + 1 < args.count {
            switch args[i + 1] {
            case "sheet": path.append(Route.sheet)
            case "summary": path.append(Route.sheet); path.append(Route.summary)
            case "modelSync": path.append(Route.modelSync)
            case "location": path.append(Route.locationPicker)
            case "nomad": path.append(Route.nomad)
            case "snapshot": path.append(Route.snapshot)
            case "deliveries": path.append(Route.deliveries)
            case "bay": path.append(Route.bay)
            case "lookup": path.append(Route.lookup)
            case "scan": path.append(Route.scanProduct)
            default: break
            }
        }
        #endif
    }

    #if DEBUG
    /// Store products as far as they were read from the demo cluster on 2026-11-05 and 11-03:
    /// Imported Milk in full, the single Clorox wipes with its UPC, and the rest with sku and name
    /// only (their brand, price and barcode were not read, so they are left out).
    private func seedDemoProducts() {
        var products: [(String, [String: Any])] = [
            ("catalogue::upc::010000100280", ["sku": "SKU-GRC-DAIR-1027", "name": "Imported Milk", "brand": "BudgetBest",
                "category": "Dairy", "department": "Grocery", "unit": "quart", "unit_price": 5.18,
                "supplier": ["name": "Valley Fresh Dairy Farms", "lead_time_days": 2], "code": ["type": "upc", "value": "010000100280"]]),
            ("catalogue::upc::020000100814", ["sku": "SKU-DGM-CLN-2000", "name": "Clorox Disinfecting Wipes Fresh Scent 75ct",
                "category": "Household & Cleaning", "code": ["type": "upc", "value": "020000100814"]]),
        ]
        let named: [(String, String, String)] = [
            ("SKU-DGM-CLN-2003", "Gain Original Liquid Laundry Detergent 40oz", "Household & Cleaning"),
            ("SKU-DGM-CLN-2006", "Glad Drawstring Trash Bags 13 Gallon 20ct", "Household & Cleaning"),
            ("SKU-DGM-PET-2026", "Purina Dog Chow Complete Adult Dry Dog Food 4.4 lb", "Pet Supplies"),
            ("SKU-GRC-BEV-00705", "Coca-Cola 100% Orange Juice with Calcium (Pack 5)", ""),
            ("SKU-GRC-DAIR-00210", "Sargento Mild Cheddar Shredded (Pack 9)", ""),
            ("SKU-GRC-DAIR-00070", "Sargento Cage Free Brown Eggs (Pack 3)", ""),
            ("SKU-GRC-DAIR-00415", "Kraft Greek Yogurt Strawberry (Pack 17)", ""),
            ("SKU-GRC-PER-1051", "Chef Shampoo", ""),
        ]
        for (sku, name, category) in named {
            products.append(("demo-product::\(sku)", ["sku": sku, "name": name, "category": category]))
        }
        for (id, data) in products { try? database.catalogColl?.save(document: MutableDocument(id: id, data: data)) }
    }

    /// Shipment SHP-OUT-8003 to store-001 and truck TRK-101, as read from the demo cluster on
    /// 2026-11-05. TRK-102, which carries the shipment, was not read, so it is left out: the screen
    /// says its details have not synced.
    private func seedDemoDeliveries() {
        let shipment: [String: Any] = [
            "type": "shipment", "shipment_id": "SHP-OUT-8003", "status": "loading", "priority": "high",
            "direction": "outbound", "shipment_type": "store_replenishment", "temperature_class": "ambient",
            "assigned_truck": "truck::TRK-102", "carrier": "Celios-Nomad Private Fleet",
            "destination": ["city": "Springfield, IL", "dock_door": "Loading Bay 1", "name": "Celios Downtown Supermarket",
                            "site": "celios-downtown", "store_id": "store-001"],
            "origin": ["city": "Springfield, IL", "dock_door": "Door 14", "facility_name": "Celios-Nomad Midwest Distribution Center", "site": "dc-01"],
            "manifest": [
                ["sku": "SKU-DGM-CLN-2000", "name": "Clorox Disinfecting Wipes Fresh Scent 75ct", "category": "Household & Cleaning",
                 "cases": 80, "units_per_case": 12, "total_units": 960, "temperature_class": "ambient"],
                ["sku": "SKU-DGM-CLN-2003", "name": "Gain Original Liquid Laundry Detergent 40oz", "category": "Household & Cleaning",
                 "cases": 60, "units_per_case": 8, "total_units": 480, "temperature_class": "ambient"],
                ["sku": "SKU-DGM-CLN-2006", "name": "Glad Drawstring Trash Bags 13 Gallon 20ct", "category": "Household & Cleaning",
                 "cases": 50, "units_per_case": 12, "total_units": 600, "temperature_class": "ambient"],
                ["sku": "SKU-DGM-PET-2026", "name": "Purina Dog Chow Complete Adult Dry Dog Food 4.4 lb", "category": "Pet Supplies",
                 "cases": 50, "units_per_case": 6, "total_units": 300, "temperature_class": "ambient"],
            ],
            "metrics": ["pallets": 22, "total_cases": 240, "total_lines": 4, "total_units": 2880, "total_weight_lbs": 38400],
            "schedule": ["created_at": "2026-11-02T18:40:00.293Z", "picked_at": "2026-11-02T19:40:00.293Z",
                         "estimated_delivery": "2026-11-02T22:40:00.293Z"],
        ]
        let truck: [String: Any] = [
            "type": "truck", "truck_id": "TRK-101", "name": "Freightliner Cascadia #101 (Multi-Temp Reefer)",
            "current_status": "en_route", "temperature_zone": "multi_temp", "trailer_type": "reefer",
            "carrier": "Celios-Nomad Private Fleet",
            "driver": ["driver_id": "DRV-501", "name": "Marcus Vance"],
            "current_route": ["route_id": "RT-CENTRAL-02", "origin": "dc-01", "stops": ["store-002", "store-003"]],
            "telematics": ["reefer_temp_f": 39, "set_point_f": 34, "speed_mph": 58, "last_ping": "2026-11-02T20:40:00.293Z"],
        ]
        try? database.shipmentsColl?.save(document: MutableDocument(id: "shipment::out::SHP-OUT-8003", data: shipment))
        try? database.trucksColl?.save(document: MutableDocument(id: "truck::TRK-101", data: truck))
    }

    /// Store-001 stock records as read from the demo cluster on 2026-11-05 (the store system's
    /// figures). The shape follows count::<store>::<sku>; Imported Milk's 30-day sales were not
    /// read and are left out.
    private func seedDemoStock() {
        func loc(_ site: String, _ rack: String, _ shelf: String, _ bin: String) -> [String: Any] {
            ["site": site, "rack": rack, "shelf": shelf, "bin": bin]
        }
        let rows: [[String: Any]] = [
            ["sku": "SKU-GRC-BEV-00705", "item_name": "Coca-Cola 100% Orange Juice with Calcium (Pack 5)", "stock_quantity": 19, "reorder_level": 49,
             "stock_status": "low_stock", "sales_volume_30d": 196, "location": loc("generalstore-01", "Aisle 3", "Shelf 1", "Bin 1")],
            ["sku": "SKU-GRC-DAIR-00210", "item_name": "Sargento Mild Cheddar Shredded (Pack 9)", "stock_quantity": 19, "reorder_level": 49,
             "stock_status": "low_stock", "sales_volume_30d": 196, "location": loc("generalstore-01", "Aisle 3", "Shelf 2", "Bin 2")],
            ["sku": "SKU-GRC-DAIR-00070", "item_name": "Sargento Cage Free Brown Eggs (Pack 3)", "stock_quantity": 0, "reorder_level": 49,
             "stock_status": "out_of_stock", "sales_volume_30d": 196, "location": loc("generalstore-01", "Aisle 7", "Shelf 2", "Bin 2")],
            ["sku": "SKU-GRC-DAIR-00415", "item_name": "Kraft Greek Yogurt Strawberry (Pack 17)", "stock_quantity": 0, "reorder_level": 44,
             "stock_status": "out_of_stock", "sales_volume_30d": 176, "location": loc("generalstore-01", "Aisle 1", "Shelf 1", "Bin 1")],
            ["sku": "SKU-GRC-PER-1051", "item_name": "Chef Shampoo", "stock_quantity": 411, "reorder_level": 147,
             "stock_status": "overstocked", "sales_volume_30d": 529, "location": loc("celios-downtown", "Aisle 4", "Shelf 1", "Bin 4")],
            ["sku": "SKU-GRC-DAIR-1027", "item_name": "Imported Milk", "stock_quantity": 31, "reorder_level": 15,
             "stock_status": "in_stock", "location": loc("celios-downtown", "Aisle 4", "Shelf 1", "Bin 4")],
        ]
        for r in rows {
            var data = r
            data["store_id"] = "store-001"; data["store_name"] = "Celios Downtown Supermarket"; data["store_type"] = "GeneralStore"
            let sku = r["sku"] as? String ?? ""
            try? database.counts?.save(document: MutableDocument(id: "count::store-001::\(sku)", data: data))
        }
        // Made-up crew counts at those bays: one off the system (milk, 28 against 31), one matching
        // it (orange juice, 19), and one said loosely (cheddar), for Scan a bay and Count and compare.
        let counted = [
            CountEntry(team: "store-001", itemName: "Imported Milk", count: 28,
                       location: ItemLocation(site: "celios-downtown", rack: "Aisle 4", shelf: "Shelf 1", bin: "Bin 4"),
                       source: .voice, storeID: "store-001", sku: "SKU-GRC-DAIR-1027"),
            CountEntry(team: "store-001", itemName: "Coca-Cola 100% Orange Juice with Calcium (Pack 5)", count: 19,
                       location: ItemLocation(site: "generalstore-01", rack: "Aisle 3", shelf: "Shelf 1", bin: "Bin 1"),
                       source: .code, storeID: "store-001", sku: "SKU-GRC-BEV-00705"),
            // Said loosely, so no sku: matched to the closest store item on screen only.
            CountEntry(team: "store-001", itemName: "shredded cheddar", count: 15,
                       location: ItemLocation(site: "generalstore-01", rack: "Aisle 3", shelf: "Shelf 2", bin: "Bin 2"),
                       source: .voice, storeID: "store-001"),
        ]
        try? database.saveAll(counted)
        session.sessionRows.insert(contentsOf: counted, at: 0)
    }

    /// Shortened copies of the three proposals approved in Nomad on 2026-11-05. The purchase order's
    /// last three lines are store-001 items from that day's low and out-of-stock samples, with
    /// illustrative quantities, so the order is long enough to show the "Show all" toggle.
    private func seedDemoProposals() {
        let day = "2026-11-05"
        let docs: [(String, [String: Any])] = [
            ("po::store-001::\(day)", [
                "type": "proposal", "kind": "purchase_order", "store_id": "store-001", "day": day, "status": "approved",
                "summary": "Draft purchase order for store-001: 60 lines totaling 5,080 units, including 11 items that are currently out of stock.",
                "lines": [
                    ["sku": "SKU-GRC-DAIR-00595", "item_name": "Kraft Cage Free Brown Eggs (Pack 24)", "on_hand": 19, "order_quantity": 98,
                     "reason": "Low stock (19, level 49). Standard 98 covers about 15 days at 196/30d."],
                    ["sku": "SKU-GRC-DAIR-00070", "item_name": "Sargento Cage Free Brown Eggs (Pack 3)", "on_hand": 0, "order_quantity": 98,
                     "reason": "Out of stock (level 49). Standard 98 covers about 15 days at 196/30d."],
                    ["sku": "SKU-GRC-BEV-00705", "item_name": "Coca-Cola 100% Orange Juice with Calcium (Pack 5)", "on_hand": 19, "order_quantity": 98,
                     "reason": "Low stock (19, level 49). Standard 98 covers about 15 days at 196/30d."],
                    ["sku": "SKU-GRC-DAIR-00210", "item_name": "Sargento Mild Cheddar Shredded (Pack 9)", "on_hand": 19, "order_quantity": 98,
                     "reason": "Low stock (19, level 49). Standard 98 covers about 15 days at 196/30d."],
                    ["sku": "SKU-GRC-DAIR-00415", "item_name": "Kraft Greek Yogurt Strawberry (Pack 17)", "on_hand": 0, "order_quantity": 88,
                     "reason": "Out of stock (level 44). Standard 88 covers about 15 days at 176/30d."],
                ]]),
            ("replenish::\(day)", [
                "type": "proposal", "kind": "replenishment", "day": day, "status": "approved",
                "summary": "25 beverage SKUs were out of stock in 3 stores each. The plan sends 48 units to each out-of-stock store, well within every DC reserve.",
                "transfers": [
                    ["sku": "SKU-GRC-BEV-00622", "item_name": "Tropicana Natural Spring Water 24pk", "to_store_ids": ["store-001", "store-024", "store-047"],
                     "units_per_store": 48, "dc_reserve_units": 3888, "priority": "low", "reason": "Out in 3 stores; 144 units against a DC reserve of 3,888."],
                    ["sku": "SKU-GRC-BEV-00645", "item_name": "Gatorade Zero Sugar Energy Drink (Pack 2)", "to_store_ids": ["store-001", "store-024", "store-047"],
                     "units_per_store": 48, "dc_reserve_units": 3456, "priority": "medium", "reason": "Out in 3 stores and low in 5; chain shelf stock is lower at 1,525."],
                    ["sku": "SKU-GRC-BEV-00668", "item_name": "Lipton Energy Drink Original (Pack 3)", "to_store_ids": ["store-001", "store-024", "store-047"],
                     "units_per_store": 48, "dc_reserve_units": 5640, "priority": "low", "reason": "Out in 3 stores; 144 units planned against a DC reserve of 5,640; chain shelf stock is 2,925."],
                    ["sku": "SKU-GRC-BEV-00691", "item_name": "Dr Pepper Cool Blue Sports Drink (Pack 4)", "to_store_ids": ["store-001", "store-024", "store-047"],
                     "units_per_store": 48, "dc_reserve_units": 3360, "priority": "low", "reason": "Out in 3 stores; 144 units planned against a DC reserve of 3,360; chain shelf stock is 2,198."],
                    ["sku": "SKU-GRC-BEV-00714", "item_name": "Starbucks Fruit Punch Thirst Quencher (Pack 5)", "to_store_ids": ["store-001", "store-024", "store-047"],
                     "units_per_store": 48, "dc_reserve_units": 3036, "priority": "medium", "reason": "Out in 3 stores; chain shelf stock is lower at 1,479. 144 units planned against a reserve of 3,036."],
                    ["sku": "SKU-GRC-BEV-00737", "item_name": "Coca-Cola Ginger Ale (Pack 6)", "to_store_ids": ["store-001", "store-024", "store-047"],
                     "units_per_store": 48, "dc_reserve_units": 4968, "priority": "low", "reason": "Out in 3 stores; 144 units planned against a DC reserve of 4,968; chain shelf stock is 3,001."],
                    ["sku": "SKU-GRC-BEV-00619", "item_name": "Folgers Cool Blue Sports Drink", "to_store_ids": ["store-004", "store-027", "store-050"],
                     "units_per_store": 48, "dc_reserve_units": 4356, "priority": "low", "reason": "Out in 3 stores."],
                ],
                "needs_supplier_order": [String]()]),
            // Illustrative: Count check has not run on phone counts yet. Real store-001 SKUs and
            // system on-hand from 2026-11-05; the counted numbers are made up.
            ("countcheck::store-001::\(day)", [
                "type": "proposal", "kind": "count_check", "store_id": "store-001", "day": day, "window_days": 1, "status": "approved",
                "summary": "Illustrative check: two shelf counts differ from the system enough to recount, and two short items need a restock.",
                "findings": [
                    ["sku": "SKU-GRC-BEV-00705", "item_name": "Coca-Cola 100% Orange Juice with Calcium (Pack 5)", "action": "recount",
                     "counted": 7, "system_on_hand": 19, "difference": -12, "order_quantity": 0, "priority": "high",
                     "reason": "12 fewer on the shelf than the system on a fast seller (196 in 30 days)."],
                    ["sku": "SKU-GRC-DAIR-00210", "item_name": "Sargento Mild Cheddar Shredded (Pack 9)", "action": "recount",
                     "counted": 31, "system_on_hand": 19, "difference": 12, "order_quantity": 0, "priority": "medium",
                     "reason": "12 more on the shelf than the system: check for a misplaced case."],
                    ["sku": "SKU-GRC-DAIR-00070", "item_name": "Sargento Cage Free Brown Eggs (Pack 3)", "action": "restock",
                     "counted": 0, "system_on_hand": 0, "difference": 0, "order_quantity": 98, "priority": "high",
                     "reason": "Shelf is empty, matching the system; order the standard 98."],
                    ["sku": "SKU-GRC-DAIR-00415", "item_name": "Kraft Greek Yogurt Strawberry (Pack 17)", "action": "restock",
                     "counted": 0, "system_on_hand": 0, "difference": 0, "order_quantity": 88, "priority": "high",
                     "reason": "Shelf is empty, matching the system; order 88."],
                ]]),
            ("coldchain::\(day)", [
                "type": "proposal", "kind": "cold_chain_alert", "day": day, "tolerance_f": 3, "status": "approved",
                "summary": "TRK-101 is running 5 F warm at 39 F against a 34 F set point: a warning, under twice the 3 F tolerance.",
                "alerts": [["truck_id": "TRK-101", "drift_f": 5, "severity": "warning",
                            "action": "Call driver Marcus Vance to confirm the truck's status (last ping three days old) and inspect the load before store-002 receives it."]]]),
        ]
        for (id, data) in docs { try? database.proposalsColl?.save(document: MutableDocument(id: id, data: data)) }
    }
    #endif
}

struct ContentUnavailableCompat: View {
    let title: String
    let systemImage: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 40, weight: .light)).foregroundStyle(CDS.inkSecondary)
            Text(title).font(CDS.display(18, weight: .bold)).foregroundStyle(CDS.ink)
            Text(message).font(CDS.body(13)).foregroundStyle(CDS.inkSecondary).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

/// Peer / cloud sync state badge.
struct SyncBadge: View {
    @EnvironmentObject private var multipeer: MultipeerSyncManager
    @EnvironmentObject private var replication: ReplicationManager
    var body: some View {
        let peers = multipeer.peers.filter(\.online).count
        if multipeer.isEnabled {
            Badge(text: peers == 0 ? "No peers" : (multipeer.peers.contains { $0.syncing } ? "Syncing · \(peers)" : "Synced · \(peers)"),
                  color: peers == 0 ? CDS.inkSecondary : CDS.success)
        } else if replication.syncStatus != .idle || replication.lastActivityAt != nil {
            Badge(text: replication.syncStatus.label, color: replication.syncStatus.isError ? CDS.red700 : CDS.info)
        } else {
            Badge(text: "Local only", color: CDS.inkSecondary)
        }
    }
}

/// Location chip (Rack · Shelf · Bin) — tap to change.
struct LocationChip: View {
    @EnvironmentObject private var session: CaptureSession
    @Binding var path: NavigationPath
    var body: some View {
        Button { path.append(Route.locationPicker) } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin").font(.system(size: 12, weight: .semibold))
                Text(session.location.chip).font(CDS.mono(13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(CDS.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(CDS.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(CDS.borderSubtle))
        }
        .accessibilityLabel("Location \(session.location.display). Tap to change")
    }
}
