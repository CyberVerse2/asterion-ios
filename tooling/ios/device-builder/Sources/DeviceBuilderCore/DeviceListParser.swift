import Foundation

public enum DeviceListParser {
    public static func parseDevicectlJSON(_ data: Data) throws -> [AppleDevice] {
        let payload = try JSONDecoder().decode(DeviceListPayload.self, from: data)
        return payload.result.devices.compactMap(Self.device(from:))
    }

    public static func parseXCTraceList(_ text: String) -> [AppleDevice] {
        var section = XCTraceSection.none
        var devices: [AppleDevice] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("==") {
                section = XCTraceSection(header: line)
                continue
            }
            guard section.includesPhysicalDevices, !line.isEmpty else { continue }
            guard let device = parseXCTraceLine(line, available: section == .devices) else { continue }
            devices.append(device)
        }

        return devices
    }

    private static func device(from raw: DeviceListPayload.RawDevice) -> AppleDevice? {
        let hardware = raw.hardwareProperties
        guard hardware?.reality == "physical" else { return nil }
        guard hardware?.deviceType == "iPhone" || hardware?.deviceType == "iPad" else { return nil }

        let udid = hardware?.udid.flatMap { DeviceIDFormat.isHardwareUDID($0) ? $0 : nil }
            ?? raw.connectionProperties?.potentialHostnames?.compactMap(hardwareUDID(inHostname:)).first

        return AppleDevice(
            name: raw.deviceProperties?.name ?? hardware?.marketingName ?? "Apple Device",
            model: hardware?.marketingName ?? hardware?.productType ?? hardware?.deviceType ?? "iOS device",
            hardwareUDID: udid,
            coreDeviceID: raw.identifier,
            osVersion: raw.deviceProperties?.osVersionNumber,
            transport: raw.connectionProperties?.transportType,
            pairingState: raw.connectionProperties?.pairingState,
            tunnelState: raw.connectionProperties?.tunnelState,
            isAvailable: (raw.connectionProperties?.pairingState == "paired"),
            source: .devicectl
        )
    }

    private static func hardwareUDID(inHostname hostname: String) -> String? {
        let prefix = hostname.split(separator: ".", maxSplits: 1).first.map(String.init) ?? hostname
        return DeviceIDFormat.isHardwareUDID(prefix) ? prefix : nil
    }

    private static func parseXCTraceLine(_ line: String, available: Bool) -> AppleDevice? {
        guard let udidMatch = line.wholeMatch(of: /^(.*) \(([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})\)$/) else {
            return nil
        }

        var remainder = String(udidMatch.1).trimmingCharacters(in: .whitespaces)
        var osVersion: String?
        if let osMatch = remainder.wholeMatch(of: /^(.*) \(([0-9]+(?:\.[0-9]+)*)\)$/) {
            remainder = String(osMatch.1).trimmingCharacters(in: .whitespaces)
            osVersion = String(osMatch.2)
        }

        let lowered = remainder.lowercased()
        if lowered.contains("watch") || lowered.contains("macbook") || lowered.contains("mac ")
            || lowered.contains("apple tv") || lowered.hasSuffix(" tv") {
            return nil
        }

        return AppleDevice(
            name: remainder,
            model: remainder,
            hardwareUDID: String(udidMatch.2),
            osVersion: osVersion,
            isAvailable: available,
            source: .xctrace
        )
    }
}

private enum XCTraceSection {
    case none
    case devices
    case offline
    case simulators

    init(header: String) {
        let lowered = header.lowercased()
        if lowered.contains("simulator") {
            self = .simulators
        } else if lowered.contains("offline") {
            self = .offline
        } else if lowered.contains("devices") {
            self = .devices
        } else {
            self = .none
        }
    }

    var includesPhysicalDevices: Bool {
        switch self {
        case .devices, .offline:
            true
        case .none, .simulators:
            false
        }
    }
}

private struct DeviceListPayload: Decodable {
    var result: Result

    struct Result: Decodable {
        var devices: [RawDevice]
    }

    struct RawDevice: Decodable {
        var identifier: String?
        var deviceProperties: DeviceProperties?
        var hardwareProperties: HardwareProperties?
        var connectionProperties: ConnectionProperties?
    }

    struct DeviceProperties: Decodable {
        var name: String?
        var osVersionNumber: String?
    }

    struct HardwareProperties: Decodable {
        var deviceType: String?
        var marketingName: String?
        var productType: String?
        var platform: String?
        var reality: String?
        var udid: String?
    }

    struct ConnectionProperties: Decodable {
        var pairingState: String?
        var potentialHostnames: [String]?
        var transportType: String?
        var tunnelState: String?
    }
}
