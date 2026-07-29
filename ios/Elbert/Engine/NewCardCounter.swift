import Foundation

/// How many new cards each deck has introduced today.
///
/// Lives in `UserDefaults`, deliberately not in CloudKit (spec section 5). New-cards-introduced-
/// today is a per-device notion: syncing it would mean starting a session on iPad silently
/// spending the iPhone's allowance. Per-device drift is both simpler and closer to what a person
/// expects from "20 new a day".
struct NewCardCounter {
    private static let prefix = "newIntroduced:"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `yyyy-MM-dd` in the device's own calendar and time zone, matching the web app's `dayKey`.
    ///
    /// A fixed `en_US_POSIX` locale, because a locale with a non-Gregorian calendar would produce
    /// a key that does not sort or compare like a date, and this string is used as an identity.
    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func key(deckID: UUID, on date: Date) -> String {
        "\(prefix)\(deckID.uuidString):\(dayKey(date))"
    }

    func introduced(deckID: UUID, on date: Date = Date()) -> Int {
        defaults.integer(forKey: Self.key(deckID: deckID, on: date))
    }

    /// Records that `count` new cards were introduced, and clears out yesterday's keys while it is
    /// here. Without the sweep every deck leaves one dead key per day, forever.
    func note(_ count: Int, deckID: UUID, on date: Date = Date()) {
        guard count > 0 else { return }
        let key = Self.key(deckID: deckID, on: date)
        defaults.set(defaults.integer(forKey: key) + count, forKey: key)
        pruneKeys(otherThan: Self.dayKey(date))
    }

    /// Today's remaining allowance for a deck, floored at zero. A deck's `newPerDay` can be lowered
    /// below what has already been introduced, and a negative allowance would read as a debt.
    func allowance(for deck: Deck, on date: Date = Date()) -> Int {
        max(0, deck.newPerDay - introduced(deckID: deck.id, on: date))
    }

    /// Only for tests and for a future "reset today's count" control.
    func reset(deckID: UUID, on date: Date = Date()) {
        defaults.removeObject(forKey: Self.key(deckID: deckID, on: date))
    }

    /// Forgets every deck's count, for every day.
    ///
    /// Used when the store is reset to sample data. Without it a seeded launch inherits whatever
    /// allowance the previous one spent, so a walk or a UI test can find a freshly seeded deck
    /// with nothing available to study.
    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func pruneKeys(otherThan today: String) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.prefix) && !key.hasSuffix(":\(today)") {
            defaults.removeObject(forKey: key)
        }
    }
}
