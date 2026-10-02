// ToshLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ToshLLM

final class SymPyToolsTests: XCTestCase {
    private func makeSettings() -> ServerSettings {
        ServerSettings(serverBinary: "/usr/bin/true", modelPath: "/tmp/m.gguf", port: 8080,
                       ngl: 99, ncmoe: 0, ctx: 8192, threads: 6, flashAttn: "auto",
                       noMmap: true, jinja: true,
                       vramReserveMB: 1024, gpuIndex: -1, extraArgs: "",
                       cacheTypeK: "f16", cacheTypeV: "f16", mlock: false)
    }

    private func makeRuntime() throws -> URL {
        let resources = FileManager.default.temporaryDirectory
            .appendingPathComponent("tosh-sympy-test-\(UUID().uuidString)")
        let bin = resources.appendingPathComponent("tosh-sympy/python/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true",
                                         toPath: bin.appendingPathComponent("python3").path)
        addTeardownBlock { try? FileManager.default.removeItem(at: resources) }
        return resources
    }

    func testOffByDefault() {
        XCTAssertFalse(makeSettings().sympyEnabled)
        XCTAssertFalse(makeSettings().arguments.contains("--mcp-servers-json"))
        XCTAssertTrue(SettingsKeys.resettableOptionKeys.contains(SettingsKeys.sympyEnabled))
    }

    func testDisabledAddsNothingEvenWithTheRuntimePresent() throws {
        XCTAssertEqual(SymPyToolsService.serverArguments(enabled: false, resources: try makeRuntime()), [])
    }

    func testEnabledWithoutTheRuntimeAddsNothing() {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(SymPyToolsService.serverArguments(enabled: true, resources: empty), [])
        XCTAssertEqual(SymPyToolsService.serverArguments(enabled: true, resources: nil), [])
    }

