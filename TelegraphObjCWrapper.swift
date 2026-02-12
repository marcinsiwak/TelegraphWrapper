import Foundation

// NOTE: This wrapper expects the Telegraph library to be added to the project (e.g., via Swift Package Manager)
// and imported in files that need it. We avoid a direct `import Telegraph` here to keep the file compiling
// even if Telegraph isn't yet linked. If Telegraph is available, uncomment the import below and the related code.
// import Telegraph

@objc public protocol TelegraphObjCWrapperDelegate: AnyObject {
    /// Called when the server successfully starts listening
    /// - Parameters:
    ///   - host: The host string (e.g., 0.0.0.0)
    ///   - port: The port number
    @objc optional func telegraphServerDidStart(host: String, port: Int)

    /// Called when the server stops (either intentionally or due to an error)
    /// - Parameter error: Optional error description
    @objc optional func telegraphServerDidStop(error: NSError?)

    /// Called when a WebSocket client connects
    /// - Parameter clientIdentifier: An opaque identifier for the client connection
    @objc optional func telegraphClientDidConnect(clientIdentifier: String)

    /// Called when a WebSocket client disconnects
    /// - Parameters:
    ///   - clientIdentifier: The same opaque identifier used on connect
    ///   - error: Optional error description
    @objc optional func telegraphClientDidDisconnect(clientIdentifier: String, error: NSError?)

    /// Called when a text message is received from a client
    /// - Parameters:
    ///   - clientIdentifier: The sender client identifier
    ///   - text: The text message
    @objc optional func telegraphDidReceiveText(clientIdentifier: String, text: String)
}

/// An Objective-C compatible wrapper for running a simple Telegraph WebSocket server.
/// This provides a minimal API surface. Extend as needed.
@objcMembers
public final class TelegraphObjCWrapper: NSObject {

    public weak var delegate: TelegraphObjCWrapperDelegate?

    // MARK: - Types

    private struct Client {
        let id: String
        // Replace `AnyObject` with the concrete Telegraph WebSocket type if available.
        weak var socket: AnyObject?
    }

    // MARK: - Internal State

    private var host: String = "0.0.0.0"
    private var port: Int = 8080

    // Replace these placeholders with real Telegraph types once available in your project.
    // private var server: HTTPServer?
    // private var websocketServer: WebSocketServer?

    private var clients: [String: Client] = [:]

    // MARK: - Lifecycle

    public override init() {
        super.init()
    }

    // MARK: - Public API

    /// Start a WebSocket server on the given host and port.
    /// If the server is already running, it will be stopped and restarted.
    /// - Parameters:
    ///   - host: Host string, default 0.0.0.0
    ///   - port: Port number
    /// - Returns: true if the server started successfully, false otherwise
    @discardableResult
    public func start(host: String = "0.0.0.0", port: Int) -> Bool {
        self.host = host
        self.port = port

        // Stop if already running
        stop()

        // In a real integration, set up Telegraph HTTP and WebSocket servers here.
        // The stubs below simulate success.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.telegraphServerDidStart?(host: host, port: port)
        }
        return true
    }

    /// Stop the server and disconnect all clients.
    public func stop() {
        // In a real integration, call server?.stop() and clean up sockets.
        let error: NSError? = nil
        clients.removeAll()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.telegraphServerDidStop?(error: error)
        }
    }

    /// Broadcast a text message to all connected clients.
    /// - Parameter text: The message to send
    public func broadcast(text: String) {
        // In a real integration, iterate over Telegraph WebSocket connections and send text.
        // Example when Telegraph is available:
        // for (_, client) in clients { (client.socket as? WebSocket)?.send(text: text) }
    }

    /// Send a text message to a specific client.
    /// - Parameters:
    ///   - clientIdentifier: The identifier obtained from connect callback
    ///   - text: The message to send
    /// - Returns: true if the client exists and the send was attempted
    @discardableResult
    public func send(to clientIdentifier: String, text: String) -> Bool {
        guard let client = clients[clientIdentifier] else { return false }
        // (client.socket as? AnyObject)?.perform(#selector(/* send */))
        _ = client
        return true
    }

    // MARK: - Helpers to integrate with Telegraph

    // The methods below demonstrate how you would wire Telegraph callbacks into the wrapper.
    // Replace the stubs once Telegraph is linked in your project.

    private func handleClientConnected(socket: AnyObject) {
        let id = UUID().uuidString
        clients[id] = Client(id: id, socket: socket)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.telegraphClientDidConnect?(clientIdentifier: id)
        }
    }

    private func handleClientDisconnected(id: String, error: Error?) {
        clients.removeValue(forKey: id)
        let nsError = (error as NSError?)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.telegraphClientDidDisconnect?(clientIdentifier: id, error: nsError)
        }
    }

    private func handleTextReceived(id: String, text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.telegraphDidReceiveText?(clientIdentifier: id, text: text)
        }
    }
}
