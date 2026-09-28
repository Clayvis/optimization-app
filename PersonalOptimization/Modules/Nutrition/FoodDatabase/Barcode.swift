import Foundation

/// Retail barcode handling for food lookup. EAN-8, UPC-A, EAN-13 and GTIN-14
/// end in a mod-10 check digit; UPC-E is a compressed UPC-A. One product can
/// appear as UPC-A (12 digits) or as its EAN-13 form (a leading zero), so a
/// lookup compares every equivalent spelling. Pure, for deterministic tests.
enum Barcode {
    /// The payload's digits, ignoring spaces and hyphens. Nil when anything
    /// else is present or nothing is left.
    static func digits(_ raw: String) -> String? {
        let cleaned = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return cleaned
    }

    /// True for an 8, 12, 13 or 14 digit GTIN with a correct check digit.
    /// Weights alternate 3, 1 from the digit next to the check digit.
    static func isValidGTIN(_ code: String) -> Bool {
        guard [8, 12, 13, 14].contains(code.count) else { return false }
        let values = code.compactMap(\.wholeNumberValue)
        guard values.count == code.count, let check = values.last else { return false }
        var sum = 0
        for (offset, value) in values.dropLast().reversed().enumerated() {
            sum += value * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    /// Expands an 8-digit UPC-E (number system 0 or 1) to its 12-digit UPC-A.
    /// Nil when the code cannot be UPC-E or the expansion fails its check digit.
    static func expandUPCE(_ code: String) -> String? {
        let d = code.compactMap(\.wholeNumberValue)
        guard d.count == 8, d[0] == 0 || d[0] == 1 else { return nil }
        let x = Array(d[1...6])
        let body: [Int]
        switch x[5] {
        case 0, 1, 2: body = [x[0], x[1], x[5], 0, 0, 0, 0, x[2], x[3], x[4]]
        case 3: body = [x[0], x[1], x[2], 0, 0, 0, 0, 0, x[3], x[4]]
        case 4: body = [x[0], x[1], x[2], x[3], 0, 0, 0, 0, 0, x[4]]
        default: body = [x[0], x[1], x[2], x[3], x[4], 0, 0, 0, 0, x[5]]
        }
        let upcA = ([d[0]] + body + [d[7]]).map(String.init).joined()
        return isValidGTIN(upcA) ? upcA : nil
    }

    /// Every equivalent GTIN spelling to try, canonical first (EAN-13 when the
    /// product has one). Empty when the payload is not a valid retail code,
    /// for example a Code 128 shipping label. `isUPCE` comes from the scanner;
    /// a typed 8-digit code is tried as EAN-8 first, then as UPC-E.
    static func lookupKeys(for raw: String, isUPCE: Bool = false) -> [String] {
        guard let code = digits(raw) else { return [] }
        var keys: [String] = []
        func add(_ key: String) { if !keys.contains(key) { keys.append(key) } }
        let expanded = code.count == 8 ? expandUPCE(code) : nil
        if isUPCE, let expanded { add("0" + expanded); add(expanded) }
        if isValidGTIN(code) {
            switch code.count {
            case 12: add("0" + code); add(code)
            case 13, 14:
                add(code)
                if code.hasPrefix("0") { add(String(code.dropFirst())) }
            default: add(code)
            }
        }
        if !isUPCE, let expanded { add("0" + expanded); add(expanded) }
        return keys
    }
}
