import Foundation
import ImageIO
import PicazhuCore

public struct ImageMetadata: Sendable {
    public var width: Int?
    public var height: Int?
    public var orientation: Int?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lens: String?
    public var iso: Int?
    public var fNumber: Double?
    public var exposureTime: Double?
    public var focalLength: Double?
    public var captureTime: Date?
    public var gpsLat: Double?
    public var gpsLon: Double?
    public var exifJSON: String?
}

public enum ImageMetadataReader {
    public static func read(url: URL) throws -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw PicazhuError.metadataReadFailed(url, "CGImageSource unavailable")
        }
        guard let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw PicazhuError.metadataReadFailed(url, "no properties")
        }

        var m = ImageMetadata()
        m.width = raw[kCGImagePropertyPixelWidth] as? Int
        m.height = raw[kCGImagePropertyPixelHeight] as? Int
        m.orientation = raw[kCGImagePropertyOrientation] as? Int

        if let tiff = raw[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            m.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }
        if let exif = raw[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            m.lens = exif[kCGImagePropertyExifLensModel] as? String
            if let isoArr = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int] {
                m.iso = isoArr.first
            }
            m.fNumber = exif[kCGImagePropertyExifFNumber] as? Double
            m.exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
            m.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
            if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                m.captureTime = exifDate(from: dateStr)
            }
        }
        if let gps = raw[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
            let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
            m.gpsLat = latRef == "S" ? -lat : lat
            m.gpsLon = lonRef == "W" ? -lon : lon
        }

        if let json = try? JSONSerialization.data(withJSONObject: stringKeyed(raw), options: []) {
            m.exifJSON = String(data: json, encoding: .utf8)
        }

        return m
    }

    private static func exifDate(from string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy:MM:dd HH:mm:ss"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: string)
    }

    private static func stringKeyed(_ dict: [CFString: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in dict {
            let key = k as String
            if let sub = v as? [CFString: Any] {
                out[key] = stringKeyed(sub)
            } else if JSONSerialization.isValidJSONObject([v]) {
                out[key] = v
            } else if let n = v as? NSNumber {
                out[key] = n
            } else {
                out[key] = "\(v)"
            }
        }
        return out
    }
}
