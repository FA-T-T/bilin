import Foundation

public enum ReaderFixtureError: Error, Equatable, Sendable {
    case missingFixture(String)
}

public struct ReaderFixtureLoader: Sendable {
    public init() {}

    public func loadFixture(named name: String, bundle: Bundle) throws -> ReaderFixture {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw ReaderFixtureError.missingFixture(name)
        }
        return try loadFixture(from: url)
    }

    public func loadFixture(from url: URL) throws -> ReaderFixture {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ReaderFixture.self, from: data)
    }
}
