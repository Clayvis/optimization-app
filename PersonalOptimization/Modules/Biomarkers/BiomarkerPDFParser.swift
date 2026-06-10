import Foundation
import PDFKit
import Vision
import os

enum BiomarkerParseError: LocalizedError {
    case unreadablePDF(String)
    case emptyDocument(String)

    var errorDescription: String? {
        switch self {
        case .unreadablePDF(let name): return "Could not open PDF \(name)"
        case .emptyDocument(let name): return "No text could be extracted from \(name), even with OCR"
        }
    }
}

/// Result of parsing one lab report.
struct ParsedLabReport: Sendable, Equatable {
    var values: [String: Double] = [:]
    /// Marker names seen but not recognized by the alias dictionary.
    var unmatched: [String] = []
    /// Draw date found in the document (UTC midnight), if any.
    var date: Date?
    var usedOCR: Bool = false
    var sourceFilename: String?
}

/// Lab-report text extraction and marker parsing. Ported verbatim from the
/// reference implementation's `parseLines` / `extractDate` (References/
/// biomarker-tracker.html): a DOD MTF stanza parser when "Laboratory" sentinel
/// lines are present, otherwise a generic longest-alias line scanner.
///
/// Runs on its own actor: PDFKit text extraction and the Vision OCR fallback
/// are CPU-bound and must not block the main actor.
actor BiomarkerPDFParser {
    static let shared = BiomarkerPDFParser()

    /// Extract text from a PDF (Vision OCR fallback when the PDF has no text
    /// layer) and parse marker values from it.
    /// - Throws: `BiomarkerParseError` when the file cannot be opened or
    ///   yields no text by either path.
    func parse(pdfAt url: URL, sex: String) throws -> ParsedLabReport {
        let filename = url.lastPathComponent
        guard let doc = PDFDocument(url: url) else {
            throw BiomarkerParseError.unreadablePDF(filename)
        }

        var text = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")
        var usedOCR = false

        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 64 {
            // Scanned report with no text layer: rasterize pages and OCR.
            text = Self.ocrText(from: doc)
            usedOCR = true
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BiomarkerParseError.emptyDocument(filename)
        }

        var report = Self.parse(text: text, sex: sex)
        report.usedOCR = usedOCR
        report.sourceFilename = filename
        Logger.parser.info("Parsed \(report.values.count, privacy: .public) markers from \(filename, privacy: .private) ocr=\(usedOCR, privacy: .public)")
        return report
    }

    // MARK: - Text parsing (pure, synchronous, testable)

    /// Parse marker values out of raw report text. Mirrors the reference
    /// `parseLines(lines, sex)` exactly, including the DOD detection rule.
    nonisolated static func parse(text: String, sex: String) -> ParsedLabReport {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var report = ParsedLabReport()
        report.date = extractDate(from: lines)

        let isDOD = lines.filter { $0 == "Laboratory" }.count >= 3
        if isDOD {
            parseDOD(lines: lines, sex: sex, into: &report)
        } else {
            parseGeneric(lines: lines, sex: sex, into: &report)
        }
        return report
    }

    /// DOD MTF stanza format: NAME \n "Laboratory" \n "VALUE UNIT [FLAG]".
    private nonisolated static func parseDOD(lines: [String], sex: String, into report: inout ParsedLabReport) {
        guard lines.count >= 3 else { return }
        for i in 0..<(lines.count - 2) where lines[i + 1] == "Laboratory" {
            let name = lines[i]
            let valueLine = lines[i + 2]
            guard let key = BiomarkerCatalog.aliasToKey(name, sex: sex) else {
                report.unmatched.append(name)
                continue
            }
            if let value = firstNumber(in: valueLine, pattern: dodNumberPattern) {
                report.values[key] = value
            }
        }
    }

    /// Generic format: a known alias at the start of a line, first number
    /// after the name on the same or next two lines. Longest alias wins so
    /// "total cholesterol" beats "cholesterol"; zero values are rejected as
    /// parse artifacts, both per the reference.
    private nonisolated static func parseGeneric(lines: [String], sex: String, into report: inout ParsedLabReport) {
        for i in 0..<lines.count {
            let line = lines[i]
            let nline = BiomarkerCatalog.normalizeName(line)
            guard !nline.isEmpty else { continue }

            var matchedKey: String?
            var matchedAliasLen = 0
            for (alias, k) in BiomarkerCatalog.aliases where nline.hasPrefix(alias) && alias.count > matchedAliasLen {
                matchedKey = k
                matchedAliasLen = alias.count
            }
            guard let rawKey = matchedKey else { continue }

            var key = rawKey
            if sex == "female" {
                switch key {
                case "hdl_m": key = "hdl_f"
                case "ferritin_m": key = "ferritin_f"
                case "estradiol_m": key = "estradiol_f"
                case "testosterone_total_m": key = "testosterone_total_f"
                default: break
                }
            }
            guard let def = BiomarkerCatalog.all[key], def.sex == nil || def.sex == sex else { continue }
            guard report.values[key] == nil else { continue }

            // Cut the original line where the alias's normalized characters
            // end, so a number inside the name ("Vitamin B12") is not taken
            // as the value. Then search the remainder plus the next 2 lines.
            let rest = remainder(of: line, afterNormalizedPrefixLength: matchedAliasLen)
            let next1 = i + 1 < lines.count ? lines[i + 1] : ""
            let next2 = i + 2 < lines.count ? lines[i + 2] : ""
            let searchText = [rest, next1, next2].joined(separator: " ")

            if let value = firstNumber(in: searchText, pattern: genericNumberPattern), value != 0 {
                report.values[key] = value
            }
        }
    }

    // MARK: - Date extraction (port of extractDate)

    private nonisolated static let datePatterns: [String] = [
        #"(\d{4}-\d{2}-\d{2})"#,
        #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{1,2}),?\s+(\d{4})"#,
        #"(\d{1,2})/(\d{1,2})/(\d{4})"#
    ]

    nonisolated static func extractDate(from lines: [String]) -> Date? {
        for line in lines {
            for pattern in datePatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let range = Range(match.range, in: line) else { continue }
                if let date = parseDateToken(String(line[range])) {
                    return date
                }
            }
        }
        return nil
    }

    /// Parse one matched token to UTC midnight, like the reference's
    /// `new Date(...).toISOString().slice(0, 10)`.
    private nonisolated static func parseDateToken(_ token: String) -> Date? {
        let formats = ["yyyy-MM-dd", "MMM d, yyyy", "MMM d yyyy", "MMMM d, yyyy", "MMMM d yyyy", "M/d/yyyy"]
        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = format
            if let d = f.date(from: token) {
                return d
            }
        }
        return nil
    }

    // MARK: - Number matching (reference regexes, alternation order preserved)

    private nonisolated static let dodNumberPattern = #"[-+]?\d+\.?\d*"#
    private nonisolated static let genericNumberPattern = #"[-+]?\d+\.?\d+|\d+"#

    private nonisolated static func firstNumber(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Double(text[range])
    }

    /// Index into the ORIGINAL line where `count` normalized characters have
    /// been consumed, returning everything after the alias.
    private nonisolated static func remainder(of line: String, afterNormalizedPrefixLength count: Int) -> String {
        var consumed = 0
        var lastSeparator = false
        for (offset, ch) in line.lowercased().enumerated() {
            let l = ch
            let isKept = (l.isLetter && l.isASCII) || l.isNumber || l == "%" || l == "(" || l == ")" || l == "-"
            if isKept {
                consumed += 1
                lastSeparator = false
            } else if l == " " || l.isWhitespace {
                // Collapsing whitespace contributes one normalized char
                // between kept runs (split/joined in normalizeName).
                if consumed > 0 && !lastSeparator { consumed += 1 }
                lastSeparator = true
            }
            if consumed >= count {
                let idx = line.index(line.startIndex, offsetBy: offset + 1)
                return String(line[idx...])
            }
        }
        return ""
    }

    // MARK: - OCR fallback

    private nonisolated static func ocrText(from doc: PDFDocument) -> String {
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            // 2x scale keeps small lab-table glyphs legible to the recognizer.
            let size = CGSize(width: bounds.width * 2, height: bounds.height * 2)
            let image = page.thumbnail(of: size, for: .mediaBox)
            guard let cgImage = image.cgImage else { continue }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                Logger.parser.warning("OCR failed on page \(i, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            let lines = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
            pages.append(lines.joined(separator: "\n"))
        }
        return pages.joined(separator: "\n")
    }
}
