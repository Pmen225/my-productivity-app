import Foundation

/// One message in the chat sent to the provider (not the SwiftData model).
public struct AssistantChatMessage: Sendable {
    public enum Role: String, Sendable { case user, assistant, tool }
    public let role: Role
    public let text: String
    public let toolCallID: String?
    public let toolCalls: [AssistantToolCallRequest]

    public init(role: Role, text: String, toolCallID: String? = nil, toolCalls: [AssistantToolCallRequest] = []) {
        self.role = role
        self.text = text
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }
}

/// A tool the assistant may call, described once and re-wrapped per provider.
public struct AssistantToolDefinition: Sendable {
    public let name: String
    public let description: String
    /// A JSON Schema object string, e.g. `{"type":"object","properties":{...},"required":[...]}`.
    public let parametersSchemaJSON: String

    public init(name: String, description: String, parametersSchemaJSON: String) {
        self.name = name
        self.description = description
        self.parametersSchemaJSON = parametersSchemaJSON
    }
}

/// A tool call the model asked to make.
public struct AssistantToolCallRequest: Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String
}

/// What came back after a full (non-streaming or completed-stream) turn.
public struct AssistantTurn: Sendable {
    public let text: String
    public let toolCalls: [AssistantToolCallRequest]
}

/// User-facing failure. Messages are pre-redacted so a stray key never renders.
public enum AssistantServiceError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse
    case http(status: Int, body: String, retryAfter: TimeInterval? = nil)
    case network(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key saved yet. Add one in Settings → Assistant."
        case .invalidResponse:
            return "The assistant sent back something Flowmap couldn't read."
        case .http(let status, let body, _):
            return KeychainService.redact("The assistant service returned an error (\(status)): \(body)")
        case .network(let message):
            return KeychainService.redact("Couldn't reach the assistant: \(message)")
        case .cancelled:
            return "Cancelled."
        }
    }
}

/// Talks to Anthropic or OpenAI's chat APIs. Provider-agnostic on the outside;
/// this is the only file that knows either wire format.
///
/// Streaming is used where practical (`streamSend`); a plain non-streaming
/// call (`send`) is the reliable fallback used if the stream can't be opened.
@MainActor
public struct AssistantService {
    public let provider: AssistantProvider
    public let model: String

    public init(provider: AssistantProvider, model: String) {
        self.provider = provider
        self.model = model.isEmpty ? provider.defaultModel : model
    }

    private var apiKey: String? { KeychainService.get(account: provider.keychainAccount) }

    /// Streams tokens via `onToken`, resolving to the completed turn. Falls
    /// back to a single non-streaming request if the stream can't be opened
    /// (e.g. the transport refuses `bytes(for:)`).
    public func streamSend(
        system: String,
        history: [AssistantChatMessage],
        tools: [AssistantToolDefinition],
        onToken: @escaping (String) -> Void
    ) async -> Result<AssistantTurn, AssistantServiceError> {
        guard let apiKey, !apiKey.isEmpty else { return .failure(.missingAPIKey) }
        do {
            switch provider {
            case .anthropic:
                return .success(try await streamAnthropic(system: system, history: history, tools: tools, apiKey: apiKey, onToken: onToken))
            case .openai:
                return .success(try await streamOpenAI(system: system, history: history, tools: tools, apiKey: apiKey, onToken: onToken))
            }
        } catch let error as AssistantServiceError {
            return .failure(error)
        } catch {
            return await send(system: system, history: history, tools: tools)
        }
    }

    /// Non-streaming request. The reliable fallback, and usable on its own.
    public func send(
        system: String,
        history: [AssistantChatMessage],
        tools: [AssistantToolDefinition]
    ) async -> Result<AssistantTurn, AssistantServiceError> {
        guard let apiKey, !apiKey.isEmpty else { return .failure(.missingAPIKey) }
        do {
            switch provider {
            case .anthropic:
                return .success(try await sendAnthropic(system: system, history: history, tools: tools, apiKey: apiKey))
            case .openai:
                return .success(try await sendOpenAI(system: system, history: history, tools: tools, apiKey: apiKey))
            }
        } catch let error as AssistantServiceError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    // MARK: - Anthropic

    func anthropicToolsPayload(_ tools: [AssistantToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            var payload: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
            ]
            payload["input_schema"] = schemaObject(tool.parametersSchemaJSON)
            return payload
        }
    }

