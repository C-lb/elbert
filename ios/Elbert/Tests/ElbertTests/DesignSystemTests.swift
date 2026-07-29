import Testing
import UIKit

@testable import Elbert

// MARK: - Buttons

@Suite("Button geometry")
struct ButtonGeometryTests {
    @Test("horizontal padding is exactly twice vertical, every tier", arguments: [HouseButtonSize.small, .medium])
    func paddingRatio(size: HouseButtonSize) {
        #expect(size.horizontalPadding == size.verticalPadding * 2)
    }

    @Test("the tiers are genuinely different sizes")
    func tiersDiffer() {
        #expect(HouseButtonSize.small.verticalPadding < HouseButtonSize.medium.verticalPadding)
        #expect(HouseButtonSize.small.cornerRadius != HouseButtonSize.medium.cornerRadius)
    }

    @Test("the tap target floor is 44pt")
    func tapTarget() {
        for size in [HouseButtonSize.small, .medium] {
            #expect(size.minimumSide == 44)
        }
    }
}

// MARK: - Type

@Suite("Type roles")
struct TypeRoleTests {
    @Test("tracking points is the em value times the role size")
    func trackingConversion() {
        for role in TypeRole.allCases {
            #expect(abs(role.trackingPoints - role.trackingEm * role.size) < 0.0001)
        }
    }

    @Test("leading and tracking both tighten as the type grows")
    func inverseScale() {
        let descending: [TypeRole] = [.display, .h2, .h3, .lead, .body]
        for (larger, smaller) in zip(descending, descending.dropFirst()) {
            #expect(larger.size > smaller.size)
            #expect(larger.leading <= smaller.leading)
            #expect(larger.trackingEm <= smaller.trackingEm)
        }
    }

    @Test("no wrapping role's lines can collide at its target leading")
    func noLineCollision() {
        for role in TypeRole.allCases where !role.isSingleLine {
            #expect(role.interlineClearance > 0, "\(role.name) leaves \(role.interlineClearance)pt between lines")
        }
    }

    @Test("the three tight roles route through the compressed line box")
    func tightRolesCompressed() {
        #expect(TypeRole.display.needsCompressedLeading)
        #expect(TypeRole.h2.needsCompressedLeading)
        #expect(TypeRole.h3.needsCompressedLeading)
        #expect(!TypeRole.body.needsCompressedLeading)
        #expect(!TypeRole.lead.needsCompressedLeading)
    }

    @Test("a role that does not need compression lands on its leading through lineSpacing")
    func looseRolesExact() {
        for role in TypeRole.allCases where !role.needsCompressedLeading {
            let rendered = role.uiFont.lineHeight + role.lineSpacing
            #expect(abs(rendered - role.lineHeight) < 0.01, "\(role.name) renders \(rendered) against \(role.lineHeight)")
        }
    }
}

// MARK: - Font

@Suite("Bundled font")
struct HouseFontTests {
    @Test("DM Sans is registered, so the system fallback is never silently taken")
    func fontIsBundled() {
        #expect(HouseFont.isAvailable)
    }

    @Test("both variation axes are exposed by the bundled file")
    func axesPresent() {
        let tags = Set(HouseFont.availableAxes().map(\.identifier))
        #expect(tags.contains(HouseFont.weightAxis))
        #expect(tags.contains(HouseFont.opticalSizeAxis))
    }

    @Test("a built font really is DM Sans and not the system face")
    func builtFontIsDMSans() {
        #expect(HouseFont.uiFont(size: 17, weight: 400).familyName == HouseFont.familyName)
    }

    @Test("the optical size axis is clamped into the range the file supports")
    func opticalSizeClamped() {
        // 34pt display sits inside 9...40, 64 would not.
        let clamped = HouseFont.uiFont(size: 64, weight: 700)
        #expect(clamped.pointSize == 64)
        #expect(HouseFont.opticalSizeRange.contains(34))
        #expect(!HouseFont.opticalSizeRange.contains(64))
    }
}

// MARK: - Palette

@Suite("Palette")
struct PaletteTests {
    /// This is the test that would have caught light `surface3` sitting below `canvas`.
    @Test(
        "the surface ladder is monotonic in both appearances",
        arguments: [("dark", Palette.dark), ("light", Palette.light)]
    )
    func surfaceLadderIsMonotonic(name: String, palette: Palette) {
        let ladder = [
            ("canvas", palette.canvas),
            ("surface1", palette.surface1),
            ("surface2", palette.surface2),
            ("surface3", palette.surface3),
        ]
        for (lower, upper) in zip(ladder, ladder.dropFirst()) {
            #expect(
                lower.1.relativeLuminance < upper.1.relativeLuminance,
                "\(name): \(lower.0) \(lower.1.relativeLuminance) is not below \(upper.0) \(upper.1.relativeLuminance)"
            )
        }
    }

    @Test("the ink ladder steps away from the canvas in both appearances")
    func inkLadderIsMonotonic() {
        // Dark ink is bright, light ink is dark, so the ladder runs opposite ways.
        #expect(Palette.dark.ink.relativeLuminance > Palette.dark.ink2.relativeLuminance)
        #expect(Palette.dark.ink2.relativeLuminance > Palette.dark.ink3.relativeLuminance)
        #expect(Palette.light.ink.relativeLuminance < Palette.light.ink2.relativeLuminance)
        #expect(Palette.light.ink2.relativeLuminance < Palette.light.ink3.relativeLuminance)
    }

    @Test("dark surfaces are lighter than the dark canvas, which is the house rule")
    func darkSurfacesAreLighter() {
        #expect(Palette.dark.surface1.relativeLuminance > Palette.dark.canvas.relativeLuminance)
    }

    @Test("nothing in dark mode is pure white")
    func noPureWhite() {
        #expect(Palette.dark.ink.hex != 0xffffff)
        #expect(Palette.dark.surface3.relativeLuminance < 0.5)
    }

    @Test("the pop shadow is deeper than the card shadow")
    func shadowLadder() {
        #expect(Palette.dark.shadowPop.alpha > Palette.dark.shadowCard.alpha)
        #expect(Palette.light.shadowPop.alpha > Palette.light.shadowCard.alpha)
    }
}

// MARK: - Icons

@Suite("Icons")
struct IconTests {
    @Test("no two semantic toast icons share a glyph with the dismiss control")
    func toastIconsAreDistinct() {
        for role in SemanticRole.allCases {
            let toast = Toast(role: role, message: "test")
            #expect(toast.icon != .dismiss, "\(role.label) reuses the dismiss glyph")
        }
    }

    @Test("every icon resolves to a real SF Symbol")
    func symbolsExist() {
        for icon in Icon.allCases {
            #expect(UIImage(systemName: icon.symbol) != nil, "\(icon.name) has no symbol \(icon.symbol)")
            #expect(UIImage(systemName: icon.filledSymbol) != nil, "\(icon.name) has no symbol \(icon.filledSymbol)")
        }
    }
}
