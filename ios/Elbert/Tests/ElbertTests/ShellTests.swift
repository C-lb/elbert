import Testing
import UIKit

@testable import Elbert

@Suite("App shell")
struct AppTabTests {
    @Test("the four tabs are in the order the spec fixes")
    func order() {
        #expect(AppTab.allCases == [.home, .decks, .study, .settings])
    }

    /// The fill swap is the *entire* current-state signal in the tab bar: no accent, no underline.
    /// A tab whose icon has no distinct `.fill` variant would therefore have no current state at
    /// all, and it would look like a styling nit rather than the bug it is.
    @Test("every tab icon has a real filled variant to swap to")
    func fillVariantsExist() {
        for tab in AppTab.allCases {
            #expect(tab.icon.hasDistinctFill, "\(tab.title) has no fill variant")
        }
    }

    @Test("both variants of every tab icon are real SF Symbols")
    func symbolsResolve() {
        for tab in AppTab.allCases {
            #expect(UIImage(systemName: tab.icon.symbol) != nil, "\(tab.icon.symbol) is missing")
            #expect(UIImage(systemName: tab.icon.filledSymbol) != nil, "\(tab.icon.filledSymbol) is missing")
        }
    }

    @Test("no two tabs share a glyph")
    func iconsAreDistinct() {
        let symbols = Set(AppTab.allCases.map(\.icon.symbol))
        #expect(symbols.count == AppTab.allCases.count)
    }

    /// Tab captions truncate rather than wrap, so a long one silently loses its tail instead of
    /// opening the row. Keeping them short is the actual fix, and this is what notices.
    @Test("tab captions are short enough to fit a quarter of the narrowest phone")
    func captionsFit() {
        // 320pt is the narrowest iPhone width still supported, so each tab gets 80pt.
        let available: CGFloat = 320 / CGFloat(AppTab.allCases.count)
        let font = TypeRole.labelSmall.uiFont

        for tab in AppTab.allCases {
            let width = (tab.title as NSString).size(withAttributes: [.font: font]).width
            #expect(width <= available, "\(tab.title) needs \(width)pt of \(available)pt")
        }
    }

    @Test("tab titles are sentence case, not shouted")
    func sentenceCase() {
        for tab in AppTab.allCases {
            #expect(tab.title != tab.title.uppercased(), "\(tab.title) is ALL CAPS")
            #expect(tab.title.first?.isUppercase == true)
        }
    }
}
