import Foundation
import XCTest
@testable import macai

final class GeminiHandlerTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        URLProtocolStub.requestHandler = nil
    }

    func testGeminiHandlerStreamAccumulatesTextAndSignatureParts() async throws {
        URLProtocolStub.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello\"}]}}]}

            data: {\"candidates\":[{\"content\":{\"parts\":[{\"thoughtSignature\":\"sig\"}]}}]}

            data: [DONE]

            """
            return (response, Data(payload.utf8))
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: sessionConfig)

        let config = APIServiceConfig(
            name: "Gemini",
            apiUrl: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
            apiKey: "test-key",
            model: "gemini-3-pro"
        )
        let handler = GeminiHandler(config: config, session: session)

        let requestMessages: [[String: String]] = [
            [
                "role": "user",
                "content": "Hi",
            ],
        ]

        let stream = try await handler.sendMessageStream(requestMessages, temperature: 1.0)
        for try await _ in stream {}

        guard let parts = handler.consumeLastResponseParts() else {
            XCTFail("Expected parts to be captured from stream")
            return
        }

        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts.contains(where: { $0.text == "Hello" }))
        XCTAssertTrue(parts.contains(where: { $0.thoughtSignature == "sig" }))
    }

    func testGeminiHandlerPreservesSignatureOnlyPartInRequest() throws {
        let expectation = expectation(description: "Request captured")
        var capturedRequest: URLRequest?

        URLProtocolStub.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data("{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"ok\"}]}}]}".utf8)
            return (response, data)
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: sessionConfig)

        let config = APIServiceConfig(
            name: "Gemini",
            apiUrl: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
            apiKey: "test-key",
            model: "gemini-3-pro"
        )
        let handler = GeminiHandler(config: config, session: session)

        let envelope = PartsEnvelope(
            serviceType: "gemini",
            parts: [
                GeminiPartRequest(text: "Hello"),
                GeminiPartRequest(thoughtSignature: "sig"),
            ]
        )
        let messageParts = try JSONEncoder().encode(envelope).base64EncodedString()
        let requestMessages: [[String: String]] = [
            [
                "role": "assistant",
                "content": "Hello",
                "message_parts": messageParts,
            ],
            [
                "role": "user",
                "content": "Hi",
            ],
        ]

        handler.sendMessage(requestMessages, temperature: 1.0) { _ in
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        guard let request = capturedRequest,
              let body = requestBody(from: request) else {
            XCTFail("Missing request body")
            return
        }

        let json = try JSONSerialization.jsonObject(with: body, options: [])
        guard let payload = json as? [String: Any],
              let contents = payload["contents"] as? [[String: Any]] else {
            XCTFail("Unable to decode request contents")
            return
        }

        guard let modelContent = contents.first(where: { ($0["role"] as? String) == "model" }) else {
            XCTFail("Missing model role content")
            return
        }

        guard let parts = modelContent["parts"] as? [[String: Any]] else {
            XCTFail("Missing model parts")
            return
        }

        XCTAssertEqual(parts.count, 2)
        let textPart = parts.first { ($0["text"] as? String) == "Hello" }
        let signaturePart = parts.first { ($0["thoughtSignature"] as? String) == "sig" }

        XCTAssertNotNil(textPart)
        XCTAssertNil(textPart?["thoughtSignature"])
        XCTAssertNotNil(signaturePart)
        XCTAssertNil(signaturePart?["text"])
        XCTAssertNil(signaturePart?["inlineData"])
    }
}

private final class URLProtocolStub: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }
    stream.open()
    defer { stream.close() }
    let bufferSize = 1024
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data.isEmpty ? nil : data
}
