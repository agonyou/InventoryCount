//  RootView.swift

import SwiftUI

enum Route: Hashable { case sheet, summary, modelSync, locationPicker, entry(CountEntry) }

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
                    case .entry(let e): EntryDetailView(entry: e)
                    }
                }
        }
        .background(CDS.surfaceSunken)
        .onAppear { applyDebugLaunchArguments() }
    }

    /// DEBUG only: `-tallyRoute sheet|summary|modelSync|location` opens a screen directly;
    /// `-tallyDemo` seeds two local rows when the sheet is empty. Used for screenshots.
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
        if let i = args.firstIndex(of: "-tallyRoute"), i + 1 < args.count {
            switch args[i + 1] {
            case "sheet": path.append(Route.sheet)
            case "summary": path.append(Route.sheet); path.append(Route.summary)
            case "modelSync": path.append(Route.modelSync)
            case "location": path.append(Route.locationPicker)
            default: break
            }
        }
        #endif
    }
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
