import SwiftUI
import MapKit
import PicazhuCore

public struct PhotoLocation: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let cameraMake: String?
    public let cameraModel: String?
    public let lens: String?
    public let focalLength: Double?
    public let fNumber: Double?
    public let iso: Int?
    public let exposureTime: Double?
    public let captureTime: Date?

    public init(
        latitude: Double, longitude: Double,
        cameraMake: String? = nil, cameraModel: String? = nil,
        lens: String? = nil, focalLength: Double? = nil,
        fNumber: Double? = nil, iso: Int? = nil,
        exposureTime: Double? = nil, captureTime: Date? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lens = lens
        self.focalLength = focalLength
        self.fNumber = fNumber
        self.iso = iso
        self.exposureTime = exposureTime
        self.captureTime = captureTime
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

public struct MapPreviewView: View {
    public let location: PhotoLocation
    @State private var region: MKCoordinateRegion

    public init(location: PhotoLocation) {
        self.location = location
        _region = State(initialValue: MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .foregroundStyle(.blue)
                Text("Location")
                    .font(.headline)
                Spacer()
                Button {
                    openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            Map(coordinateRegion: $region, annotationItems: [AnnotationItem(coordinate: location.coordinate)]) { item in
                MapMarker(coordinate: item.coordinate, tint: .blue)
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))

            Text(coordinateText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if hasCameraInfo {
                Divider()
                cameraInfoView
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.blue.opacity(0.06))
        )
    }

    private var coordinateText: String {
        let lat = String(format: "%.6f", location.latitude)
        let lon = String(format: "%.6f", location.longitude)
        let ns = location.latitude >= 0 ? "N" : "S"
        let ew = location.longitude >= 0 ? "E" : "W"
        return "\(lat)° \(ns), \(lon)° \(ew)"
    }

    private var hasCameraInfo: Bool {
        location.cameraModel != nil || location.lens != nil || location.focalLength != nil
    }

    @ViewBuilder
    private var cameraInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let make = location.cameraMake, let model = location.cameraModel {
                metaRow("Camera", "\(make) \(model)")
            } else if let model = location.cameraModel {
                metaRow("Camera", model)
            }
            if let lens = location.lens {
                metaRow("Lens", lens)
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                if let fl = location.focalLength {
                    Text("\(Int(fl))mm").font(.caption.monospacedDigit())
                }
                if let fn = location.fNumber {
                    Text("f/\(String(format: "%.1f", fn))").font(.caption.monospacedDigit())
                }
                if let iso = location.iso {
                    Text("ISO \(iso)").font(.caption.monospacedDigit())
                }
                if let exp = location.exposureTime {
                    Text(formatExposure(exp)).font(.caption.monospacedDigit())
                }
            }
            .foregroundStyle(.secondary)

            if let time = location.captureTime {
                metaRow("Taken", DateFormatter.localizedString(from: time, dateStyle: .medium, timeStyle: .short))
            }
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(DesignTokens.Typography.metaLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
    }

    private func formatExposure(_ seconds: Double) -> String {
        if seconds >= 1 { return "\(String(format: "%.1f", seconds))s" }
        let denom = Int(round(1.0 / seconds))
        return "1/\(denom)s"
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: location.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = "Photo Location"
        item.openInMaps()
    }
}

struct AnnotationItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
