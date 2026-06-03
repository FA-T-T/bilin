import Foundation

public enum ZoteroArXivExtractor {
    public static func extract(from fields: [(name: String, value: String?)]) -> ZoteroArXivMetadata? {
        for field in fields {
            guard let value = field.value, let match = firstMatch(in: value) else {
                continue
            }
            return ZoteroArXivMetadata(
                identifier: match.identifier,
                version: match.version,
                sourceField: field.name
            )
        }
        return nil
    }

    private static func firstMatch(in value: String) -> (identifier: String, version: String?)? {
        let patterns = [
            #"(?i)arxiv:\s*([a-z]+(?:-[a-z]+)?/\d{7}|\d{4}\.\d{4,5})(v\d+)?"#,
            #"(?i)arxiv\.org/(?:abs|pdf)/([a-z]+(?:-[a-z]+)?/\d{7}|\d{4}\.\d{4,5})(v\d+)?(?:\.pdf)?"#
        ]
        for pattern in patterns {
            guard
                let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(
                    in: value,
                    range: NSRange(value.startIndex..<value.endIndex, in: value)
                ),
                let idRange = Range(match.range(at: 1), in: value)
            else {
                continue
            }
            let identifier = String(value[idRange])
            let version: String?
            if match.range(at: 2).location != NSNotFound, let versionRange = Range(match.range(at: 2), in: value) {
                version = String(value[versionRange])
            } else {
                version = nil
            }
            return (identifier, version)
        }
        return nil
    }
}
