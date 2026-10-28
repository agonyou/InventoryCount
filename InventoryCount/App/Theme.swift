//  Theme.swift
//  Couchbase Design System tokens, per the Tally design handoff.
//  Cream page, near-black text, red used like a highlighter (one solid-red element per screen).

import SwiftUI

enum CDS {
    // Surfaces & lines
    static let surfaceSunken = Color(hex: 0xFFFAF2)
    static let surface       = Color.white
    static let borderSubtle  = Color(hex: 0xE8DFD2)
    // Text
    static let ink           = Color(hex: 0x1C1917)
    static let inkSecondary  = Color(hex: 0x5A554F)
    // Brand
    static let red           = Color(hex: 0xEC1D24)
    static let red700        = Color(hex: 0xB3161B)
    // Status
    static let success       = Color(hex: 0x2F7D5E)
    static let info          = Color(hex: 0x33556E)
    static let amber         = Color(hex: 0xF0A500)
    static let amberSoft     = Color(hex: 0xFEC578)
    static let amberTint     = Color(hex: 0xFFF4DE)
    // Radii
    static let cardRadius: CGFloat = 16
    static let rowRadius: CGFloat  = 12

    // Type. Figtree display, Open Sans body, JetBrains Mono for counts/locations/identifiers.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name: String
        switch weight {
        case .heavy, .black: name = "Figtree-ExtraBold"
        case .bold:          name = "Figtree-Bold"
        case .semibold:      name = "Figtree-SemiBold"
        default:             name = "Figtree-Regular"
        }
        return .custom(name, size: size)
    }
    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "OpenSans-Bold"
        case .semibold:             name = "OpenSans-SemiBold"
        default:                    name = "OpenSans-Regular"
        }
        return .custom(name, size: size)
    }
    static func mono(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "JetBrainsMono-SemiBold"
        case .medium:                          name = "JetBrainsMono-Medium"
        default:                               name = "JetBrainsMono-Regular"
        }
        return .custom(name, size: size)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

// MARK: - Reusable pieces

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var tint: Color = CDS.surface
    var border: Color = CDS.borderSubtle
    var dashed = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CDS.cardRadius, style: .continuous)
                    .strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : []))
            )
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(CDS.body(12, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(CDS.inkSecondary)
    }
}

struct Badge: View {
    let text: String
    var color: Color = CDS.inkSecondary
    var filled = false
    var mono = false
    var body: some View {
        Text(text)
            .font(mono ? CDS.mono(12, weight: .medium) : CDS.body(12, weight: .semibold))
            .foregroundStyle(filled ? .white : color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(filled ? color : color.opacity(0.10), in: Capsule())
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CDS.body(15, weight: .semibold))
            .foregroundStyle(prominent ? .white : CDS.ink)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .background(prominent ? CDS.red : CDS.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? .clear : CDS.borderSubtle))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = CDS.ink
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(CDS.mono(24, weight: .semibold)).foregroundStyle(tint)
                Text(label).font(CDS.body(12)).foregroundStyle(CDS.inkSecondary)
            }
        }
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(CDS.display(28, weight: .heavy)).tracking(-0.5).foregroundStyle(CDS.ink)
            if let subtitle { Text(subtitle).font(CDS.body(13)).foregroundStyle(CDS.inkSecondary) }
        }
    }
}
