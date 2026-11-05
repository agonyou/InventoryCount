//  NomadView.swift
//  Nomad's decisions for this store, as approved in Nomad: the purchase order, transfers from
//  the DC, count-check findings and cold-chain alerts. They arrive through sync seconds after a
//  manager approves them. Read-only: the phone shows them; nothing here changes a count.

import SwiftUI

struct NomadView: View {
    @EnvironmentObject private var database: DatabaseManager
    /// Proposals showing every row: order lines, transfers, findings or truck alerts. The others
    /// show the first few.
    @State private var expanded: Set<String> = []
    /// DEBUG `-tallyNomadExpanded`: every list starts in full. Used for screenshots.
    private let startExpanded: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-tallyNomadExpanded")
        #else
        return false
        #endif
    }()
    private let collapsedRows = 3

    var body: some View {
        let store = AppConfig.currentStoreID
        let decisions = database.nomadDecisions(store: store)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Nomad", subtitle: store.map { "Approved for \($0)" } ?? "Approved in Nomad")
                if decisions.isEmpty {
                    ContentUnavailableCompat(
                        title: "Nothing approved yet", systemImage: "checkmark.seal",
                        message: store == nil
                            ? "Set your crew to your store (like store-001) in Model & sync to see its orders and transfers."
                            : "Purchase orders, transfers and alerts appear here when a manager approves them in Nomad.")
                }
                ForEach(decisions) { p in
                    switch p.kind {
                    case .purchaseOrder: purchaseOrder(p)
                    case .replenishment: replenishment(p, store: store ?? "")
                    case .countCheck: countCheck(p)
                    case .shiftSummary: shiftSummary(p)
                    case .coldChainAlert: coldChain(p)
                    }
                }
            }
            .padding(16)
        }
        .background(CDS.surfaceSunken.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Kinds

    private func purchaseOrder(_ p: ProposalDoc) -> some View {
        let units = p.lines.reduce(0) { $0 + $1.orderQuantity }
        let out = p.lines.filter { $0.onHand == 0 }.count
        return section(p, headline: "\(p.lines.count) lines · \(units.formatted()) units\(out > 0 ? " · \(out) out of stock" : "")") {
            ForEach(shown(p.lines, of: p), id: \.self) { l in
                row(title: l.itemName, detail: "\(l.sku) · on hand \(l.onHand)", trailing: "+\(l.orderQuantity)",
                    tint: l.onHand == 0 ? CDS.red700 : CDS.ink, note: l.reason)
            }
            showAllToggle(p, count: p.lines.count, noun: "lines")
        }
    }

    private func replenishment(_ p: ProposalDoc, store: String) -> some View {
        let mine = p.transfers(to: store)
        let units = mine.reduce(0) { $0 + $1.unitsPerStore }
        return section(p, headline: "\(mine.count) SKU\(mine.count == 1 ? "" : "s") coming to \(store) · \(units.formatted()) units") {
            ForEach(shown(mine, of: p), id: \.self) { t in
                row(title: t.itemName, detail: "\(t.sku) · \(t.priority) priority", trailing: "+\(t.unitsPerStore)",
                    tint: t.priority == "high" ? CDS.red700 : CDS.ink, note: t.reason)
            }
            showAllToggle(p, count: mine.count, noun: "transfers")
        }
    }

    private func countCheck(_ p: ProposalDoc) -> some View {
        let recounts = p.findings.filter { $0.action == "recount" }.count
        let restocks = p.findings.count - recounts
        return section(p, headline: "\(recounts) to recount · \(restocks) to restock") {
            ForEach(shown(p.findings, of: p), id: \.self) { f in
                row(title: f.itemName,
                    detail: "\(f.action == "recount" ? "Recount" : "Restock") · counted \(f.counted), system \(f.systemOnHand)",
                    trailing: f.action == "recount" ? "\(f.difference > 0 ? "+" : "")\(f.difference)" : "+\(f.orderQuantity)",
                    tint: f.action == "recount" ? CDS.amber : CDS.ink, note: f.reason)
            }
            showAllToggle(p, count: p.findings.count, noun: "findings")
        }
    }

    private func shiftSummary(_ p: ProposalDoc) -> some View {
        section(p, headline: "End of shift") {
            ForEach(p.highlights, id: \.self) { h in
                Label(h, systemImage: "arrow.right.circle").font(CDS.body(13, weight: .semibold)).foregroundStyle(CDS.ink)
            }
        }
    }

    private func coldChain(_ p: ProposalDoc) -> some View {
        let tolerance = p.toleranceF.map { " · tolerance \(Int($0)) °F" } ?? ""
        return section(p, headline: "\(p.alerts.count) truck\(p.alerts.count == 1 ? "" : "s") off set point\(tolerance)") {
            ForEach(shown(p.alerts, of: p), id: \.self) { a in
                row(title: a.truckID, detail: a.severity.capitalized, trailing: String(format: "%+.0f°F", a.driftF),
                    tint: a.severity == "critical" ? CDS.red700 : CDS.amber, note: a.action)
            }
            showAllToggle(p, count: p.alerts.count, noun: "alerts")
        }
    }

    // MARK: - Pieces

    private func showsAll(_ p: ProposalDoc) -> Bool { expanded.contains(p.id) != startExpanded }

    /// The rows to show: all of them when expanded or short, else the first few.
    private func shown<Row>(_ rows: [Row], of p: ProposalDoc) -> [Row] {
        showsAll(p) || rows.count <= collapsedRows ? rows : Array(rows.prefix(collapsedRows))
    }

    /// "Show all 60 lines" / "Show fewer", only when there is more than the first few.
    @ViewBuilder
    private func showAllToggle(_ p: ProposalDoc, count: Int, noun: String) -> some View {
        if count > collapsedRows {
            let all = showsAll(p)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded.contains(p.id) { expanded.remove(p.id) } else { expanded.insert(p.id) }
                }
            } label: {
                Label(all ? "Show fewer" : "Show all \(count) \(noun)", systemImage: all ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(PillButtonStyle())
            .accessibilityHint(all ? "Shows the first \(collapsedRows) \(noun)" : "Shows all \(count) \(noun)")
        }
    }

    private func section<Rows: View>(_ p: ProposalDoc, headline: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: p.systemImage).font(.system(size: 14, weight: .semibold)).foregroundStyle(CDS.ink)
                Eyebrow(text: "\(p.title) · \(p.day)")
                Spacer()
                Badge(text: "Approved", color: CDS.success)
            }
            Text(headline).font(CDS.body(15, weight: .semibold)).foregroundStyle(CDS.ink)
            if !p.summary.isEmpty { Text(p.summary).font(CDS.body(13)).foregroundStyle(CDS.inkSecondary) }
            rows()
        }
    }

    private func row(title: String, detail: String, trailing: String, tint: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(CDS.body(14, weight: .semibold)).foregroundStyle(CDS.ink)
                Spacer(minLength: 8)
                Text(trailing).font(CDS.mono(14, weight: .medium)).foregroundStyle(tint)
            }
            Text(detail).font(CDS.mono(11)).foregroundStyle(CDS.inkSecondary)
            if !note.isEmpty { Text(note).font(CDS.body(12)).foregroundStyle(CDS.inkSecondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CDS.surface, in: RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CDS.rowRadius, style: .continuous).strokeBorder(CDS.borderSubtle))
    }
}

