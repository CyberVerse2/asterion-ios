import Foundation

public struct AppleDevice: Identifiable, Hashable, Sendable {
    public var name: String
    public var model: String
    public var hardwareUDID: String?
    public var coreDeviceID: String?
    public var osVersion: String?
    public var transport: String?
    public var pairingState: String?
    public var tunnelState: String?
    public var isAvailable: Bool
    public var source: Source

    public enum Source: String, Sendable {
        case devicectl
        case xctrace
    }

    public init(
        name: String,
        model: String,
        hardwareUDID: String? = nil,
        coreDeviceID: String? = nil,
        osVersion: String? = nil,
        transport: String? = nil,
        pairingState: String? = nil,
        tunnelState: String? = nil,
        isAvailable: Bool = true,
        source: Source
    ) {
        self.name = name
        self.model = model
        self.hardwareUDID = hardwareUDID
        self.coreDeviceID = coreDeviceID
        self.osVersion = osVersion
        self.transport = transport
        self.pairingState = pairingState
        self.tunnelState = tunnelState
        self.isAvailable = isAvailable
        self.source = source
    }

    public var id: String {
        buildDestinationID
    }

    /// `xcodebuild -destination id=` wants the hardware UDID when it exists.
    public var buildDestinationID: String {
        hardwareUDID ?? coreDeviceID ?? name
    }

    public var installDeviceID: String {
        hardwareUDID ?? coreDeviceID ?? name
    }

    public var title: String {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty { return trimmedModel }
        return name
    }

    public var subtitle: String {
        var parts: [String] = []
        if name != title { parts.append(name) }
        if let osVersion, !osVersion.isEmpty { parts.append(osVersion) }
        if let transport, !transport.isEmpty { parts.append(transport) }
        if let pairingState, !pairingState.isEmpty { parts.append(pairingState) }
        if !isAvailable { parts.append("offline") }
        return parts.joined(separator: " · ")
    }
}

public enum DeviceIDFormat {
    public static func isHardwareUDID(_ value: String) -> Bool {
        value.wholeMatch(of: /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$/) != nil
    }
}
