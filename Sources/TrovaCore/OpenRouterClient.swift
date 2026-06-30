import Foundation

public enum LLMError: Error, CustomStringConvertible {
    case badResponse(String)
    public var description: String {
        switch self { case let .badResponse(s): return "LLM yanıtı çözümlenemedi: \(s.prefix(400))" }
    }
}

public struct ChatMessage: Sendable {
    public let role: String      // "system" | "user" | "assistant"
    public let content: String
    public init(role: String, content: String) { self.role = role; self.content = content }
}

public struct LLMConfig: Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public init(baseURL: URL, apiKey: String, model: String) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model
    }
}

/// OpenRouter (OpenAI-uyumlu `/chat/completions`) sohbet istemcisi.
public final class OpenRouterClient: @unchecked Sendable {
    public let model: String
    private let config: LLMConfig
    private let session: URLSession

    public init(config: LLMConfig, session: URLSession = .shared) {
        self.config = config
        self.model = config.model
        self.session = session
    }

    public func complete(messages: [ChatMessage], temperature: Double = 0.2) throws -> String {
        let payload: [String: Any] = [
            "model": config.model,
            "temperature": temperature,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        let data = try SyncHTTP.postJSON(
            session: session,
            url: config.baseURL.appendingPathComponent("chat/completions"),
            bearer: config.apiKey,
            body: try JSONSerialization.data(withJSONObject: payload))

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        if let error = root["error"] { throw LLMError.badResponse("\(error)") }
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }

    // MARK: - Araç çağırma (function calling) — ajan döngüsü için

    public struct ToolCall {
        public let id: String
        public let name: String
        public let arguments: String   // JSON string
    }

    public struct ChatResponse {
        public let content: String?
        public let toolCalls: [ToolCall]
        public let rawAssistantMessage: [String: Any]   // tool_calls'lı asistan mesajı, aynen geri eklenir
    }

    /// Ham mesaj sözlükleriyle (tool/assistant rolleri dahil) sohbet; OpenAI-uyumlu `tools`.
    public func chatRaw(messages: [[String: Any]], tools: [[String: Any]]? = nil,
                        temperature: Double = 0.2) throws -> ChatResponse {
        var payload: [String: Any] = [
            "model": config.model, "temperature": temperature, "messages": messages,
        ]
        if let tools, !tools.isEmpty {
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        }
        let data = try SyncHTTP.postJSON(
            session: session, url: config.baseURL.appendingPathComponent("chat/completions"),
            bearer: config.apiKey, body: try JSONSerialization.data(withJSONObject: payload))

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        if let error = root["error"] { throw LLMError.badResponse("\(error)") }
        guard let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw LLMError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }

        var calls: [ToolCall] = []
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String else { continue }
                calls.append(ToolCall(id: id, name: name,
                                      arguments: function["arguments"] as? String ?? "{}"))
            }
        }
        return ChatResponse(content: message["content"] as? String,
                            toolCalls: calls, rawAssistantMessage: message)
    }

    // MARK: - Streaming (tek-atışlık; brifing/özet için canlı çıktı)

    /// Bir SSE satırının ayrıştırılmış sonucu.
    enum StreamEvent: Equatable { case content(String), done, ignore }

    /// `data: {json}` / `data: [DONE]` satırından içerik parçasını çıkarır. Saf — test edilebilir.
    static func streamEvent(fromLine line: String) -> StreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return .ignore }
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String, !content.isEmpty else { return .ignore }
        return .content(content)
    }

    /// Yanıtı SSE ile akıtır; her içerik parçası için sırayla `onDelta` beklenir, tüm metin döner.
    /// `onDelta` async olduğundan döngü her parçayı bekler → sıra korunur (UI'da ana aktöre güvenli hop).
    /// Araç çağırma YOK — yalnızca tek-atışlık üretim (brifing, konu özeti) içindir.
    public func completeStreaming(messages: [ChatMessage], temperature: Double = 0.2,
                                  onDelta: @Sendable @escaping (String) async -> Void) async throws -> String {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "model": config.model, "temperature": temperature, "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var body = ""
            for try await line in bytes.lines { body += line }
            throw LLMError.badResponse("HTTP \(http.statusCode): \(body)")
        }

        var full = ""
        for try await line in bytes.lines {
            switch Self.streamEvent(fromLine: line) {
            case .content(let fragment): full += fragment; await onDelta(fragment)
            case .done: return full
            case .ignore: continue
            }
        }
        return full
    }

    public static func fromEnvironment(
        _ env: [String: String] = ProcessInfo.processInfo.environment
    ) -> OpenRouterClient? {
        guard let key = env["OPENROUTER_API_KEY"] ?? env["EIDX_LLM_API_KEY"] else { return nil }
        let base = env["EIDX_LLM_BASE_URL"] ?? "https://openrouter.ai/api/v1"
        let model = env["EIDX_LLM_MODEL"] ?? "anthropic/claude-sonnet-4.6"
        guard let url = URL(string: base) else { return nil }
        return OpenRouterClient(config: .init(baseURL: url, apiKey: key, model: model))
    }
}
