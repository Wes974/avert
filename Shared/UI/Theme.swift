import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Midnight palette

/// The "Midnight" direction, kept in sync with `design/AppIcon.svg` (deep indigo
/// ground, gold spark) and with `Assets.xcassets/AccentColor`.
///
/// Every token is a light/dark pair: dark mode is the real Midnight, light mode
/// is its daylight counterpart. Hardcoding one scheme would look broken for half
/// the users, and the banner in `ts/src/banner.ts` already honours
/// `prefers-color-scheme` — the app should not be less careful.
///
/// Names are `avert`-prefixed on purpose: `Color.indigo` already exists in
/// SwiftUI and shadowing it would make every use site ambiguous.
extension Color {
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
        #endif
    }

    static let avertGroundTop = Color(light: 0xF6F5FD, dark: 0x1B1842)
    static let avertGroundBottom = Color(light: 0xFFFFFF, dark: 0x0B0A19)
    static let avertSurface = Color(light: 0xFFFFFF, dark: 0x211E48)
    static let avertSurfaceRaised = Color(light: 0xF1F0FB, dark: 0x2A2757)
    static let avertHairline = Color(light: 0x1B1842, dark: 0xFFFFFF)
    static let avertIndigo = Color(light: 0x4340C4, dark: 0x8F8CF5)
    static let avertGold = Color(light: 0x8A6000, dark: 0xFFCE4A)
    static let avertInk = Color(light: 0x14122B, dark: 0xF4F3FB)
    static let avertInkSoft = Color(light: 0x55506E, dark: 0xB6B2D6)
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

// MARK: - Ground

/// Full-bleed background gradient. Sits behind scrolling content, so the scroll
/// view's own background has to be hidden by the caller.
struct MidnightGround: View {
    var body: some View {
        LinearGradient(
            colors: [.avertGroundTop, .avertGroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Surfaces

struct AvertCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.avertSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.avertHairline.opacity(scheme == .dark ? 0.10 : 0.07), lineWidth: 1)
            )
            // Light mode gets a whisper of elevation; in dark mode a shadow on a
            // near-black ground is invisible noise.
            .shadow(color: scheme == .dark ? .clear : Color.avertIndigo.opacity(0.08), radius: 12, y: 4)
    }
}

/// Small-caps section label — used instead of `List`'s built-in headers so the
/// screens stay on the Midnight ground.
struct AvertSectionLabel: View {
    let text: LocalizedStringKey

    var body: some View {
        // Uppercased by the view, not in the catalog: the key stays the natural
        // spelling, and locales that uppercase differently are handled by SwiftUI.
        Text(text)
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Color.avertInkSoft)
            .padding(.horizontal, 4)
    }
}

/// Icon + title (+ optional detail) row. `tone` colours the glyph only: the
/// text stays high-contrast so meaning never rests on colour alone.
struct AvertRow: View {
    enum Tone { case indigo, gold, neutral }

    let icon: String
    // LocalizedStringKey, not String: these titles come from arrays of data, and
    // a plain String would silently drop out of the String Catalog (found the
    // hard way — `xcodebuild -exportLocalizations` extracted 14 strings out of
    // ~50). Markdown emphasis works too.
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    var tone: Tone = .indigo

    private var glyphColor: Color {
        switch tone {
        case .indigo: Color.avertIndigo
        case .gold: Color.avertGold
        case .neutral: Color.avertInkSoft
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.avertInk)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.avertInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Brand mark

/// A SwiftUI echo of the app icon: the real identity card, its offset ghost
/// duplicate, and the gold spark. Drawn rather than shipped as a PNG so it
/// tracks the palette and stays crisp at any size.
///
/// The proportions below are not invented — they are `design/AppIcon.svg` mapped
/// into a unit square, so the mark on screen and the mark on the Home Screen are
/// the same drawing. An earlier version used wide card shapes here and squares in
/// the icon, and the mismatch was visible side by side.
///
/// Reference geometry, in the SVG's own coordinates: both cards are 40×40 with
/// rx 11, the real one at (20,42), the ghost at (38,26), the spark centred on
/// (74,30) with r 7.6. The glyph spans (20,22.4)…(81.6,82).
struct AvertMark: View {
    var size: CGFloat = 72

    // The glyph's bounding box in SVG units, and its centre.
    private static let unit: CGFloat = 61.6
    private static let centre = CGPoint(x: 50.8, y: 52.2)

    private var card: CGFloat { size * 40 / Self.unit }
    private var radius: CGFloat { size * 11 / Self.unit }
    private var spark: CGFloat { size * 15.2 / Self.unit }

    /// Offset of a shape's centre from the box centre, given its top-left corner
    /// in SVG coordinates.
    private func offset(x: CGFloat, y: CGFloat, side: CGFloat) -> CGSize {
        CGSize(
            width: (x + side / 2 - Self.centre.x) / Self.unit * size,
            height: (y + side / 2 - Self.centre.y) / Self.unit * size
        )
    }

    var body: some View {
        ZStack {
            // Ghost duplicate: dashed outline, up and to the right.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    Color.avertIndigo.opacity(0.55),
                    style: StrokeStyle(
                        lineWidth: size * 3.1 / Self.unit,
                        dash: [size * 6 / Self.unit, size * 6 / Self.unit]
                    )
                )
                .frame(width: card, height: card)
                .offset(offset(x: 38, y: 26, side: 40))

            // The real card: solid, person knocked out.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.avertIndigo, Color.avertIndigo.opacity(0.78)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: card, height: card)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: card * 0.52, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .offset(offset(x: 20, y: 42, side: 40))

            // The spark, on the ghost's top-right corner.
            ZStack {
                Circle().fill(Color.avertGold)
                Image(systemName: "exclamationmark")
                    .font(.system(size: spark * 0.62, weight: .heavy))
                    .foregroundStyle(Color.avertGroundBottom)
            }
            .frame(width: spark, height: spark)
            .offset(offset(x: 74 - 7.6, y: 30 - 7.6, side: 15.2))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Screen scaffold

/// Shared layout for the three tabs: Midnight ground + large title + cards.
struct MidnightScreen<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(Color.avertInkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    content()
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollContentBackground(.hidden)
            .background(MidnightGround())
            .navigationTitle(title)
        }
    }
}
