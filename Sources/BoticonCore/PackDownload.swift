import Foundation

/// State is confined to URLSession's serial delegate queue. Cancellation uses URLSession's thread-safe API.
final class PackDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    private var failure: Error?
    private var redirects = 0
    private var file: URL?
    private var handle: FileHandle?
    private var received = 0

    init(configuration: URLSessionConfiguration = .ephemeral) {
        super.init()
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func fetch(_ url: URL) async throws -> URL {
        do {
            _ = try PackURL.validated(url.absoluteString)
            try Task.checkCancellation()
        } catch { session.invalidateAndCancel(); throw error }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                var request = URLRequest(url: url)
                request.setValue("application/zip, application/octet-stream", forHTTPHeaderField: "Accept")
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                session.dataTask(with: request).resume()
            }
        } onCancel: { self.session.invalidateAndCancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 5, let url = request.url,
              (try? PackURL.validated(url.absoluteString)) != nil else {
            failure = PackError.invalid("安全なHTTPSの配布先へ移動できませんでした。")
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let url = response.url, (try? PackURL.validated(url.absoluteString)) != nil,
                  response.expectedContentLength <= WallpaperPack.maximumArchiveBytes else {
                throw PackError.invalid("取得先の応答が不正か、容量上限（256MiB）を超えています。")
            }
            let owned = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bwp.zip")
            guard FileManager.default.createFile(atPath: owned.path, contents: nil) else {
                throw PackError.invalid("ダウンロード用のファイルを作成できませんでした。")
            }
            file = owned
            handle = try FileHandle(forWritingTo: owned)
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard failure == nil, let handle, received + data.count <= WallpaperPack.maximumArchiveBytes else {
                throw PackError.invalid("壁紙パックの上限（256MiB）を超えました。")
            }
            try handle.write(contentsOf: data)
            received += data.count
        } catch { failure = error; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        do {
            try handle?.close()
            handle = nil
            if let error = failure ?? error { throw error }
            guard received > 0, let file else { throw PackError.invalid("空のファイルは追加できません。") }
            continuation?.resume(returning: file)
        } catch {
            if let file { try? FileManager.default.removeItem(at: file) }
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}