    func testEnabledStartsTheHelperAsAnMCPServer() throws {
        let resources = try makeRuntime()
        let arguments = SymPyToolsService.serverArguments(enabled: true, resources: resources)
        XCTAssertEqual(arguments.first, "--mcp-servers-json")
        let config = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try XCTUnwrap(arguments.last).utf8)) as? [String: Any])
        let server = try XCTUnwrap((config["mcpServers"] as? [String: Any])?["sympy"] as? [String: Any])
        let runtime = resources.appendingPathComponent("tosh-sympy").path
        XCTAssertEqual(server["command"] as? String, runtime + "/python/bin/python3")
        XCTAssertEqual(server["args"] as? [String], ["-I", "-B", runtime + "/tosh_sympy/server.py"])
    }

    func testScientificServerRunsBesideSymPy() throws {
        let resources = try makeRuntime()
        XCTAssertFalse(makeSettings().scientificEnabled)
        XCTAssertTrue(SettingsKeys.resettableOptionKeys.contains(SettingsKeys.scientificEnabled))
        func servers(_ sympy: Bool, _ scientific: Bool) throws -> [String: Any] {
            let arguments = SymPyToolsService.serverArguments(enabled: sympy, scientific: scientific,
                                                              resources: resources)
            guard let json = arguments.last else { return [:] }
            let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            return try XCTUnwrap(config["mcpServers"] as? [String: Any])
        }
        XCTAssertEqual(try servers(false, false).count, 0)
        XCTAssertEqual(Array(try servers(true, false).keys), ["sympy"])
        XCTAssertEqual(Array(try servers(false, true).keys), ["scientific"])
        let both = try servers(true, true)
        XCTAssertEqual(Set(both.keys), ["sympy", "scientific"])
        let scientific = try XCTUnwrap(both["scientific"] as? [String: Any])
        XCTAssertEqual((scientific["args"] as? [String])?.last, "scientific")
        XCTAssertEqual((both["sympy"] as? [String: Any])?["command"] as? String, scientific["command"] as? String)
    }

    func testRoutingRuleIsSentOnlyWithBothToolSets() {
        let rule = ScientificToolsService.routingRule
        XCTAssertEqual(ScientificToolsService.system("", sympy: true, scientific: true), rule)
        XCTAssertEqual(ScientificToolsService.system("Be brief.", sympy: true, scientific: true),
                       "Be brief.\n\n" + rule)
        XCTAssertEqual(ScientificToolsService.system("Be brief.", sympy: true, scientific: false), "Be brief.")
        XCTAssertEqual(ScientificToolsService.system("", sympy: false, scientific: true), "")
        XCTAssertEqual(ScientificToolsService.system("", sympy: false, scientific: false), "")
    }

    func testScientificCallIsPresentedAsMath() {
        XCTAssertTrue(ScientificToolsService.isTool("scientific_linalg"))
        XCTAssertFalse(ScientificToolsService.isTool("sympy_matrix"))
        let call = ChatToolCall(
            name: "scientific_compute",
            arguments: #"{"operation":"integrate","expression":"sin(x**2)","lower":0,"upper":10}"#,
            result: #"{"success": true, "operation": "integrate", "value": 0.58367089993, "error_estimate": 2.7e-11, "method": "adaptive quadrature (QUADPACK)", "warnings": []}"#)
        let presentation = ToolCallPresentation.make(call)
        XCTAssertEqual(presentation.kind, .math)
        XCTAssertEqual(presentation.title, "Integrate")
        XCTAssertEqual(presentation.code, "sin(x**2)")
        XCTAssertEqual(presentation.result?.components(separatedBy: "\n").first, "value: 0.58367089993")
        XCTAssertEqual(
            ScientificToolsService.readable(#"{"success":false,"operation":"solve","error":{"code":"singular_matrix","message":"singular"}}"#),
            "singular")
        XCTAssertEqual(ScientificToolsService.input(["values": [1, 2, 3]]), "values: 3 values")
    }

    func testToolNames() {
        XCTAssertTrue(SymPyToolsService.isTool("sympy_expression"))
        XCTAssertTrue(SymPyToolsService.isTool("sympy_verify"))
        XCTAssertFalse(SymPyToolsService.isTool("read_file"))
        XCTAssertFalse(SymPyToolsService.isTool("sympy"))
    }

    func testCallIsPresentedAsMath() {
        let call = ChatToolCall(
            name: "sympy_expression",
            arguments: #"{"operation":"laplace_transform","expression":"exp(-a*t)"}"#,
            result: #"{"success": true, "operation": "laplace_transform", "exact": "1/(a + s)", "latex": "x", "warnings": []}"#)
        let presentation = ToolCallPresentation.make(call)
        XCTAssertEqual(presentation.kind, .math)
        XCTAssertEqual(presentation.title, "Laplace transform")
        XCTAssertEqual(presentation.code, "exp(-a*t)")
        XCTAssertEqual(presentation.result, "1/(a + s)")
    }

    func testReadableResults() {
        XCTAssertEqual(
            SymPyToolsService.readable(#"{"success":true,"exact":"sqrt(pi)","numeric":"1.77","warnings":["w"]}"#),
            "sqrt(pi)\n≈ 1.77\n⚠︎ w")
        XCTAssertEqual(
            SymPyToolsService.readable(#"{"success":true,"equivalent":false,"difference":"1","warnings":[]}"#),
            "equivalent: no\ndifference: 1")
        XCTAssertEqual(
            SymPyToolsService.readable(#"{"success":false,"operation":"factor","error":{"code":"timeout","message":"stopped"}}"#),
            "stopped")
        XCTAssertEqual(SymPyToolsService.readable("not json"), "not json")
        XCTAssertEqual(
            SymPyToolsService.readable(#"{"success":true,"exact":null,"unevaluated":"Integral(x**x, (x, 0, 1))","numeric":"0.78","method":"numerical_integration","warnings":[]}"#),
            "Integral(x**x, (x, 0, 1))\n≈ 0.78")
        XCTAssertEqual(
            SymPyToolsService.readable(#"{"success":false,"timed_out":true,"exact":null,"unevaluated":"Integral(f(x), x)","error":{"code":"timeout","message":"No closed form."},"warnings":[]}"#),
            "No closed form.\nIntegral(f(x), x)")
        XCTAssertEqual(SymPyToolsService.input(["equations": ["x = 1", "y = 2"]]), "x = 1\ny = 2")
        XCTAssertEqual(SymPyToolsService.input(["matrix": [["1", 2], [3, "4"]]]), "1  2\n3  4")
    }
}
