//  DeliveriesView.swift
//  Deliveries and trucks: what is coming to this store, on which truck, and whether each truck's
//  refrigeration is in range. "In range" uses the tolerance of Nomad's newest approved cold-chain
//  alert (3 °F when there is none), and a truck that alert names is flagged. Read-only.

import SwiftUI

struct DeliveriesView: View {
    @EnvironmentObject private var database: DatabaseManager
    @State private var expanded: Set<String> = []
    private let collapsedRows = 3

    var body: some View {
        let store = AppConfig.currentStoreID
        let coming = store.map { s in database.shipments.filter { $0.storeID == s } } ?? []
        let alert = database.proposals.first { $0.kind == .coldChainAlert }
        let tolerance = alert?.toleranceF ?? 3
        let alerted = Set(alert?.alerts.map(\.truckID) ?? [])
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: "Deliveries and trucks", subtitle: store.map { "Coming to \($0)" })
                Eyebrow(text: "Coming to this store · \(coming.count)")
                if coming.isEmpty {
                    Text(store == nil ? "Set your crew to your store to see its deliveries." : "No deliveries on the way.")
                        .font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                }
                ForEach(coming) { shipment($0, tolerance: tolerance, alerted: alerted) }

                Eyebrow(text: "Fleet · \(database.trucks.count) truck\(database.trucks.count == 1 ? "" : "s") · tolerance \(Int(tolerance)) °F")
                if database.trucks.isEmpty {
                    Text("No trucks synced yet.").font(CDS.body(13)).foregroundStyle(CDS.inkSecondary)
                }
                ForEach(database.trucks.sorted { Self.attention($0, tolerance, alerted) > Self.attention($1, tolerance, alerted) }) {
                    truckRow($0, tolerance: tolerance, alerted: alerted)
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Shipments

    private func shipment(_ s: Shipment, tolerance: Double, alerted: Set<String>) -> some View {
        let truck = database.trucks.first { $0.truckID == s.truckID }
        let all = expanded.contains(s.id) || s.lines.count <= collapsedRows
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox").font(.system(size: 14, weight: .semibold)).foregroundStyle(CDS.ink)
                    Text(s.shipmentID).font(CDS.mono(14, weight: .semibold)).foregroundStyle(CDS.ink)
                    Spacer()
                    Badge(text: s.status.replacingOccurrences(of: "_", with: " ").capitalized, color: CDS.info)
                    if s.priority == "high" { Badge(text: "High priority", color: CDS.red700) }
                }
                Text(Self.eta(s)).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                Text([s.originName.isEmpty ? nil : "From \(s.originName)",
                      s.dockDoor.isEmpty ? nil : "to \(s.dockDoor)",
                      "\(s.totalUnits.formatted()) units",
                      s.pallets > 0 ? "\(s.pallets) pallets" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                // The truck carrying it.
                if let truck {
                    truckRow(truck, tolerance: tolerance, alerted: alerted)
                } else if !s.truckID.isEmpty {
                    Text("Truck \(s.truckID): details not synced yet").font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                }
                ForEach(all ? s.lines : Array(s.lines.prefix(collapsedRows)), id: \.self) { l in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.name).font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.ink)
                            Text("\(l.sku) · \(l.cases) cases · \(l.temperatureClass)").font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
                        }
                        Spacer(minLength: 8)
                        Text("\(l.totalUnits)").font(CDS.mono(14, weight: .medium)).foregroundStyle(CDS.ink)
                    }
                }
                if s.lines.count > collapsedRows {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expanded.contains(s.id) { expanded.remove(s.id) } else { expanded.insert(s.id) }
                        }
                    } label: {
                        Label(all ? "Show fewer" : "Show all \(s.lines.count) lines", systemImage: all ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(PillButtonStyle())
                }
            }
        }
    }

    private static func eta(_ s: Shipment) -> String {
        guard let eta = s.estimatedDelivery else { return "No delivery time yet" }
        let when = eta.formatted(date: .abbreviated, time: .shortened)
        return eta < Date() && s.status != "delivered" ? "Was due \(when)" : "Due \(when)"
    }

    // MARK: - Trucks

    /// 2 = flagged by Nomad, 1 = out of range, 0 = fine or no reefer.
    private static func attention(_ t: Truck, _ tolerance: Double, _ alerted: Set<String>) -> Int {
        if alerted.contains(t.truckID) { return 2 }
        if let d = t.driftF, abs(d) > tolerance { return 1 }
        return 0
    }

    private func truckRow(_ t: Truck, tolerance: Double, alerted: Set<String>) -> some View {
        let level = Self.attention(t, tolerance, alerted)
        let tint: Color = level == 0 ? CDS.success : CDS.amber
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: t.driftF == nil ? "truck.box" : "thermometer.snowflake")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(t.driftF == nil ? CDS.inkSecondary : tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(t.truckID).font(CDS.mono(13, weight: .semibold)).foregroundStyle(CDS.ink)
                    if level == 2 { Badge(text: "Nomad alert", color: CDS.amber) }
                }
                Text(t.name).font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
                Text(Self.reefer(t, tolerance: tolerance)).font(CDS.body(12, weight: .semibold)).foregroundStyle(t.driftF == nil ? CDS.inkSecondary : tint)
                Text([t.status.replacingOccurrences(of: "_", with: " "),
                      t.driverName.isEmpty ? nil : "driver \(t.driverName)",
                      t.routeStops.isEmpty ? nil : "stops \(t.routeStops.joined(separator: ", "))",
                      t.lastPing.map { "last ping \($0.formatted(.relative(presentation: .named)))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(CDS.body(11)).foregroundStyle(CDS.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level == 0 ? CDS.surface : CDS.amberTint, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(level == 0 ? CDS.borderSubtle : CDS.amberSoft))
        .accessibilityElement(children: .combine)
    }

    private static func reefer(_ t: Truck, tolerance: Double) -> String {
        guard let temp = t.reeferTempF, let set = t.setPointF, let d = t.driftF else { return "No refrigeration reading" }
        let state = abs(d) > tolerance ? String(format: "%+.0f °F off", d) : "in range"
        return String(format: "Reefer %.0f °F, set %.0f °F: ", temp, set) + state
    }
}
