import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppSection
    @Binding var isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            VStack(spacing: 5) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: isCompact ? 0 : 11) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            if !isCompact {
                                Text(section.title)
                                    .font(.asterionDisplay(14, weight: selection == section ? .semibold : .medium))
                                Spacer()
                            }
                        }
                            .foregroundStyle(
                                selection == section
                                    ? (isCompact ? Color.asterionAccent : Color.asterionText)
                                    : Color.asterionSidebarMuted
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, isCompact ? 10 : 12)
                            .padding(.vertical, 10)
                            .background {
                                if selection == section {
                                    RoundedRectangle(cornerRadius: isCompact ? 10 : 8, style: .continuous)
                                        .fill(isCompact ? Color.asterionAccentSoft.opacity(0.72) : Color.asterionSidebarSelection)
                                }
                            }
                            .overlay(alignment: .leading) {
                                if selection == section, !isCompact {
                                    Capsule()
                                        .fill(Color.asterionSidebarAccent)
                                        .frame(width: 3, height: 22)
                                        .padding(.leading, 3)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: isCompact ? 10 : 8, style: .continuous)
                                    .stroke(selection == section ? Color.asterionBorder : .clear)
                            }
                            .animation(
                                reduceMotion ? nil : AsterionMotion.navigation,
                                value: selection == section
                            )
                    }
                    .buttonStyle(AsterionPressButtonStyle())
                    .help(section.title)
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 20)

            compactToggle
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .trailing)
                .padding(.horizontal, 14)
                .padding(.bottom, model.signedInUser == nil ? 16 : 8)

            if let user = model.signedInUser {
                HStack(spacing: isCompact ? 0 : 10) {
                    AsyncImage(url: user.imageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(Color.asterionMuted)
                        }
                    }
                    .frame(width: isCompact ? 26 : 30, height: isCompact ? 26 : 30)
                    .clipShape(Circle())

                    if !isCompact {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.name)
                                .font(.asterionDisplay(12, weight: .semibold))
                                .foregroundStyle(Color.asterionSidebarText)
                                .lineLimit(1)
                            Text("Reader")
                                .font(.caption2)
                                .foregroundStyle(Color.asterionSidebarAccent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
                .padding(.horizontal, isCompact ? 10 : 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .overlay(alignment: .top) {
                    Divider().overlay(Color.asterionBorder)
                }
            }
        }
        .background {
            Color.asterionSidebar
                .ignoresSafeArea()
        }
        .clipShape(Rectangle())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.asterionBorder)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        if isCompact {
            logoMark
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 23)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 18)
        } else {
            brand
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
    }

    private var brand: some View {
        HStack(alignment: .center, spacing: 9) {
            logoMark
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 31)

            VStack(alignment: .leading, spacing: 2) {
                Text("ASTERION")
                    .font(.asterionDisplay(16, weight: .semibold))
                    .tracking(2.3)
                    .foregroundStyle(Color.asterionSidebarText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text("Stories that transcend time.")
                    .font(.caption2)
                    .foregroundStyle(Color.asterionSidebarMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var compactToggle: some View {
        Button {
            toggleCompactSidebar()
        } label: {
            Image(systemName: isCompact ? "chevron.right" : "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.asterionSidebarMuted)
                .frame(width: 22, height: 22)
                .background(Color.asterionSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.asterionBorder)
                }
        }
        .buttonStyle(AsterionPressButtonStyle())
        .help(isCompact ? "Expand Sidebar" : "Compact Sidebar")
        .accessibilityLabel(isCompact ? "Expand Sidebar" : "Compact Sidebar")
    }

    private func toggleCompactSidebar() {
        let compacting = !isCompact
        isCompact = compacting

        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            guard !window.styleMask.contains(.fullScreen), !window.isZoomed else { return }
            let delta: CGFloat = 156
            var frame = window.frame
            frame.origin.x += compacting ? delta : -delta
            frame.size.width += compacting ? -delta : delta
            if let screen = window.screen {
                frame = window.constrainFrameRect(frame, to: screen)
            }
            window.setFrame(frame, display: true, animate: !reduceMotion)
        }
    }

    private var logoMark: Image {
        guard let url = Bundle.module.url(
            forResource: "AsterionMark",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing Asterion logo mark")
        }
        return Image(nsImage: image)
    }
}
