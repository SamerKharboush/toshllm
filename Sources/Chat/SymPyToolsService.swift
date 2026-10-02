// ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Symbolic math tools. The engine runs the bundled helper as an MCP server and lists its
/// tools on /tools, so the app only decides whether to start it and how to show a call.
enum SymPyToolsService {
    static let serverName = "sympy"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.sympyEnabled)
    }

    static func isTool(_ name: String) -> Bool {
        name.hasPrefix(serverName + "_")
    }

    /// The runtime built by scripts/build-sympy.sh, or nil when this build does not carry it.
    static func runtimeDirectory(resources: URL? = Bundle.main.resourceURL) -> URL? {
        guard let directory = resources?.appendingPathComponent("tosh-sympy"),
              FileManager.default.isExecutableFile(
                atPath: directory.appendingPathComponent("python/bin/python3").path)
        else { return nil }
        return directory
    }

    static func serverArguments(enabled: Bool, resources: URL? = Bundle.main.resourceURL) -> [String] {
        guard enabled, let runtime = runtimeDirectory(resources: resources) else { return [] }
        let config: [String: Any] = ["mcpServers": [serverName: [
            "command": runtime.appendingPathComponent("python/bin/python3").path,
            "args": ["-I", "-B", runtime.appendingPathComponent("tosh_sympy/server.py").path],
            "timeout_ms": 30_000,
        ]]]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]) else {
            return []
        }
        return ["--mcp-servers-json", String(decoding: data, as: UTF8.self)]
    }

    /// What the call was asked to work on, for the tool card.
    static func input(_ arguments: [String: Any]) -> String? {
        if let expression = arguments["expression"] as? String { return expression }
        if let equations = arguments["equations"] as? [Any] {
            return equations.map { String(describing: $0) }.joined(separator: "\n")
        }
        if let rows = arguments["matrix"] as? [[Any]] {
            return rows.map { $0.map { String(describing: $0) }.joined(separator: "  ") }
                .joined(separator: "\n")
        }
        if let left = arguments["left"] as? String, let right = arguments["right"] as? String {
            return left + "\n" + right
        }
        return nil
    }

    /// The JSON result as the few lines a person reads. The model still gets the JSON.
    static func readable(_ result: String) -> String {
        guard let data = result.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return result }
        var lines: [String] = []
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            // a timeout or an open integral still says what was asked and what is known
            guard object["timed_out"] != nil else { return message }
            lines.append(message)
            if let unevaluated = object["unevaluated"] as? String { lines.append(unevaluated) }
            if let partial = object["partial"] as? [String: Any], let exact = partial["exact"] as? String {
                lines.append(exact)
            }
            return lines.joined(separator: "\n")
        }
        if let equivalent = object["equivalent"] {
            lines.append("equivalent: \(text(equivalent))")
            if let difference = object["difference"] as? String, difference != "0" {
                lines.append("difference: \(difference)")
            }
        }
        if let satisfied = object["satisfied"] {
            lines.append("satisfied: \(text(satisfied))")
            for check in object["checks"] as? [[String: Any]] ?? [] {
                if let residual = check["residual"] as? String, residual != "0" {
                    lines.append("residual: \(residual)")
                }
            }
        }
        if let exact = object["exact"] as? String {
            lines.append(exact)
        } else if let unevaluated = object["unevaluated"] as? String {
            lines.append(unevaluated)
        }
        if let numeric = object["numeric"] as? String { lines.append("≈ \(numeric)") }
        for warning in object["warnings"] as? [String] ?? [] { lines.append("⚠︎ \(warning)") }
        return lines.isEmpty ? result : lines.joined(separator: "\n")
    }

    private static func text(_ value: Any) -> String {
        if value is NSNull { return "undecided" }
        if let flag = value as? Bool { return flag ? "yes" : "no" }
        return String(describing: value)
    }
}
