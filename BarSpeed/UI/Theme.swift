import SwiftUI

enum Theme {
    static let bg = Color(red: 0.055, green: 0.06, blue: 0.075)
    static let card = Color(red: 0.11, green: 0.115, blue: 0.135)
    static let cardAlt = Color(red: 0.15, green: 0.155, blue: 0.18)
    static let accent = Color(red: 0.36, green: 0.86, blue: 0.62)
    static let warn = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let danger = Color(red: 0.95, green: 0.36, blue: 0.36)
    static let text = Color.white
    static let sub = Color.white.opacity(0.55)
    static let line = Color.white.opacity(0.08)

    static func zoneColor(_ v: Double) -> Color {
        if v >= 0.75 { return accent }
        if v >= 0.55 { return Color(red: 0.45, green: 0.78, blue: 0.98) }
        if v >= 0.35 { return warn }
        return danger
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

struct Pill: View {
    var text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

struct ProLock: View {
    var text: String = "会员功能"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text(text)
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(0.15))
            .foregroundStyle(Theme.accent)
            .clipShape(Capsule())
        }
    }
}
