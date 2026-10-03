// ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Sends a math tool call together with the user's own words, so the helper can refuse a call
/// that does not say what the user asked. The text comes from the conversation, never from the
/// model: any argument the model starts with "_" is dropped before the app adds its own.
enum MathTranscriptionService {
    static let reviewInstructions = "You check a transcription. Do not solve anything. REQUEST is what the user asked. CALL is what will be computed. Answer consistent if CALL states the same mathematical problem as REQUEST: the same formulas, numbers, limits, conditions and data, even when written differently or with other variable names. Answer inconsistent if CALL changes, drops or adds any of them. Answer uncertain if REQUEST does not say enough to tell."
    static let reviewGrammar = #"root ::= "consistent" | "inconsistent" | "uncertain""#
    static let contextLimit = 6000

    static func isMathTool(_ name: String) -> Bool {
        SymPyToolsService.isTool(name) || ScientificToolsService.isTool(name)
    }

    /// The last user message is the request; earlier user messages and tool results are context.
    static func source(messages: [ChatMessage]) -> [String: Any]? {
        guard let last = messages.lastIndex(where: { $0.role == "user" }) else { return nil }
        let earlier = messages.enumerated().compactMap { index, message -> String? in
            guard index != last, message.role == "user" || message.role == "tool" else { return nil }
            return message.role == "user" ? message.wireContent : message.content
        }.joined(separator: "\n")
        return ["request": messages[last].wireContent, "context": String(earlier.suffix(contextLimit))]
    }

    static func execute(name: String, arguments: [String: Any], source: [String: Any]?, port: Int,
                        workingDirectory: String? = nil) async throws -> ToolExecutionResult {
        var plain = arguments.filter { !$0.key.hasPrefix("_") }
        guard let source else {
            return try await ChatToolsService.execute(name: name, arguments: plain, port: port,
                                                      workingDirectory: workingDirectory)
        }
        plain["_source"] = source
        let first = try await ChatToolsService.execute(name: name, arguments: plain, port: port,
                                                       workingDirectory: workingDirectory)
        guard let reply = reply(first.content), errorCode(reply) == "needs_review" else { return first }
        let verdict = try await review(source: source, reply: reply, operation: arguments["operation"] as? String,
                                       port: port)
        guard verdict == "consistent" else { return first }
        plain["_reviewed"] = "consistent"
        return try await ChatToolsService.execute(name: name, arguments: plain, port: port,
                                                  workingDirectory: workingDirectory)
    }

    /// The model compares the request with what the helper read; it never sees a result to defend.
    static func review(source: [String: Any], reply: [String: Any], operation: String?, port: Int) async throws -> String {
        let lines = (reply["interpreted_input"] as? [String]) ?? []
        let user = "REQUEST:\n\(source["request"] as? String ?? "")\n\nCALL: \(operation ?? "")\n"
            + lines.joined(separator: "\n") + " /no_think"
        var body: [String: Any] = [
            "messages": [["role": "system", "content": reviewInstructions], ["role": "user", "content": user]],
            "max_tokens": 4, "temperature": 0, "grammar": reviewGrammar, "cache_prompt": false,
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        if let model = ServerSettings.activeRouterModel() { body["model"] = model }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = ServerSettings.activeAPIKey() { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((object?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
        return ((message?["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func reply(_ content: String) -> [String: Any]? {
        guard let start = content.firstIndex(of: "{") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(content[start...].utf8)) as? [String: Any]
    }

    /// What the helper read from the call, for the card: the user checks it against the request.
    static func interpreted(_ reply: [String: Any]) -> [String] {
        ((reply["interpreted_input"] as? [String]) ?? []).map { "▸ " + $0 }
    }

    static func errorCode(_ reply: [String: Any]) -> String? {
        (reply["error"] as? [String: Any])?["code"] as? String
    }
}
