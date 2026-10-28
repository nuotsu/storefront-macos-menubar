import Foundation

/// Minimal RFC4180-ish CSV encode/decode — just enough for the store list's
/// "Display Name,Domain,Color" export/import, including quoted fields with
/// embedded commas or quotes.
enum CSV {
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func parse(_ contents: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInQuotes = false
        let chars = Array(contents)
        var i = 0

        while i < chars.count {
            let char = chars[i]
            if isInQuotes {
                if char == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        isInQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    isInQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                // `"\r\n"` is a single `Character` in Swift, so CRLF files (Excel, Google
                // Sheets) never match `"\n"` alone and would parse as one long row.
                case "\n", "\r\n":
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                case "\r":
                    break
                default:
                    currentField.append(char)
                }
            }
            i += 1
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
