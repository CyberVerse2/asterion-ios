import Foundation

struct WebVTTCue: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

enum WebVTTParserError: LocalizedError {
    case unreadableText
    case invalidDocument
    case invalidTiming(String)

    var errorDescription: String? {
        switch self {
        case .unreadableText:
            "The downloaded subtitle file is not valid UTF-8 text."
        case .invalidDocument:
            "The downloaded subtitle file is not a valid WebVTT document."
        case .invalidTiming(let timing):
            "The downloaded subtitle file contains an invalid cue time: \(timing)"
        }
    }
}

enum WebVTTParser {
    static func parse(fileURL: URL) throws -> [WebVTTCue] {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard var document = String(data: data, encoding: .utf8) else {
            throw WebVTTParserError.unreadableText
        }

        document = document
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if document.first == "\u{feff}" {
            document.removeFirst()
        }
        guard document.hasPrefix("WEBVTT") else {
            throw WebVTTParserError.invalidDocument
        }

        var cues: [WebVTTCue] = []
        for block in document.components(separatedBy: "\n\n").dropFirst() {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            guard let firstContentLine = lines.first(where: {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else {
                continue
            }

            let directive = firstContentLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            if directive.hasPrefix("NOTE")
                || directive == "STYLE"
                || directive == "REGION" {
                continue
            }

            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }
            let timing = lines[timingIndex]
            let components = timing.components(separatedBy: "-->")
            guard components.count == 2 else {
                throw WebVTTParserError.invalidTiming(timing)
            }

            let startToken = components[0].trimmingCharacters(in: .whitespaces)
            let endToken = components[1]
                .trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: \Character.isWhitespace)
                .first
                .map(String.init) ?? ""
            guard let startTime = parseTime(startToken),
                  let endTime = parseTime(endToken) else {
                throw WebVTTParserError.invalidTiming(timing)
            }
            if endTime == startTime {
                continue
            }
            guard endTime > startTime else {
                throw WebVTTParserError.invalidTiming(timing)
            }

            let cueText = lines
                .dropFirst(timingIndex + 1)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayText = plainText(from: cueText)
            guard !displayText.isEmpty else { continue }
            cues.append(
                WebVTTCue(
                    startTime: startTime,
                    endTime: endTime,
                    text: displayText
                )
            )
        }

        return cues.sorted { lhs, rhs in
            if lhs.startTime == rhs.startTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.startTime < rhs.startTime
        }
    }

    static func caption(at time: TimeInterval, in cues: [WebVTTCue]) -> String? {
        let activeText = cues.lazy
            .filter { $0.startTime <= time && time < $0.endTime }
            .map(\.text)
            .joined(separator: "\n")
        return activeText.isEmpty ? nil : activeText
    }

    private static func parseTime(_ token: String) -> TimeInterval? {
        let parts = token
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              let seconds = Double(parts[parts.count - 1]),
              let minutes = Double(parts[parts.count - 2]) else {
            return nil
        }

        let hours: Double
        if parts.count == 3 {
            guard let parsedHours = Double(parts[0]) else { return nil }
            hours = parsedHours
        } else {
            hours = 0
        }
        guard hours >= 0,
              minutes >= 0,
              minutes < 60,
              seconds >= 0,
              seconds < 60 else {
            return nil
        }
        return hours * 3_600 + minutes * 60 + seconds
    }

    private static func plainText(from cueText: String) -> String {
        let normalized = cueText
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        var result = ""
        var isInsideTag = false
        for character in normalized {
            if character == "<" {
                isInsideTag = true
            } else if character == ">", isInsideTag {
                isInsideTag = false
            } else if !isInsideTag {
                result.append(character)
            }
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
