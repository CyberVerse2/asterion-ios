import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            VStack(spacing: 5) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                            Text(section.title)
                                .font(.asterionDisplay(14, weight: selection == section ? .semibold : .medium))
                            Spacer()
                        }
                            .foregroundStyle(selection == section ? Color.asterionText : Color.asterionSidebarMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                if selection == section {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.asterionSidebarSelection)
                                }
                            }
                            .overlay(alignment: .leading) {
                                if selection == section {
                                    Capsule()
                                        .fill(Color.asterionSidebarAccent)
                                        .frame(width: 3, height: 22)
                                        .padding(.leading, 3)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selection == section ? Color.asterionBorder : .clear)
                            }
                            .animation(
                                reduceMotion ? nil : AsterionMotion.navigation,
                                value: selection == section
                            )
                    }
                    .buttonStyle(AsterionPressButtonStyle())
                }
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 20)

            if let user = model.signedInUser {
                HStack(spacing: 10) {
                    AsyncImage(url: user.imageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundStyle(Color.asterionMuted)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())

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
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .overlay(alignment: .top) {
                    Divider().overlay(Color.asterionBorder)
                }
            }
        }
        .background(Color.asterionSidebar)
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
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 23)
        .padding(.bottom, 25)
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
