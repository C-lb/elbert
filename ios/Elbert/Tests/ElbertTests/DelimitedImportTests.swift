import Testing

@testable import Elbert

// Every case in `src/import/csv.test.ts` is the oracle and appears first, in that file's order.
// The suite after them is the edge coverage the web app never had.

@Suite("Delimited import, the web app's cases")
struct DelimitedImportOracleTests {
    @Test("tab-delimited rows, the Quizlet default export")
    func tabs() {
        #expect(DelimitedImport.parse("chat\tcat\nchien\tdog") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("comma-delimited rows with quoted fields containing commas")
    func quotedCommas() {
        #expect(DelimitedImport.parse("\"a, b\",def\nterm2,def2") == [
            ImportRow(term: "a, b", definition: "def"),
            ImportRow(term: "term2", definition: "def2"),
        ])
    }

    @Test("quoted fields with embedded newlines")
    func embeddedNewlines() {
        #expect(DelimitedImport.parse("\"line1\nline2\",def") == [
            ImportRow(term: "line1\nline2", definition: "def"),
        ])
    }

    @Test("escaped quotes inside quoted fields")
    func escapedQuotes() {
        #expect(DelimitedImport.parse("\"she said \"\"hi\"\"\",def") == [
            ImportRow(term: "she said \"hi\"", definition: "def"),
        ])
    }

    @Test("semicolon is the fallback when there is no tab or comma")
    func semicolons() {
        #expect(DelimitedImport.parse("chat;cat\nchien;dog") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("extra columns join onto the definition with a middle dot")
    func extraColumns() {
        #expect(DelimitedImport.parse("chat,cat,feline,animal") == [
            ImportRow(term: "chat", definition: "cat · feline · animal"),
        ])
    }

    @Test("cell whitespace is trimmed")
    func trimming() {
        #expect(DelimitedImport.parse("  chat  ,  cat  ") == [
            ImportRow(term: "chat", definition: "cat"),
        ])
    }

    @Test("empty lines are skipped")
    func emptyLines() {
        #expect(DelimitedImport.parse("chat\tcat\n\n\nchien\tdog") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("rows with an empty term are skipped")
    func emptyTerm() {
        #expect(DelimitedImport.parse("chat\tcat\n\tdog\n   \tcat2") == [
            ImportRow(term: "chat", definition: "cat"),
        ])
    }

    @Test("CRLF line endings")
    func crlf() {
        #expect(DelimitedImport.parse("chat\tcat\r\nchien\tdog\r\n") == [
            ImportRow(term: "chat", definition: "cat"),
            ImportRow(term: "chien", definition: "dog"),
        ])
    }

    @Test("empty input parses to nothing")
    func empty() {
        #expect(DelimitedImport.parse("").isEmpty)
        #expect(DelimitedImport.parse("   \n  \n").isEmpty)
    }

    @Test("a row with only a term keeps an empty definition")
    func termOnly() {
        #expect(DelimitedImport.parse("chat") == [ImportRow(term: "chat", definition: "")])
    }
}

@Suite("Delimited import, edges the web app never covered")
struct DelimitedImportEdgeTests {
    @Test("a byte order mark does not become part of the first term")
    func bom() {
        #expect(DelimitedImport.parse("\u{FEFF}chat\tcat") == [
            ImportRow(term: "chat", definition: "cat"),
        ])
    }

    @Test("an unterminated quote keeps the rest of the input as one field")
    func unterminatedQuote() {
        #expect(DelimitedImport.parse("\"chat,cat") == [
            ImportRow(term: "chat,cat", definition: ""),
        ])
    }

    @Test("a quote that is not the first character is a literal quote")
    func lateQuote() {
        #expect(DelimitedImport.parse("5\" nail,a nail") == [
            ImportRow(term: "5\" nail", definition: "a nail"),
        ])
    }

    @Test("the delimiter is chosen once, so commas inside a tab file stay put")
    func delimiterChosenOnce() {
        #expect(DelimitedImport.parse("chat\tcat, a small one") == [
            ImportRow(term: "chat", definition: "cat, a small one"),
        ])
    }
}