/// Capture-screen strip: "Nomad · PO 60 lines · 6 transfers · 1 truck alert". Hidden when there
/// is nothing approved for this store.
struct NomadStrip: View {
    @EnvironmentObject private var database: DatabaseManager
    @Binding var path: NavigationPath

    var body: some View {
        let store = AppConfig.currentStoreID
        let decisions = database.nomadDecisions(store: store)
        if !decisions.isEmpty {
            Button { path.append(Route.nomad) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
                    Text("Nomad").font(CDS.body(14, weight: .semibold))
                    Text(Self.digest(decisions, store: store)).font(CDS.mono(12)).foregroundStyle(CDS.inkSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if decisions.contains(where: { $0.kind == .coldChainAlert }) {
                        Image(systemName: "thermometer.snowflake").font(.system(size: 12, weight: .semibold)).foregroundStyle(CDS.amber)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CDS.inkSecondary)
                }
                .foregroundStyle(CDS.ink)
                .padding(.horizontal, 14).frame(height: 40)
                .background(CDS.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(CDS.borderSubtle))
            }
            .accessibilityLabel("Nomad decisions: \(Self.digest(decisions, store: store))")
            .padding(.horizontal, 16).padding(.bottom, 4)
        }
    }

    static func digest(_ decisions: [ProposalDoc], store: String?) -> String {
        decisions.map { p -> String in
            switch p.kind {
            case .purchaseOrder: return "PO \(p.lines.count) lines"
            case .replenishment: return "\(store.map { p.transfers(to: $0).count } ?? 0) transfers"
            case .countCheck: return "\(p.findings.count) to check"
            case .shiftSummary: return "shift summary"
            case .coldChainAlert: return "\(p.alerts.count) truck alert\(p.alerts.count == 1 ? "" : "s")"
            }
        }
        .joined(separator: " · ")
    }
}