    private func anthropicRequestBody(system: String, history: [AssistantChatMessage], tools: [AssistantToolDefinition], stream: Bool) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 2048,
            "system": system,
            "stream": stream,
            "messages": history.map { message in
                var payload: [String: Any] = ["role": message.role.rawValue, "content": message.text]
                if let toolCallID = message.toolCallID { payload["tool_call_id"] = toolCallID }
                if !message.toolCalls.isEmpty {
                    payload["tool_calls"] = message.toolCalls.map { call in
                        ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": call.argumentsJSON]]
                    }
                }
                return payload
            },
            "tools": anthropicToolsPayload(tools),
        ]
    }

    private func anthropicRequest(body: [String: Any], apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func sendAnthropic(system: String, history: [AssistantChatMessage], tools: [AssistantToolDefinition], apiKey: String) async throws -> AssistantTurn {
        let body = anthropicRequestBody(system: system, history: history, tools: tools, stream: false)
        let request = try anthropicRequest(body: body, apiKey: apiKey)
        let (data, response) = try await urlSessionData(for: request)
        try validate(response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]]
        else { throw AssistantServiceError.invalidResponse }

        var text = ""
        var calls: [AssistantToolCallRequest] = []
        for block in content {
            guard let type = block["type"] as? String else { continue }
            if type == "text", let value = block["text"] as? String {
                text += value
            } else if type == "tool_use", let name = block["name"] as? String, let id = block["id"] as? String {
                let input = block["input"] ?? [:]
                calls.append(AssistantToolCallRequest(id: id, name: name, argumentsJSON: jsonString(input)))
            }
        }
        return AssistantTurn(text: text, toolCalls: calls)
    }

    private func streamAnthropic(system: String, history: [AssistantChatMessage], tools: [AssistantToolDefinition], apiKey: String, onToken: @escaping (String) -> Void) async throws -> AssistantTurn {
        let body = anthropicRequestBody(system: system, history: history, tools: tools, stream: true)
        let request = try anthropicRequest(body: body, apiKey: apiKey)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response, data: nil)

        var text = ""
        var toolName: String?
        var toolID: String?
        var toolJSON = ""
        var calls: [AssistantToolCallRequest] = []

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }

            switch type {
            case "content_block_start":
                if let block = event["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                    toolName = block["name"] as? String
                    toolID = block["id"] as? String
                    toolJSON = ""
                }
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any] else { continue }
                if let value = delta["text"] as? String {
                    text += value
                    onToken(value)
                } else if let partial = delta["partial_json"] as? String {
                    toolJSON += partial
                }
            case "content_block_stop":
                if let name = toolName, let id = toolID {
                    calls.append(AssistantToolCallRequest(id: id, name: name, argumentsJSON: toolJSON.isEmpty ? "{}" : toolJSON))
                }
                toolName = nil
                toolID = nil
                toolJSON = ""
            default:
                break
            }
        }
        return AssistantTurn(text: text, toolCalls: calls)
    }

    // MARK: - OpenAI

    func openAIToolsPayload(_ tools: [AssistantToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": schemaObject(tool.parametersSchemaJSON),
                ],
            ]
        }
    }

    private func openAIRequestBody(system: String, history: [AssistantChatMessage], tools: [AssistantToolDefinition], stream: Bool) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        messages += history.map { message in
            var payload: [String: Any] = ["role": message.role.rawValue, "content": message.text]
            if let toolCallID = message.toolCallID { payload["tool_call_id"] = toolCallID }
            if !message.toolCalls.isEmpty {
                payload["tool_calls"] = message.toolCalls.map { call in
                    ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": call.argumentsJSON]]
                }
            }
            return payload
        }
        return [
            "model": model,
            "stream": stream,
            "messages": messages,
            "tools": openAIToolsPayload(tools),
        ]
    }

    private func openAIRequest(body: [String: Any], apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func sendOpenAI(system: String, history: [AssistantChatMessage], tools: [AssistantToolDefinition], apiKey: String) async throws -> AssistantTurn {
        let body = openAIRequestBody(system: system, history: history, tools: tools, stream: false)
        let request = try openAIRequest(body: body, apiKey: apiKey)
        let (data, response) = try await urlSessionData(for: request)
        try validate(response, data: data)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else { throw AssistantServiceError.invalidResponse }

        let text = message["content"] as? String ?? ""
        var calls: [AssistantToolCallRequest] = []
        if let toolCalls = message["tool_calls"] as? [[String: Any]] {
            for call in toolCalls {
                guard let id = call["id"] as? String, let function = call["function"] as? [String: Any],
                      let name = function["name"] as? String
                else { continue }
                let arguments = function["arguments"] as? String ?? "{}"
                calls.append(AssistantToolCallRequest(id: id, name: name, argumentsJSON: arguments))
            }
        }
        return AssistantTurn(text: text, toolCalls: calls)
    }

    private func streamOpenAI(system: String, history: [AssistantChatMessage], tools: [AssistantToolDefinition], apiKey: String, onToken: @escaping (String) -> Void) async throws -> AssistantTurn {
        let body = openAIRequestBody(system: system, history: history, tools: tools, stream: true)
        let request = try openAIRequest(body: body, apiKey: apiKey)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response, data: nil)

        var text = ""
        // Keyed by tool_call index — OpenAI streams each call's name/args in pieces.
        var callsByIndex: [Int: (id: String, name: String, arguments: String)] = [:]

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = event["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any]
            else { continue }

            if let value = delta["content"] as? String {
                text += value
                onToken(value)
            }
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    guard let index = call["index"] as? Int else { continue }
                    var existing = callsByIndex[index] ?? (id: "", name: "", arguments: "")
                    if let id = call["id"] as? String { existing.id = id }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String { existing.name += name }
                        if let arguments = function["arguments"] as? String { existing.arguments += arguments }
                    }
                    callsByIndex[index] = existing
                }
            }
        }
        let calls = callsByIndex.sorted { $0.key < $1.key }.map {
            AssistantToolCallRequest(id: $0.value.id, name: $0.value.name, argumentsJSON: $0.value.arguments.isEmpty ? "{}" : $0.value.arguments)
        }
        return AssistantTurn(text: text, toolCalls: calls)
    }

    // MARK: - Shared helpers

    private func urlSessionData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw AssistantServiceError.cancelled
        } catch {
            throw AssistantServiceError.network(error.localizedDescription)
        }
    }

    private func validate(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else { throw AssistantServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw AssistantServiceError.http(status: http.statusCode, body: String(body.prefix(300)), retryAfter: retryAfter)
        }
    }

    private func schemaObject(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? ["type": "object", "properties": [String: Any]()]
    }

    private func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }
}
