import SwiftUI

struct MediaDownloadPlannerItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let isUnavailable: Bool
    let status: String?
}

struct MediaDownloadPlannerGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let countLabel: String
    let items: [MediaDownloadPlannerItem]
}

struct MediaDownloadPlannerView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let groups: [MediaDownloadPlannerGroup]
    let onDownload: (MediaDownloadQuality, Set<String>) -> Void

    @State private var quality: MediaDownloadQuality
    @State private var selectedItemIDs: Set<String>

    init(
        title: String,
        groups: [MediaDownloadPlannerGroup],
        initiallySelectedItemIDs: Set<String>,
        quality: MediaDownloadQuality = .p1080,
        onDownload: @escaping (MediaDownloadQuality, Set<String>) -> Void
    ) {
        self.title = title
        self.groups = groups
        self.onDownload = onDownload
        _quality = State(initialValue: quality)
        _selectedItemIDs = State(initialValue: initiallySelectedItemIDs)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            episodeList
            Divider()
            footer
        }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 420, idealHeight: 560)
        .background(Color.asterionMediaCanvas)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.asterionDisplay(19, weight: .semibold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                Text(selectionSummary)
                    .font(.caption)
                    .foregroundStyle(Color.asterionMuted)
            }

            Spacer()

            Button("Clear") { selectedItemIDs.removeAll() }
                .disabled(selectedItemIDs.isEmpty)
            Button("Select All") { selectedItemIDs = selectableItemIDs }
                .disabled(selectedItemIDs == selectableItemIDs)
        }
        .padding(20)
    }

    private var episodeList: some View {
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.items) { item in
                        Toggle(isOn: itemBinding(item)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Color.asterionText)
                                    if let detail = item.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(Color.asterionMuted)
                                    }
                                }

                                Spacer()

                                if let status = item.status {
                                    Text(status)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.asterionMuted)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(item.isUnavailable)
                    }
                } header: {
                    HStack {
                        Button {
                            toggle(group)
                        } label: {
                            Label(group.title, systemImage: groupSelectionIcon(group))
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text(group.countLabel)
                            .font(.caption)
                            .foregroundStyle(Color.asterionMuted)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Picker("Quality", selection: $quality) {
                ForEach(MediaDownloadQuality.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .frame(width: 170)

            Text(quality.selectionDetail)
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)

            Spacer()

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button {
                onDownload(quality, selectedItemIDs)
                dismiss()
            } label: {
                Label(downloadButtonTitle, systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.asterionAccent)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedItemIDs.isEmpty)
        }
        .padding(20)
    }

    private var selectableItemIDs: Set<String> {
        Set(groups.flatMap(\.items).filter { !$0.isUnavailable }.map(\.id))
    }

    private var selectionSummary: String {
        let count = selectedItemIDs.count
        return count == 1 ? "1 item selected" : "\(count) items selected"
    }

    private var downloadButtonTitle: String {
        selectedItemIDs.count == 1 ? "Download 1" : "Download \(selectedItemIDs.count)"
    }

    private func itemBinding(_ item: MediaDownloadPlannerItem) -> Binding<Bool> {
        Binding(
            get: { selectedItemIDs.contains(item.id) },
            set: { isSelected in
                if isSelected {
                    selectedItemIDs.insert(item.id)
                } else {
                    selectedItemIDs.remove(item.id)
                }
            }
        )
    }

    private func selectableIDs(in group: MediaDownloadPlannerGroup) -> Set<String> {
        Set(group.items.filter { !$0.isUnavailable }.map(\.id))
    }

    private func toggle(_ group: MediaDownloadPlannerGroup) {
        let groupIDs = selectableIDs(in: group)
        if groupIDs.isSubset(of: selectedItemIDs) {
            selectedItemIDs.subtract(groupIDs)
        } else {
            selectedItemIDs.formUnion(groupIDs)
        }
    }

    private func groupSelectionIcon(_ group: MediaDownloadPlannerGroup) -> String {
        let groupIDs = selectableIDs(in: group)
        let selectedCount = groupIDs.intersection(selectedItemIDs).count
        if selectedCount == 0 { return "square" }
        if selectedCount == groupIDs.count { return "checkmark.square.fill" }
        return "minus.square.fill"
    }
}
