import Foundation
import Telegraph

// MARK: - ObjC-compatible HTTP Method

@objc public enum TelegraphHTTPMethod: Int {
    case get
    case post
    case put
    case delete
    case patch
    case head
    case options
}

// MARK: - ObjC-compatible HTTP Request

@objc public class TelegraphHTTPRequest: NSObject {
    @objc public let method: String
    @objc public let path: String
    @objc public let headers: [String: String]

    init(method: String, path: String, headers: [String: String]) {
        self.method = method
        self.path = path
        self.headers = headers
    }
}

// MARK: - ObjC-compatible HTTP Response builder

@objc public class TelegraphHTTPResponse: NSObject {
    @objc public var statusCode: Int
    @objc public var headers: [String: String]
    @objc public var body: Data?

    @objc public init(statusCode: Int) {
        self.statusCode = statusCode
        self.headers = [:]
        self.body = nil
    }

    @objc public convenience init(statusCode: Int, body: String) {
        self.init(statusCode: statusCode)
        self.body = body.data(using: .utf8)
        self.headers["Content-Type"] = "text/plain; charset=utf-8"
    }

    @objc public convenience init(statusCode: Int, json: String) {
        self.init(statusCode: statusCode)
        self.body = json.data(using: .utf8)
        self.headers["Content-Type"] = "application/json; charset=utf-8"
    }
}

// MARK: - WebSocket Message

@objc public class TelegraphWebSocketMessage: NSObject {
    @objc public let text: String?
    @objc public let data: Data?

    init(text: String) {
        self.text = text
        self.data = nil
    }

    init(data: Data) {
        self.text = nil
        self.data = data
    }
}

// MARK: - Delegate Protocol

@objc public protocol TelegraphServerDelegate: AnyObject {
    /// Called when the server starts successfully
    @objc optional func serverDidStart(_ server: TelegraphServerWrapper)

    /// Called when the server stops
    @objc optional func serverDidStop(_ server: TelegraphServerWrapper)

    /// Called when the server encounters an error
    @objc optional func server(_ server: TelegraphServerWrapper, didFailWithError error: Error)

    /// Called for every incoming HTTP request not matched by a registered route.
    /// Return a TelegraphHTTPResponse or nil to send a 404.
    @objc optional func server(
        _ server: TelegraphServerWrapper,
        didReceiveRequest request: TelegraphHTTPRequest
    ) -> TelegraphHTTPResponse?

    // MARK: WebSocket delegate methods

    /// Called when a WebSocket client connects
    @objc optional func server(
        _ server: TelegraphServerWrapper,
        webSocketDidConnect webSocketID: String,
        path: String
    )

    /// Called when a WebSocket client disconnects
    @objc optional func server(
        _ server: TelegraphServerWrapper,
        webSocketDidDisconnect webSocketID: String,
        error: Error?
    )

    /// Called when a WebSocket message is received
    @objc optional func server(
        _ server: TelegraphServerWrapper,
        webSocket webSocketID: String,
        didReceiveMessage message: TelegraphWebSocketMessage
    )
}

// MARK: - Route Handler Block Type

public typealias TelegraphRouteHandler = (TelegraphHTTPRequest) -> TelegraphHTTPResponse

// MARK: - Main Wrapper

@objc public class TelegraphServerWrapper: NSObject {

    // MARK: Private state

    private var server: Server
    private var routeHandlers: [(method: HTTPMethod, path: String, handler: TelegraphRouteHandler)] = []

    // WebSocket tracking: Telegraph uses connection objects, we map them to string IDs
    private var webSocketConnections: [ObjectIdentifier: (connection: WebSocketConnection, id: String)] = [:]
    private var webSocketConnectionsByID: [String: WebSocketConnection] = [:]

    // MARK: Public

    @objc public weak var delegate: TelegraphServerDelegate?

    @objc public var port: Int {
        return Int(server.port)
    }

    @objc public var isRunning: Bool {
        return server.isRunning
    }

    // MARK: Init

    @objc public override init() {
        self.server = Server()
        super.init()
        setupServerDelegates()
    }

    /// Init with TLS using a p12 certificate identity
    @objc public init(p12URL: URL, passphrase: String) throws {
        let identity = try CertificateIdentity(p12URL: p12URL, passphrase: passphrase)
        self.server = Server(identity: identity)
        super.init()
        setupServerDelegates()
    }

    // MARK: - Start / Stop

    @objc public func start(port: UInt16) throws {
        try server.start(port: port)
        delegate?.serverDidStart?(self)
    }

    @objc public func stop() {
        server.stop()
        delegate?.serverDidStop?(self)
    }

    // MARK: - Routing

    /// Register a GET route. Handler block receives the request and returns a response.
    @objc public func get(_ path: String, handler: @escaping (TelegraphHTTPRequest) -> TelegraphHTTPResponse) {
        addRoute(method: .get, path: path, handler: handler)
    }

    /// Register a POST route.
    @objc public func post(_ path: String, handler: @escaping (TelegraphHTTPRequest) -> TelegraphHTTPResponse) {
        addRoute(method: .post, path: path, handler: handler)
    }

    /// Register a PUT route.
    @objc public func put(_ path: String, handler: @escaping (TelegraphHTTPRequest) -> TelegraphHTTPResponse) {
        addRoute(method: .put, path: path, handler: handler)
    }

