import XCTest
@testable import BoticonCore

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let path = url.path
        let status = path == "/missing" ? 404 : 200
        let headers = path == "/oversized" ? ["Content-Length": "999999999"] : [:]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "/chunks" {
            client?.urlProtocol(self, didLoad: Data("first".utf8))
            client?.urlProtocol(self, didLoad: Data("second".utf8))
        }
        if path != "/slow" { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {}
}

final class PackDownloadTests: XCTestCase {
    private static func fetch(_ path: String) async throws -> URL {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return try await PackDownload(configuration: configuration).fetch(URL(string: "https://example.com" + path)!)
    }

    func testChunksAreWrittenToOwnedTemporaryFile() async throws {
        let url = try await Self.fetch("/chunks")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "firstsecond")
    }

    func testHTTPFailureEmptyAndOversizedResponseAreRejected() async throws {
        for path in ["/missing", "/empty", "/oversized"] {
            do { _ = try await Self.fetch(path); XCTFail("Accepted \(path)") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }

    func testInFlightCancellationStopsDownload() async throws {
        let task = Task { try await Self.fetch("/slow") }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertEqual((error as NSError).code, NSURLErrorCancelled) }
    }
}
