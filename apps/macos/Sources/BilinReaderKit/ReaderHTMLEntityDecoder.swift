import Foundation

enum ReaderHTMLEntityDecoder {
    private static let namedEntities: [String: String] = [
        "amp": "&",
        "apos": "'",
        "gt": ">",
        "lt": "<",
        "mdash": "—",
        "ndash": "–",
        "nbsp": " ",
        "quot": "\""
    ]

    static func decode(_ value: String) -> String {
        guard value.contains("&") else { return value }

        var output = ""
        var cursor = value.startIndex
        while cursor < value.endIndex {
            guard value[cursor] == "&",
                  let semicolon = value[cursor...].firstIndex(of: ";")
            else {
                output.append(value[cursor])
                cursor = value.index(after: cursor)
                continue
            }

            let entityStart = value.index(after: cursor)
            let entity = String(value[entityStart..<semicolon])
            if let decoded = decodedEntity(entity) {
                output.append(decoded)
            } else {
                output.append(String(value[cursor...semicolon]))
            }
            cursor = value.index(after: semicolon)
        }
        return output
    }

    private static func decodedEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return decodedUnicodeScalar(String(entity.dropFirst(2)), radix: 16)
        }
        if entity.hasPrefix("#") {
            return decodedUnicodeScalar(String(entity.dropFirst()), radix: 10)
        }
        return namedEntities[entity.lowercased()]
    }

    private static func decodedUnicodeScalar(_ value: String, radix: Int) -> String? {
        guard let scalarValue = UInt32(value, radix: radix),
              let scalar = UnicodeScalar(scalarValue)
        else {
            return nil
        }
        return String(Character(scalar))
    }
}
