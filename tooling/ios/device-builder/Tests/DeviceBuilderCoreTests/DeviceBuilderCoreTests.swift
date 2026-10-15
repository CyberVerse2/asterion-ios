import DeviceBuilderCore
import Foundation
import Testing

struct DeviceListParserTests {
    @Test func parsesPhysicalPhonesAndPadsAndSkipsWatchAndSimulator() throws {
        let url = try #require(Bundle.module.url(forResource: "devices", withExtension: "json", subdirectory: "Fixtures"))
        let devices = try DeviceListParser.parseDevicectlJSON(Data(contentsOf: url))

        #expect(devices.map(\.title) == [
            "iPad Pro 13-inch (M4)",
            "iPhone 17 Pro Max",
        ])
        #expect(devices[0].name == "iPhone")
        #expect(devices[0].buildDestinationID == "00008132-001A79013E7A801C")
        #expect(devices[0].coreDeviceID == "972D9DC3-E7DD-5526-B75E-6271926A5346")
        #expect(devices[1].buildDestinationID == "00008150-00110911366A401C")
        #expect(devices.allSatisfy { $0.hardwareUDID != nil })
    }

    @Test func xctraceSkipsSimulatorsWatchAndMac() {
        let text = """
        == Devices ==
        Celestine’s MacBook Pro (C23013D3-E2B5-5F1F-B894-A1E7874B7B8C)

        == Devices Offline ==
        Celestine’s Apple Watch (26.1) (00008310-000B4DAC3E40E01E)
        iPhone (2) (26.6.1) (00008150-00110911366A401C)
        iPhone (26.6) (00008132-001A79013E7A801C)

        == Simulators ==
        iPhone 17 Simulator (26.2) (E4E4BB00-BFF7-4A6F-9F3A-57BB10EC991E)
        """

        let devices = DeviceListParser.parseXCTraceList(text)
        #expect(devices.map(\.buildDestinationID) == [
            "00008150-00110911366A401C",
            "00008132-001A79013E7A801C",
        ])
        #expect(devices[0].name == "iPhone (2)")
        #expect(devices[0].osVersion == "26.6.1")
        #expect(devices[1].name == "iPhone")
        #expect(devices.allSatisfy { !$0.isAvailable })
    }
}

struct BuildPlanTests {
    @Test func prefersHardwareUDIDAndPreservesProjectSigning() {
        let device = AppleDevice(
            name: "iPhone",
            model: "iPad Pro 13-inch (M4)",
            hardwareUDID: "00008132-001A79013E7A801C",
            coreDeviceID: "972D9DC3-E7DD-5526-B75E-6271926A5346",
            source: .devicectl
        )
        let repo = URL(fileURLWithPath: "/Users/thecyberverse/Code/Asterion")
        let plan = BuildPlan(repoRoot: repo, device: device)

        #expect(plan.xcodebuildArguments.contains("-destination"))
        #expect(plan.xcodebuildArguments.contains("id=00008132-001A79013E7A801C"))
        #expect(!plan.xcodebuildArguments.contains { $0.contains("972D9DC3") })
        #expect(plan.xcodebuildArguments.contains("-allowProvisioningUpdates"))
        #expect(plan.xcodebuildArguments.contains("-allowProvisioningDeviceRegistration"))
        #expect(!plan.xcodebuildArguments.contains { $0.hasPrefix("CODE_SIGN_ENTITLEMENTS=") })
        #expect(!plan.xcodebuildArguments.contains { $0.hasPrefix("DEVELOPMENT_TEAM=") })
        #expect(plan.derivedDataPath.path.hasSuffix("/.artifacts/ios/device/00008132-001A79013E7A801C"))
        #expect(plan.installArguments.contains("00008132-001A79013E7A801C"))
        #expect(plan.launchArguments.contains("cyberverse.Asterion"))
    }

    @Test func hardwareUDIDFormat() {
        #expect(DeviceIDFormat.isHardwareUDID("00008150-00110911366A401C"))
        #expect(!DeviceIDFormat.isHardwareUDID("C9363699-1B89-5FAE-AD8E-A73CE230CC85"))
    }
}

struct RepoRootTests {
    @Test func recognizesThisWorkspace() {
        let repo = URL(fileURLWithPath: "/Users/thecyberverse/Code/Asterion")
        #expect(AsterionRepo.containsProject(at: repo))
        #expect(!AsterionRepo.containsProject(at: repo.appending(path: "apps/ios")))
    }
}
