import SwiftUI

struct SettingsView: View {
    @AppStorage("readerFontSize") private var fontSize = 19.0
    @AppStorage("readerLineSpacing") private var lineSpacing = 8.0
    @AppStorage("readerColumnWidth") private var columnWidth = 640.0

    var body: some View {
        Form {
            Section("Reader") {
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $fontSize, in: 14...30, step: 1)
                            .frame(width: 220)
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Line spacing") {
                    Slider(value: $lineSpacing, in: 2...16, step: 1)
                        .frame(width: 220)
                }
                LabeledContent("Reading width") {
                    Slider(value: $columnWidth, in: 520...900, step: 20)
                        .frame(width: 220)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 260)
    }
}
