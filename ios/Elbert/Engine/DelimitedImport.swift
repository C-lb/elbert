import Foundation

/// One row of a pasted or picked file, before it becomes a note.
struct ImportRow: Equatable, Sendable {
    let term: String
    let definition: String
}

/// Parses delimited text into rows.
///
/// Port of `src/import/csv.ts`, and that file's test suite is the oracle. The behaviour worth
/// knowing before changing anything here: the delimiter is chosen once for the whole input rather
/// than per line, because a definition containing a comma inside a tab-delimited file would
/// otherwise split in the wrong place, and that is the common case with Quizlet exports.
///
/// Nothing here tries to detect a header row. Any heuristic for that eventually eats a real first
/// card, so the decision belongs to the person importing, and `ImportSheet` gives them a toggle.
enum DelimitedImport {
    static func parse(_ text: String) -> [ImportRow] {
        var text = text
        // Excel on Windows writes a byte order mark. Left in place it rides along on the first
        // term, and the first card silently reads wrong.
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let delimiter = detectDelimiter(text)
        var out: [ImportRow] = []

        for cells in splitRows(text, delimiter: delimiter) {
            let trimmed = cells.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let allBlank = trimmed.allSatisfy(\.isEmpty)
            if allBlank { continue }

            guard let term = trimmed.first, !term.isEmpty else { continue }

            // Columns past the second are appended rather than dropped, so a three-column export
            // does not silently lose its third column.
            let definition = trimmed.count > 1 ? trimmed[1...].joined(separator: " · ") : ""
            out.append(ImportRow(term: term, definition: definition))
        }

        return out
    }

    private static func detectDelimiter(_ text: String) -> Unicode.Scalar {
        if text.unicodeScalars.contains("\t") { return "\t" }
        if text.unicodeScalars.contains(",") { return "," }
        return ";"
    }

    /// Splits text into rows of raw fields, respecting quoted fields that may contain the
    /// delimiter and may contain newlines.
    ///
    /// This walks unicode scalars rather than characters, and that is load-bearing rather than a
    /// style choice. Swift treats CRLF as ONE `Character`, a single grapheme cluster, so a
    /// character-wise walk matches neither `"\r"` nor `"\n"` on a Windows line ending and appends
    /// the whole break into the field instead of ending the row. The JavaScript this is ported
    /// from iterates UTF-16 code units and has no such cluster, so scalars are what keep the two
    /// implementations agreeing. `src/import/csv.test.ts`'s CRLF case is what caught it.
    private static func splitRows(_ text: String, delimiter: Unicode.Scalar) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false

        func pushField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
        }
        func pushRow() {
            pushField()
            rows.append(row)
            row = []
        }

        let scalars = Array(text.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            if inQuotes {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(scalar)
                }
                index += 1
                continue
            }

            // A quote only opens a quoted field at the start of one. Anywhere else it is a literal
            // quote, which is what makes `5" nail` survive.
            if scalar == "\"" && field.isEmpty {
                inQuotes = true
                index += 1
                continue
            }
            if scalar == delimiter {
                pushField()
                index += 1
                continue
            }
            if scalar == "\r" {
                index += 1
                continue
            }
            if scalar == "\n" {
                pushRow()
                index += 1
                continue
            }

            field.append(scalar)
            index += 1
        }

        // Flush a trailing field or row, unless the input ended cleanly on a newline and it was
        // already pushed.
        if !field.isEmpty || !row.isEmpty { pushRow() }

        return rows
    }
}
