import CoreGraphics
import Foundation
import ImageIO
import Vision

enum InBodyPhotoError: LocalizedError, Equatable {
    case unreadableImage
    case noValuesFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "That image couldn't be opened. Try another photo."
        case .noValuesFound:
            return "No InBody values were found. Use a flat, well-lit photo of the whole result sheet, or type the values."
        }
    }
}

/// Reads InBody result sheets from images on the device with Vision. Nothing
/// is uploaded and nothing is kept: the caller gets values to review.
/// Synchronous and CPU-heavy; call it off the main actor.
///
/// Text is recognized on the photo as taken, at two sizes. Receipt-printer
/// digits read differently from one scale to another (a "4" at one size is
/// a "1" at the next), so the passes are combined and any disagreement is
/// flagged rather than trusted. A perspective-corrected copy was tried and
/// read worse: resampling blurred the digits and curled paper skewed the rows.
enum InBodySheetRecognizer {
    /// Long-edge sizes for the recognition passes. A photo smaller than a size
    /// is read at its own size; a repeated size is skipped.
    static let passSizes = [3024, 2000]

    /// One reading from one or more images (pages); earlier pages win.
    static func read(imageData pages: [Data], now: Date, calendar: Calendar) throws -> InBodyPhotoReading {
        var result: InBodyPhotoReading?
        for data in pages {
            let page = try read(imageData: data, now: now, calendar: calendar)
            result = result.map { $0.merged(with: page) } ?? page
        }
        guard let result, !result.read.isEmpty else { throw InBodyPhotoError.noValuesFound }
        return result
    }

    static func read(imageData: Data, now: Date, calendar: Calendar) throws -> InBodyPhotoReading {
        var passes: [InBodyPhotoReading] = []
        var sizes: Set<Int> = []
        for size in passSizes {
            let image = try decodedImage(imageData, maxPixelSize: size)
            guard sizes.insert(max(image.width, image.height)).inserted else { continue }
            passes.append(try read(image, now: now, calendar: calendar))
        }
        guard let combined = InBodySheetParser.consensus(passes) else { throw InBodyPhotoError.unreadableImage }
        return combined
    }

    /// One pass. A Japanese sheet reads poorly as English; retry only then.
    static func read(_ image: CGImage, now: Date, calendar: Calendar) throws -> InBodyPhotoReading {
        var reading = InBodySheetParser.parse(try recognizeText(in: image, languages: ["en-US"]), now: now, calendar: calendar)
        if reading.read.count < 4, supportedLanguages().contains("ja-JP"),
           // MARK: try? justified: the English pass already succeeded; a failed retry keeps it.
           let japanese = try? recognizeText(in: image, languages: ["ja-JP", "en-US"]) {
            let alternative = InBodySheetParser.parse(japanese, now: now, calendar: calendar)
            if alternative.read.count > reading.read.count { reading = alternative }
        }
        return reading
    }

    /// Decoded with the photo's orientation applied, no larger than `maxPixelSize`.
    static func decodedImage(_ imageData: Data, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary) else { throw InBodyPhotoError.unreadableImage }
        return image
    }

    static func recognizeText(in image: CGImage, languages: [String]) throws -> [RecognizedTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" numbers and abbreviations like PBF.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages
        // Result sheets use small print; the default ignores text under 1/32 of the height.
        request.minimumTextHeight = 0.005
        try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:]).perform([request])
        let width = CGFloat(image.width), height = CGFloat(image.height)
        func pixel(_ normalized: CGPoint) -> CGPoint { CGPoint(x: normalized.x * width, y: (1 - normalized.y) * height) }
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let (topLeft, topRight) = (pixel(observation.topLeft), pixel(observation.topRight))
            let (bottomLeft, bottomRight) = (pixel(observation.bottomLeft), pixel(observation.bottomRight))
            return RecognizedTextLine(
                text: text,
                center: CGPoint(x: (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4,
                                y: (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4),
                width: hypot(bottomRight.x - bottomLeft.x, bottomRight.y - bottomLeft.y),
                height: hypot(topLeft.x - bottomLeft.x, topLeft.y - bottomLeft.y),
                angle: atan2(bottomRight.y - bottomLeft.y, bottomRight.x - bottomLeft.x))
        }
    }

    static func supportedLanguages() -> [String] {
        // MARK: try? justified: an unsupported query just means English only.
        (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
    }
}
