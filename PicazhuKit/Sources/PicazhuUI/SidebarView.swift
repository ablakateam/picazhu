import SwiftUI
import PicazhuCore

public struct SidebarSelection: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case library
        case folder(FolderID)
        case pinned
        case recent
        case savedSearch(SavedSearchID)
        case diagnostics
    }
    public let kind: Kind
    public init(kind: Kind) { self.kind = kind }
}

public struct SidebarSection<Content: View>: View {
    public let title: String
    public let content: () -> Content

    public init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        Section {
            content()
        } header: {
            Text(title)
                .font(DesignTokens.Typography.sectionHeader)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }
}
