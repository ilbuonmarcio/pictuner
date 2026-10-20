import Foundation
import ImageIO

/// Camera values only. A missing capture clock is never replaced with a file date.
struct PhotoMetadata: Equatable, Sendable {
    var captureDate: String?
    var coordinates: String?

    static func read(_ url: URL) -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return PhotoMetadata() }
        return PhotoMetadata(properties: properties)
    }

    init(captureDate: String? = nil, coordinates: String? = nil) {
        self.captureDate = captureDate; self.coordinates = coordinates
    }

    init(properties: [String: Any]) {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        if let raw = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            // EXIF's clock may have no time zone. Format the recorded wall clock as-is.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            if raw.count == 19, let date = formatter.date(from: raw), formatter.string(from: date) == raw {
                formatter.dateFormat = "d MMM yyyy · HH:mm:ss"
                captureDate = formatter.string(from: date)
                if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String,
                   offset.range(of: #"^[+-](0[0-9]|1[0-4]):[0-5][0-9]$"#, options: .regularExpression) != nil {
                    captureDate! += " \(offset)"
                }
            }
        }
        let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
        if let latitude = gps[kCGImagePropertyGPSLatitude as String] as? NSNumber,
           let longitude = gps[kCGImagePropertyGPSLongitude as String] as? NSNumber,
           let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
           let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
           latitude.doubleValue.isFinite, longitude.doubleValue.isFinite,
           (0...90).contains(latitude.doubleValue), (0...180).contains(longitude.doubleValue),
           ["N", "S"].contains(latRef), ["E", "W"].contains(lonRef) {
            coordinates = String(format: "%.5f° %@   %.5f° %@", locale: Locale(identifier: "en_US_POSIX"),
                                 latitude.doubleValue, latRef, longitude.doubleValue, lonRef)
        }
    }
}

enum OverlayPosition: String, Codable, CaseIterable, Sendable {
    case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight
    var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topCenter: return "Top center"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomCenter: return "Bottom center"
        case .bottomRight: return "Bottom right"
        }
    }
}

struct MetadataOverlay: Codable, Equatable, Sendable {
    var enabled = false
    var showsDate = true
    var showsGPS = true
    var position = OverlayPosition.bottomLeft
    /// Proportions of the final cropped image's shorter edge, including the plate's margin.
    var margin = 0.035
    var textSize = 0.025

    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, showsDate, showsGPS, position, margin, textSize }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        showsDate = try values.decode(Bool.self, forKey: .showsDate)
        showsGPS = try values.decode(Bool.self, forKey: .showsGPS)
        position = try values.decode(OverlayPosition.self, forKey: .position)
        margin = try values.decode(Double.self, forKey: .margin)
        textSize = try values.decode(Double.self, forKey: .textSize)
        guard margin.isFinite, (0.01...0.12).contains(margin), textSize.isFinite, (0.012...0.05).contains(textSize) else {
            throw DecodingError.dataCorruptedError(forKey: .margin, in: values, debugDescription: "Invalid EXIF overlay dimensions.")
        }
    }

    func lines(for metadata: PhotoMetadata) -> [String] {
        guard enabled else { return [] }
        return [showsDate ? metadata.captureDate : nil, showsGPS ? metadata.coordinates : nil].compactMap { $0 }
    }
}
