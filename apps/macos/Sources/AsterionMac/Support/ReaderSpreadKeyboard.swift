import AppKit

enum ReaderSpreadKeyboardCommand: Equatable {
    case turn(Int)

    static func resolve(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Self? {
        let blocking = modifiers.intersection([.command, .option, .control, .shift])
        guard blocking.isEmpty else { return nil }
        switch keyCode {
        case 123, 116: return .turn(-1)
        case 124, 121, 49: return .turn(1)
        default: return nil
        }
    }
}
