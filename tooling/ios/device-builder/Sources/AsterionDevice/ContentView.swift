import AppKit
import DeviceBuilderCore
import SwiftUI

struct ContentView: View {
    @Bindable var controller: BuildController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            repoRow
            deviceList
            actions
            logPane
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 500)
        .background(Color(red: 0.165, green: 0.165, blue: 0.185))
        .preferredColorScheme(.dark)
        .task {
            await controller.refreshDevices()
        }
        .onChange(of: controller.selectedID) {
            controller.persistSelection()
        }
        .onChange(of: controller.repoPath) {
            controller.persistRepoPath()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Asterion Device")
                    .font(.system(size: 32, weight: .medium, design: .serif))
                Text("Build, install, and launch cyberverse.Asterion")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusChip
        }
    }

    private var statusChip: some View {
        Text(controller.status.banner)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.18), in: Capsule())
            .foregroundStyle(statusColor)
            .lineLimit(2)
            .frame(maxWidth: 260, alignment: .trailing)
    }

    private var statusColor: Color {
        switch controller.status {
        case .idle:
            .secondary
        case .running:
            Color(red: 0.83, green: 0.56, blue: 0)
        case .succeeded:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }

    private var repoRow: some View {
        HStack(spacing: 8) {
            Text("Repo")
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            TextField("Asterion repository", text: $controller.repoPath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            Button("Choose…") {
                chooseRepo()
            }
            .disabled(controller.status.isRunning)
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Devices")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await controller.refreshDevices() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(controller.isRefreshing || controller.status.isRunning)
                .keyboardShortcut("r", modifiers: .command)
            }

            if let listError = controller.listError, controller.devices.isEmpty {
                Text(listError)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                    .padding(12)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            } else {
                List(controller.devices, selection: $controller.selectedID) { device in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.title)
                            .font(.system(size: 14, weight: .semibold))
                        if !device.subtitle.isEmpty {
                            Text(device.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(device.buildDestinationID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .tag(device.id)
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .frame(minHeight: 140, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await controller.build() }
            } label: {
                Label("Build, install, and launch", systemImage: "iphone.and.arrow.forward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.canBuild)
            .keyboardShortcut("b", modifiers: .command)

            Button("Cancel", role: .destructive) {
                controller.cancel()
            }
            .controlSize(.large)
            .disabled(!controller.status.isRunning)
            .keyboardShortcut(".", modifiers: .command)
        }
    }

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log")
                .font(.headline)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(controller.log.isEmpty ? "Build output will appear here." : controller.log)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(controller.log.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("log-end")
                }
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: controller.log) {
                    proxy.scrollTo("log-end", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = controller.repoURL
        panel.prompt = "Use Folder"
        panel.message = "Choose the Asterion repository root (the folder that contains apps/ios)."
        if panel.runModal() == .OK, let url = panel.url {
            controller.repoPath = url.path
            controller.persistRepoPath()
        }
    }
}
