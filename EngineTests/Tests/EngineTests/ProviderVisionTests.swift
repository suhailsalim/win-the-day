import XCTest
@testable import AppCore

/// `Providers.supportsVision` gates every photo affordance (meal photo, label scan). A wrong
/// `true` sends image bytes to a text-only endpoint and fails the call; a wrong `false` hides
/// a working feature — so the allowlist is pinned here.
final class ProviderVisionTests: XCTestCase {

    func testMultimodalCloudProvidersSupportVision() {
        XCTAssertTrue(Providers.supportsVision(provider: "anthropic", model: "sonnet46"))
        XCTAssertTrue(Providers.supportsVision(provider: "openai", model: "gpt5"))
        XCTAssertTrue(Providers.supportsVision(provider: "gemini", model: "g31flash"))
    }

    func testTextOnlyProvidersDoNotSupportVision() {
        XCTAssertFalse(Providers.supportsVision(provider: "apple", model: "apple-od"))
        XCTAssertFalse(Providers.supportsVision(provider: "deepseek", model: "deepseek-chat"))
        XCTAssertFalse(Providers.supportsVision(provider: "nonsense", model: "whatever"))
    }

    func testOpenRouterDependsOnTheModel() {
        XCTAssertTrue(Providers.supportsVision(provider: "openrouter", model: "or-claude-sonnet"))
        XCTAssertTrue(Providers.supportsVision(provider: "openrouter", model: "or-gemini-flash"))
        XCTAssertFalse(Providers.supportsVision(provider: "openrouter", model: "or-llama"))
    }

    func testLocalModelsAreAllowlistedByName() {
        XCTAssertTrue(Providers.supportsVision(provider: "ollama", model: "ollama-llava"))
        XCTAssertFalse(Providers.supportsVision(provider: "ollama", model: "ollama-qwen"))
        XCTAssertFalse(Providers.supportsVision(provider: "ollamacloud", model: "oc-gptoss"))
        XCTAssertTrue(Providers.supportsVision(provider: "ollama", model: "custom", custom: "qwen2.5-vl:7b"))
        XCTAssertFalse(Providers.supportsVision(provider: "ollama", model: "custom", custom: "mistral"))
    }
}
