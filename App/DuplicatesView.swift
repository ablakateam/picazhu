import SwiftUI
import AppKit
import PicazhuMedia
import PicazhuCore
import PicazhuUI

struct DuplicatesView: View {
    @Bindable var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicate Detection")
                        .font(.headline)
                    Text("\(model.duplicateGroups.count) groups found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isScanningDuplicates {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Divider()

            if model.duplicateGroups.isEmpty && !model.isScanningDuplicates {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("No duplicates found")
                        .font(.title3.weight(.semibold))
                    Text("All media in the current folder appears unique.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(model.duplicateGroups) { group in
                            DuplicateGroupRow(group: group, model: model)
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack {
                Button("Rescan") {
                    Task { await model.scanForDuplicates() }
                }
                .disabled(model.isScanningDuplicates)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
    }
}

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    @Bindable var model: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(group.itemIDs.count) similar items")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(Int(group.similarity * 100))% match")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(matchColor.opacity(0.15)))
                    .foregroundStyle(matchColor)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(group.itemIDs, id: \.rawValue) { itemID in
                        if let item = model.items.first(where: { $0.id == itemID }) {
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                    if let thumb = model.thumbnail(for: item) {
                                        Image(nsImage: thumb)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 100, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(width: 100, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                                )

                                Text(item.filename)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(width: 100)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.06))
        )
    }

    private var matchColor: Color {
        group.similarity > 0.95 ? .red : .orange
    }
}
