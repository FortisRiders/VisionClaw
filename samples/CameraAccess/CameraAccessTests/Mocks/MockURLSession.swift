import Foundation

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

final class MockURLSession: URLSessionProtocol {
    enum Stub {
        case success(Data, URLResponse)
        case failure(Error)
    }

    var stub: Stub = .success(Data(), HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!)

    private(set) var capturedRequests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        switch stub {
        case .success(let data, let response):
            return (data, response)
        case .failure(let error):
            throw error
        }
    }

    func makeOpenClawResponse(content: String, statusCode: Int = 200) -> Stub {
        let json: [String: Any] = [
            "choices": [
                ["message": ["role": "assistant", "content": content]]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return .success(data, response)
    }
}
