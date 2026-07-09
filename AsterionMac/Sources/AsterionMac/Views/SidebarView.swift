import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: AppSection

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            if let user = model.signedInUser {
                Section("Signed in") {
                    Label(user.name, systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ASTERION")
                    .font(.asterionSerif(24, weight: .semibold))
                    .tracking(3)
                    .foregroundStyle(Color.asterionText)
                Text("A quiet place for long stories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
    }
}
