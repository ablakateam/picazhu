import SwiftUI

public enum DesignTokens {
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
    }

    public enum Grid {
        public static let minCellSize: CGFloat = 96
        public static let defaultCellSize: CGFloat = 168
        public static let maxCellSize: CGFloat = 320
        public static let gutter: CGFloat = 10
    }

    public enum Palette {
        public static let selection = Color.accentColor.opacity(0.18)
        public static let selectionBorder = Color.accentColor
        public static let card = Color(nsColor: .controlBackgroundColor)
        public static let subtleBorder = Color.primary.opacity(0.08)
    }

    public enum Typography {
        public static let sectionHeader = Font.system(.subheadline, design: .default, weight: .semibold)
        public static let itemTitle = Font.system(.body, design: .default, weight: .medium)
        public static let itemCaption = Font.system(.caption, design: .default)
        public static let metaLabel = Font.system(.caption2, design: .default, weight: .semibold)
    }
}
