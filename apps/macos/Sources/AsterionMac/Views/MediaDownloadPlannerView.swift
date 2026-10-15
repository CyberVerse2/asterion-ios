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
            Rectangle().fill(Color.asterionHairline).frame(height: 1)
            episodeList
            Rectangle().fill(Color.asterionHairline).frame(height: 1)
            footer
        }
        .frame(minWidth: 500, idealWidth: 560, minHeight: 420, idealHeight: 560)
        .background(Color.asterionMediaCanvas)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.asterionTitle(20, weight: .bold))
                    .foregroundStyle(Color.asterionText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Text(selectionSummary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.asterionMuted)
            }

            Spacer()

            Button("Clear") { selectedItemIDs.removeAll() }
                .buttonStyle(.asterionSecondary)
                .disabled(selectedItemIDs.isEmpty)
            Button("Select all") { selectedItemIDs = selectableItemIDs }
                .buttonStyle(.asterionSecondary)
                .disabled(selectedItemIDs == selectableItemIDs)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var episodeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Button {
                                toggle(group)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: groupSelectionIcon(group))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.asterionText)
                                    Text(group.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.asterionText)
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Select or clear every episode in \(group.title)")
                            .accessibilityLabel(group.title)
                            .accessibilityValue(groupSelectionValue(group))
                            .accessibilityHint("Selects or clears every episode in this group")

                            Spacer()

                            Text(group.countLabel)
                                .font(.asterionMono(11, weight: .medium))
                                .foregroundStyle(Color.asterionFaint)
                        }
                        .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.asterionHairline)
                                        .frame(height: 1)
                                        .padding(.leading, 44)
                                }
                                PlannerItemRow(item: item, isOn: itemBinding(item))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .asterionPanel(cornerRadius: 14)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .hidingScrollIndicators()
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(MediaDownloadQuality.allCases) { option in
                        QualityChip(option: option, isSelected: quality == option) {
                            quality = option
                        }
                    }
                }
                .padding(3)
                .background(Color.asterionSurface, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.asterionBorder))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Quality")

                Text(quality.selectionDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.asterionMuted)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.asterionSecondary)
                .keyboardShortcut(.cancelAction)

            Button {
                onDownload(quality, selectedItemIDs)
                dismiss()
            } label: {
                Label(downloadButtonTitle, systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.asterionPrimary)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedItemIDs.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Color.asterionSurface.opacity(0.5))
    }

    private var selectableItemIDs: Set<String> {
        Set(groups.flatMap(\.items).filter { !$0.isUnavailable }.map(\.id))
    }

    private var selectionSummary: String {
        let count = selectedItemIDs.count
        return count == 1 ? "1 item selected" : "\(count) items selected"
    }

    private var downloadButtonTitle: String {
        let count = selectedItemIDs.count
        if groups.count == 1, groups.first?.id == "movie" {
            return count == 1 ? "Download" : "Download \(count)"
        }
        return count == 1 ? "Download 1 episode" : "Download \(count) episodes"
    }

    private func groupSelectionValue(_ group: MediaDownloadPlannerGroup) -> String {
        let groupIDs = selectableIDs(in: group)
        let selectedCount = groupIDs.intersection(selectedItemIDs).count
        return "\(selectedCount) of \(groupIDs.count) selected"
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

private struct PlannerItemRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let item: MediaDownloadPlannerItem
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(item.isUnavailable ? Color.asterionMuted : Color.asterionText)
                        .lineLimit(1)
                    if let detail = item.detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.asterionMuted)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let status = item.status {
                    Text(status)
                        .font(.asterionMono(11, weight: .medium))
                        .foregroundStyle(Color.asterionMuted)
                }
            }
            .padding(.leading, 6)
        }
        .toggleStyle(.checkbox)
        .disabled(item.isUnavailable)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isHovering && !item.isUnavailable ? 0.04 : 0))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : AsterionMotion.hover, value: isHovering)
    }
}

private struct QualityChip: View {
    let option: MediaDownloadQuality
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(option.title)
                .font(.asterionMono(12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.asterionMediaCanvas : Color.asterionMuted)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(isSelected ? Color.asterionText : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(option.selectionDetail)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
