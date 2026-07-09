import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand

            VStack(spacing: 8) {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.body.weight(.medium))
                            .foregroundStyle(selection == section ? Color.asterionGold : Color.asterionText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11)
                            .background(
                                selection == section ? Color.asterionAccentSoft : .clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

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
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.name)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.asterionText)
                            .lineLimit(1)
                        Text("Reader")
                            .font(.caption2)
                            .foregroundStyle(Color.asterionGold)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .background(Color.asterionSidebar)
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "sparkle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.asterionGold)
                Text("ASTERION")
                    .font(.asterionSerif(21, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(Color.asterionText)
            }
            Text("Stories that transcend time.")
                .font(.caption)
                .foregroundStyle(Color.asterionMuted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 25)
        .padding(.bottom, 30)
    }
}