    /// Register a DELETE route.
    @objc public func delete(_ path: String, handler: @escaping (TelegraphHTTPRequest) -> TelegraphHTTPResponse) {
        addRoute(method: .delete, path: path, handler: handler)
    }

    // MARK: - WebSocket

    /// Send a text message to a connected WebSocket client by ID
    @objc public func sendText(_ text: String, toWebSocket webSocketID: String) {
        guard let connection = webSocketConnectionsByID[webSocketID] else { return }
        connection.send(text: text)
    }

    /// Send binary data to a connected WebSocket client by ID
    @objc public func sendData(_ data: Data, toWebSocket webSocketID: String) {
        guard let connection = webSocketConnectionsByID[webSocketID] else { return }
        connection.send(data: data)
    }

    /// Disconnect a WebSocket client by ID
    @objc public func disconnectWebSocket(_ webSocketID: String) {
        guard let connection = webSocketConnectionsByID[webSocketID] else { return }
        connection.close(immediately: false)
    }

    /// Returns all currently connected WebSocket IDs
    @objc public var connectedWebSocketIDs: [String] {
        return Array(webSocketConnectionsByID.keys)
    }
}

// MARK: - Private helpers

private extension TelegraphServerWrapper {

    func addRoute(method: HTTPMethod, path: String, handler: @escaping TelegraphRouteHandler) {
        routeHandlers.append((method: method, path: path, handler: handler))
        server.route(method, path) { [weak self] request -> HTTPResponse in
            guard let self = self else {
                return HTTPResponse(.internalServerError)
            }
            let wrappedRequest = self.wrap(request: request)
            let wrappedResponse = handler(wrappedRequest)
            return self.unwrap(response: wrappedResponse)
        }
    }

    func wrap(request: HTTPRequest) -> TelegraphHTTPRequest {
        var headers: [String: String] = [:]
        for (key, value) in request.headers {
            headers[key.rawValue] = value.rawValue
        }
        return TelegraphHTTPRequest(
            method: request.method.rawValue,
            path: request.uri.path,
            headers: headers
        )
    }

    func unwrap(response: TelegraphHTTPResponse) -> HTTPResponse {
        let status = HTTPStatusCode(rawValue: response.statusCode) ?? .ok
        var httpResponse = HTTPResponse(status)
        if let body = response.body {
            httpResponse.body = body
        }
        for (key, value) in response.headers {
            httpResponse.headers[HTTPHeaderName(key)] = HTTPHeaderValue(value)
        }
        return httpResponse
    }

    func setupServerDelegates() {
        server.delegate = self
        server.webSocketDelegate = self
    }

    func makeWebSocketID(for connection: WebSocketConnection) -> String {
        let key = ObjectIdentifier(connection)
        if let existing = webSocketConnections[key] {
            return existing.id
        }
        let newID = UUID().uuidString
        webSocketConnections[key] = (connection: connection, id: newID)
        webSocketConnectionsByID[newID] = connection
        return newID
    }

    func removeWebSocket(_ connection: WebSocketConnection) {
        let key = ObjectIdentifier(connection)
        if let existing = webSocketConnections[key] {
            webSocketConnectionsByID.removeValue(forKey: existing.id)
            webSocketConnections.removeValue(forKey: key)
        }
    }
}

// MARK: - ServerDelegate

extension TelegraphServerWrapper: ServerDelegate {

    public func serverDidStop(_ server: Server, error: Error?) {
        if let error = error {
            delegate?.server?(self, didFailWithError: error)
        } else {
            delegate?.serverDidStop?(self)
        }
    }

    public func server(_ server: Server, didReceiveRequest request: HTTPRequest, error: Error?) {
        if let error = error {
            delegate?.server?(self, didFailWithError: error)
        }
    }
}

// MARK: - ServerWebSocketDelegate

extension TelegraphServerWrapper: ServerWebSocketDelegate {

    public func server(_ server: Server, webSocketDidConnect webSocket: WebSocketConnection, handshake: HTTPRequest) {
        let id = makeWebSocketID(for: webSocket)
        let path = handshake.uri.path
        delegate?.server?(self, webSocketDidConnect: id, path: path)
    }

    public func server(_ server: Server, webSocketDidDisconnect webSocket: WebSocketConnection, error: Error?) {
        let key = ObjectIdentifier(webSocket)
        let id = webSocketConnections[key]?.id ?? "unknown"
        delegate?.server?(self, webSocketDidDisconnect: id, error: error)
        removeWebSocket(webSocket)
    }

    public func server(_ server: Server, webSocket: WebSocketConnection, didReceiveMessage message: WebSocketMessage) {
        let id = makeWebSocketID(for: webSocket)
        let wrappedMessage: TelegraphWebSocketMessage
        switch message.payload {
        case .text(let text):
            wrappedMessage = TelegraphWebSocketMessage(text: text)
        case .binary(let data):
            wrappedMessage = TelegraphWebSocketMessage(data: data)
        default:
            return
        }
        delegate?.server?(self, webSocket: id, didReceiveMessage: wrappedMessage)
    }

    public func server(_ server: Server, webSocket: WebSocketConnection, didSendMessage message: WebSocketMessage) {
        // no-op — expose via delegate if needed
    }
}
