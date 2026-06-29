import Foundation

enum HTTPClientError: Error, CustomStringConvertible {
    case http(status: Int, body: String)
    case transport(String)

    var description: String {
        switch self {
        case let .http(status, body): return "HTTP \(status): \(body.prefix(400))"
        case let .transport(message): return "Ağ hatası: \(message)"
        }
    }
}

/// Tamamlanma kapanışından senkron koda sonuç taşımak için Sendable kutu.
/// `DispatchSemaphore.wait()` happens-before garantisi sağladığından erişim güvenlidir.
private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// CLI için senkron HTTP POST (DispatchSemaphore ile bekler). UI runloop'u olmadığından güvenli.
enum SyncHTTP {
    static func postJSON(session: URLSession, url: URL, bearer: String, body: Data) throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<Result<Data, Error>>()
        session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                box.value = .failure(HTTPClientError.transport(error.localizedDescription)); return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                box.value = .failure(HTTPClientError.http(
                    status: http.statusCode, body: String(data: data ?? Data(), encoding: .utf8) ?? ""))
                return
            }
            box.value = .success(data ?? Data())
        }.resume()
        semaphore.wait()
        return try box.value!.get()
    }
}
