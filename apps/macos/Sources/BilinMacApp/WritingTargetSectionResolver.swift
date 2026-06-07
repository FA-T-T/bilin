import BilinWorkspaceKit

enum WritingTargetSectionResolver {
    static let appendToEndTitle = "Append to end"

    static func targetPreference(
        for location: WritingProjectLocation,
        selectedTitle: String? = nil
    ) -> String {
        if let selectedTitle = normalizedSelectedTitle(selectedTitle) {
            if selectedTitle == appendToEndTitle {
                return appendToEndTitle
            }
            if let selected = location.sectionAnchors.first(where: { $0.title == selectedTitle }) {
                return selected.title
            }
        }
        return location.sectionAnchors.first?.title ?? appendToEndTitle
    }

    static func displayName(
        for location: WritingProjectLocation,
        selectedTitle: String? = nil
    ) -> String {
        targetPreference(for: location, selectedTitle: selectedTitle)
    }

    static func options(for location: WritingProjectLocation) -> [String] {
        var seen: Set<String> = []
        var options: [String] = []
        for section in location.sectionAnchors where !seen.contains(section.title) {
            options.append(section.title)
            seen.insert(section.title)
        }
        if !seen.contains(appendToEndTitle) {
            options.append(appendToEndTitle)
        }
        return options
    }

    private static func normalizedSelectedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
