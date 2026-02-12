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

    // MARK: - Start / Stop

    @objc public func start(port: UInt16) throws {
        try server.start(port: Endpoint.Port(port))
        delegate?.serverDidStart?(self)
    }

    @objc public func stop() {
        server.stop()
        delegate?.serverDidStop?(self)
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
