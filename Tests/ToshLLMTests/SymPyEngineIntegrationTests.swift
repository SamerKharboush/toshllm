// ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ToshLLM

/// Runs the real engine with the math runtime from vendor/, both tool sets on. Needs a tool-calling model:
///   TOSH_SYMPY_E2E_MODEL=~/models/Qwen3-4B-Q4_K_M.gguf ./scripts/test.sh --filter SymPyEngine
final class SymPyEngineIntegrationTests: XCTestCase {
    private static let port = 18_433
    private static var server: Process?
    private static var skipReason: String?

    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    override class func setUp() {
        super.setUp()
        let environment = ProcessInfo.processInfo.environment
        guard let model = environment["TOSH_SYMPY_E2E_MODEL"] else {
            skipReason = "Set TOSH_SYMPY_E2E_MODEL to run the engine integration tests"
            return
        }
        let binary = environment["TOSH_BIN"]
            ?? repository.appendingPathComponent("vendor/llama.cpp/build-static/bin/llama-server").path
        let sympy = SymPyToolsService.serverArguments(
            enabled: true, scientific: true, resources: repository.appendingPathComponent("vendor"))
        guard FileManager.default.isExecutableFile(atPath: binary), !sympy.isEmpty else {
            skipReason = "Build the engine and the math runtime first"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["-m", (model as NSString).expandingTildeInPath, "--host", "127.0.0.1",
                             "--port", String(port), "-ngl", "99", "-c", "8192", "--load-mode", "none",
                             "--jinja", "--tools", "all"] + sympy
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch {
            skipReason = "Could not start the engine: \(error.localizedDescription)"
            return
        }
        server = process
        let health = URL(string: "http://127.0.0.1:\(port)/health")!
        for _ in 0..<240 {
            if let data = try? Data(contentsOf: health), String(decoding: data, as: UTF8.self).contains("ok") {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        skipReason = "The engine did not become ready"
    }

    override class func tearDown() {
        server?.terminate()
        server?.waitUntilExit()
        server = nil
        super.tearDown()
    }

    override func setUpWithError() throws {
        if let reason = Self.skipReason { throw XCTSkip(reason) }
        UserDefaults.standard.set(true, forKey: SettingsKeys.agentToolsEnabled)
        UserDefaults.standard.set(true, forKey: SettingsKeys.sympyEnabled)
        UserDefaults.standard.set(true, forKey: SettingsKeys.scientificEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKeys.agentToolsEnabled)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.sympyEnabled)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.scientificEnabled)
        super.tearDown()
    }

    private func run(_ tool: String, _ arguments: [String: Any], cwd: String? = nil) async throws -> ToolExecutionResult {
        try await ChatToolsService.execute(name: tool, arguments: arguments, port: Self.port,
                                           workingDirectory: cwd)
    }

    func testToolsAreDiscoveredThroughTheEngine() async throws {
        let tools = try await ChatToolsService.listEnabled(port: Self.port)
        let names = Set(tools.map(\.name))
        for name in ["sympy_expression", "sympy_solve", "sympy_matrix", "sympy_verify",
                     "scientific_compute", "scientific_linalg", "scientific_optimize",
                     "scientific_signal", "scientific_ode", "scientific_stats",
                     "read_file", "write_file", "edit_file", "grep_search", "file_glob_search",
                     "exec_shell_command"] {
            XCTAssertTrue(names.contains(name), name)
        }
        for tool in tools where SymPyToolsService.isTool(tool.name) || ScientificToolsService.isTool(tool.name) {
            XCTAssertFalse(tool.writesData)
            XCTAssertFalse(tool.usesCwd)
            XCTAssertNotNil(tool.openAIDefinition)
        }
    }

    func testEachSettingHidesItsOwnTools() async throws {
        UserDefaults.standard.set(false, forKey: SettingsKeys.sympyEnabled)
        var names = try await ChatToolsService.listEnabled(port: Self.port).map(\.name)
        XCTAssertFalse(names.contains { SymPyToolsService.isTool($0) })
        XCTAssertTrue(names.contains("read_file"))

        UserDefaults.standard.set(true, forKey: SettingsKeys.sympyEnabled)
        UserDefaults.standard.set(false, forKey: SettingsKeys.scientificEnabled)
        UserDefaults.standard.set(false, forKey: SettingsKeys.agentToolsEnabled)
        names = try await ChatToolsService.listEnabled(port: Self.port).map(\.name)
        XCTAssertEqual(Set(names), ["sympy_expression", "sympy_solve", "sympy_matrix", "sympy_verify"])

        UserDefaults.standard.set(false, forKey: SettingsKeys.sympyEnabled)
        UserDefaults.standard.set(true, forKey: SettingsKeys.scientificEnabled)
        names = try await ChatToolsService.listEnabled(port: Self.port).map(\.name)
        XCTAssertEqual(Set(names), ["scientific_compute", "scientific_linalg", "scientific_optimize",
                                    "scientific_signal", "scientific_ode", "scientific_stats"])
    }

    func testScientificToolsRunThroughTheEngine() async throws {
        let integral = try await run("scientific_compute", ["operation": "integrate", "expression": "sin(x**2)",
                                                            "lower": 0, "upper": 10])
        XCTAssertFalse(integral.isError, integral.content)
        XCTAssertTrue(integral.content.contains(#""value": 0.5836708999"#), integral.content)

        let determinant = try await run("scientific_linalg", ["operation": "determinant",
                                                              "matrix": [[1, 2], [3, 4]]])
        XCTAssertTrue(determinant.content.contains(#""determinant": -2.0"#), determinant.content)

        let minimum = try await run("scientific_optimize", ["operation": "minimize",
                                                            "expression": "(x - 3)**2 + (y + 1)**2",
                                                            "initial_guess": ["x": 0, "y": 0]])
        XCTAssertFalse(minimum.isError, minimum.content)
        XCTAssertTrue(minimum.content.contains(#""success": true"#), minimum.content)

        let spectrum = try await run("scientific_signal", ["operation": "fft", "expression": "sin(2*pi*50*t)",
                                                           "sample_rate": 1000, "duration": 1])
        XCTAssertTrue(spectrum.content.contains("50.0"), spectrum.content)

        let decay = try await run("scientific_ode", ["operation": "solve_ivp", "equations": ["dy/dt = -y"],
                                                     "initial_conditions": ["y": 1], "interval": [0, 1],
                                                     "at": [1]])
        XCTAssertTrue(decay.content.contains("0.36787"), decay.content)

        let summary = try await run("scientific_stats", ["operation": "describe", "values": [1, 2, 3, 4]])
        XCTAssertTrue(summary.content.contains(#""mean": 2.5"#), summary.content)

        // a failed computation is an error with its code, never a number
        let singular = try await run("scientific_linalg", ["operation": "solve", "matrix": [[1, 2], [2, 4]],
                                                           "other": [1, 2]])
        XCTAssertTrue(singular.isError)
        XCTAssertTrue(singular.content.contains("singular_matrix"), singular.content)
        let divergent = try await run("scientific_compute", ["operation": "integrate", "expression": "1/x",
                                                             "lower": 0, "upper": 1])
        XCTAssertTrue(divergent.isError)
        XCTAssertFalse(divergent.content.contains(#""value""#), divergent.content)

        let injected = try await run("scientific_compute", ["operation": "evaluate",
                                                            "expression": "__import__('os').system('id')"])
        XCTAssertTrue(injected.isError)
        XCTAssertTrue(injected.content.contains("invalid_expression"), injected.content)
        let named = try await run("scientific_compute", ["operation": "evaluate",
                                                         "expression": "np.sin(1)"])
        XCTAssertTrue(named.isError, named.content)
    }

    func testToolsRunThroughTheEngine() async throws {
        let factored = try await run("sympy_expression", ["operation": "factor", "expression": "x**2 - 5*x + 6"])
        XCTAssertFalse(factored.isError)
        XCTAssertTrue(factored.content.contains(#""exact": "(x - 3)*(x - 2)""#), factored.content)

        let verified = try await run("sympy_verify", ["operation": "equivalent",
                                                      "left": "(x + 1)**2", "right": "x**2 + 2*x"])
        XCTAssertTrue(verified.content.contains(#""equivalent": false"#), verified.content)

        let solved = try await run("sympy_solve", ["operation": "solve", "equations": ["e**2 - 4 = 0"],
                                                   "variables": ["e"]])
        XCTAssertTrue(solved.content.contains(#""solutions": [{"e": "-2"}, {"e": "2"}]"#), solved.content)

        let determinant = try await run("sympy_matrix", ["operation": "determinant",
                                                         "matrix": [["1", "2"], ["3", "4"]]])
        XCTAssertTrue(determinant.content.contains(#""exact": "-2""#), determinant.content)

        let numeric = try await run("sympy_expression", ["operation": "integrate", "expression": "exp(sin(x))",
                                                         "variable": "x", "lower": "0", "upper": "1"])
        XCTAssertFalse(numeric.isError)
        XCTAssertTrue(numeric.content.contains(#""method": "numerical_integration""#), numeric.content)
        XCTAssertEqual(SymPyToolsService.readable(numeric.content).components(separatedBy: "\n").prefix(2).joined(separator: " "),
                       "Integral(exp(sin(x)), (x, 0, 1)) ≈ 1.63186960841805")

        // no closed form is an answer, not a failed call
        let open = try await run("sympy_expression", ["operation": "integrate", "expression": "sin(sin(x))",
                                                      "variable": "x"])
        XCTAssertFalse(open.isError)
        XCTAssertTrue(open.content.contains(#""code": "no_closed_form""#), open.content)

        let injected = try await run("sympy_expression", ["operation": "simplify",
                                                          "expression": "__import__('os').system('id')"])
        XCTAssertTrue(injected.isError)
        XCTAssertTrue(injected.content.contains("invalid_expression"), injected.content)
    }

    func testFileAndShellToolsStillWork() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tosh-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cwd = directory.path

        let written = try await run("write_file", ["path": "note.txt", "content": "alpha\nbeta\n"], cwd: cwd)
        XCTAssertFalse(written.isError, written.content)
        let read = try await run("read_file", ["path": "note.txt"], cwd: cwd)
        XCTAssertEqual(read.content, "alpha\nbeta\n")
        let edited = try await run("edit_file", ["path": "note.txt",
                                                 "edits": [["old_text": "beta", "new_text": "gamma"]]], cwd: cwd)
        XCTAssertFalse(edited.isError, edited.content)
        let grep = try await run("grep_search", ["path": ".", "pattern": "gamma"], cwd: cwd)
        XCTAssertTrue(grep.content.contains("note.txt:gamma"), grep.content)
        let glob = try await run("file_glob_search", ["path": ".", "include": "*.txt"], cwd: cwd)
        XCTAssertTrue(glob.content.contains("note.txt"), glob.content)
        let shell = try await ChatToolsService.executeStreaming(
            name: "exec_shell_command", arguments: ["command": "cat note.txt"], port: Self.port,
            workingDirectory: cwd) { _ in }
        XCTAssertTrue(shell.content.contains("gamma") && shell.content.contains("[exit code: 0]"), shell.content)
    }

    func testExactRequestStaysSymbolicWithBothToolSets() async throws {
        let tools = try await ChatToolsService.listEnabled(port: Self.port)
            .filter { SymPyToolsService.isTool($0.name) || ScientificToolsService.isTool($0.name) }
            .compactMap(\.openAIDefinition)
        XCTAssertEqual(tools.count, 10)
        let system = ScientificToolsService.system("", sympy: true, scientific: true)
        for (prompt, family) in [("Integrate x^2 from 0 to 3.", "sympy_"),
                                 ("Numerically integrate exp(sin(x)) from 0 to 2.", "scientific_")] {
            let reply = try await complete([["role": "system", "content": system],
                                            ["role": "user", "content": prompt + " Use the tools. /no_think"]],
                                           tools: tools)
            let call = try XCTUnwrap((reply["tool_calls"] as? [[String: Any]])?.first, prompt)
            let name = try XCTUnwrap((call["function"] as? [String: Any])?["name"] as? String)
            XCTAssertTrue(name.hasPrefix(family), "\(prompt) -> \(name)")
        }
    }

    private func complete(_ messages: [[String: Any]], tools: [[String: Any]]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(Self.port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": messages, "tools": tools, "temperature": 0, "max_tokens": 1024,
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let choice = try XCTUnwrap((object["choices"] as? [[String: Any]])?.first)
        return try XCTUnwrap(choice["message"] as? [String: Any])
    }

    func testModelCallsTheToolAndUsesItsResult() async throws {
        let tools = try await ChatToolsService.listEnabled(port: Self.port)
            .filter { SymPyToolsService.isTool($0.name) }.compactMap(\.openAIDefinition)
        var messages: [[String: Any]] = [[
            "role": "user",
            "content": "Use the tool to factor x^2 - 5x + 6, then tell me the factors. /no_think",
        ]]
        let first = try await complete(messages, tools: tools)
        let call = try XCTUnwrap((first["tool_calls"] as? [[String: Any]])?.first, "the model made no tool call")
        let function = try XCTUnwrap(call["function"] as? [String: Any])
        let name = try XCTUnwrap(function["name"] as? String)
        XCTAssertTrue(SymPyToolsService.isTool(name), name)

        let arguments = try ChatToolsService.parseArguments(try XCTUnwrap(function["arguments"] as? String))
        let result = try await run(name, arguments)
        XCTAssertFalse(result.isError, result.content)
        XCTAssertTrue(result.content.contains("(x - 3)*(x - 2)"), result.content)

        messages.append(first)
        messages.append(["role": "tool", "tool_call_id": call["id"] as? String ?? "", "content": result.content])
        let answer = try await complete(messages, tools: tools)
        let text = try XCTUnwrap(answer["content"] as? String)
        XCTAssertTrue(text.contains("3") && text.contains("2"), text)
        XCTAssertNil(answer["tool_calls"] as? [[String: Any]])
    }
}
