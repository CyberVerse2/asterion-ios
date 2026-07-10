import AppKit
import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppSection

    private var listSelection: Binding<AppSection?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 12)

            List(selection: listSelection) {
                Section("Browse") {
                    ForEach(AppSection.allCases, id: \.self) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                            .help(section.title)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Asterion")
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
                    .lineLimit(1)
                Text("Stories that transcend time.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
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
