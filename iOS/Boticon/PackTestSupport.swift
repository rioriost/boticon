#if DEBUG && targetEnvironment(simulator)
import Foundation

/// UI tests supply invented archive bytes at launch. This transport is absent from Release builds.
final class PackFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "fixture.example.com" && ProcessInfo.processInfo.environment["BOTICON_PACK_FIXTURE_BASE64"] != nil
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let value = ProcessInfo.processInfo.environment["BOTICON_PACK_FIXTURE_BASE64"], value.count < 64000,
              let data = Data(base64Encoded: value), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                            headerFields: ["Content-Length": String(data.count)]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
