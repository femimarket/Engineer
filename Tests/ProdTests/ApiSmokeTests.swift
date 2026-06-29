//
//  ApiSmokeTests.swift
//  ProdTests
//
//  Hits the real Api endpoints with creds from env vars. Purpose: when
//  Engineer stays on shimmer after Generate, isolate whether the Api itself
//  is returning real bytes (then the bug is in our state handling) or
//  returning the lib's fallback PNG (then the bug is auth / server-side).
//
//  Set creds in the scheme's environment variables (Edit Scheme → Test →
//  Environment Variables):
//    TEST_USER     = <user>
//    TEST_PASSWORD = <password>
//
//  Tests skip silently if creds aren't set, so they stay green in CI.
//

import XCTest
import Api

#if canImport(UIKit)
import UIKit
#endif

final class ApiSmokeTests: XCTestCase {
    private static var user: String {
        ProcessInfo.processInfo.environment["TEST_USER"] ?? ""
    }
    private static var password: String {
        ProcessInfo.processInfo.environment["TEST_PASSWORD"] ?? ""
    }

    private func requireCreds() throws {
        if Self.user.isEmpty || Self.password.isEmpty {
            throw XCTSkip("Set TEST_USER and TEST_PASSWORD env vars to run the Api smoke tests.")
        }
    }

    /// Verifies the chat call returns an assistant message with non-empty
    /// content that isn't the lib's "Could not respond" fallback. Failure here
    /// means auth is bad or the server returned an error — not a state-handling
    /// problem in Engineer.
    func testChatReturnsAssistantMessage() async throws {
        try requireCreds()
        let messages = await Api.qwen3_6_35b_a3b(
            user: Self.user,
            password: Self.password,
            messages: [(role: .user, content: "Reply with exactly: pong")]
        )
        let last = try XCTUnwrap(messages.last, "Expected at least one message in response")
        XCTAssertEqual(last.role, .assistant, "Last message should be from the assistant")
        XCTAssertFalse(last.content.isEmpty, "Assistant content was empty")
        XCTAssertNotEqual(
            last.content,
            "Could not respond",
            "Lib returned its fallback content — auth or server-side failure"
        )
    }

    /// Verifies flux2Pro returns enough bytes to be a real image and that
    /// those bytes decode as a UIImage with a real size. Failure here means
    /// the Api isn't returning real images — either auth, server-side, or
    /// the lib substituted its fallback PNG.
    func testFlux2ProReturnsDecodableImage() async throws {
        try requireCreds()
        let data = await Api.flux2Pro(
            user: Self.user,
            password: Self.password,
            prompt: "a single red apple, white background, studio lighting"
        )
        XCTAssertGreaterThan(
            data.count,
            1000,
            "Result too small to be a real image (\(data.count) bytes) — likely empty or fallback"
        )
        #if canImport(UIKit)
        let img = UIImage(data: data)
        XCTAssertNotNil(img, "Returned bytes did not decode as a UIImage")
        if let img {
            XCTAssertGreaterThan(img.size.width, 0)
            XCTAssertGreaterThan(img.size.height, 0)
        }
        #endif
    }
}
