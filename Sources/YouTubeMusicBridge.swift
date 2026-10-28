import Foundation
import Network

/// Local WebSocket (ws://127.0.0.1:47811) that the "Islet for YouTube Music" Chrome extension connects to.
/// The extension pushes playback state; Islet sends back playback commands.
/// Only loopback connections whose Origin is a Chrome extension are accepted.
final class YouTubeMusicBridge {
    struct State: Decodable, Equatable {
        let playing: Bool
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let artwork: String
        /// Songs after this one (extension 1.4 and later).
        let queue: [QueueEntry]?
    }

    struct QueueEntry: Decodable, Equatable {
        let index: Int
        let title: String
        let artist: String
        let artwork: String
        let duration: String
    }

    private struct Message: Decodable {
        let type: String
        let state: State?
    }

    static let port: NWEndpoint.Port = 47811

    /// Called on the main queue when the track, artist or play state changes.
    var onChange: (() -> Void)?

    private let queue = DispatchQueue(label: "islet.youtube-bridge")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:] // only touched on `queue`
    private var latest: (state: State, receivedAt: Date)?           // only touched on `queue`
    private var pingTimer: DispatchSourceTimer?

    init() {
        start()
    }

    /// Latest state and when it arrived. Dropped after two minutes without news.
    func current() -> (state: State, receivedAt: Date)? {
        queue.sync {
            guard let latest, Date().timeIntervalSince(latest.receivedAt) < 120 else { return nil }
            return latest
        }
    }

    func send(_ command: PlayerCommand) {
        var payload: [String: Any] = ["type": "command"]
        switch command {
        case .playPause: payload["command"] = "playPause"
        case .next: payload["command"] = "next"
        case .previous: payload["command"] = "previous"
        case .focus: payload["command"] = "focus"
        case .playItem(let index, let title):
            payload["command"] = "playQueueItem"
            payload["value"] = index
            payload["title"] = title
        case .seek(let s):
            payload["command"] = "seek"
            payload["value"] = s
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        queue.async { self.broadcast(data) }
    }

    // MARK: Server

    private func start() {
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.setClientRequestHandler(queue) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let allowed = origin.hasPrefix("chrome-extension://")
            if !allowed { NSLog("%@", "Islet music [bridge] rejected connection from origin '\(origin)'") }
            return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject, subprotocol: nil, additionalHeaders: nil)
        }
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    NSLog("%@", "Islet music [bridge] listener failed: \(error)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("%@", "Islet music [bridge] could not start: \(error)")
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20, repeating: 20)
        timer.setEventHandler { [weak self] in
            self?.broadcast(Data(#"{"type":"ping"}"#.utf8))
        }
        timer.resume()
        pingTimer = timer
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                NSLog("%@", "Islet music [bridge] extension connected")
            case .failed, .cancelled:
                self?.drop(id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self else { return }
            let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if error != nil || meta?.opcode == .close {
                connection.cancel()
                return
            }
            if let data, !data.isEmpty { self.handle(data) }
            self.receive(on: connection)
        }
    }

    private func drop(_ id: ObjectIdentifier) {
        guard connections.removeValue(forKey: id) != nil else { return }
        NSLog("%@", "Islet music [bridge] extension disconnected")
        if connections.isEmpty, latest != nil {
            latest = nil
            notify()
        }
    }

    private func handle(_ data: Data) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data), message.type == "state" else { return }
        let old = latest?.state
        if let state = message.state {
            latest = (state, Date())
        } else {
            latest = nil
        }
        let new = message.state
        if old?.title != new?.title || old?.artist != new?.artist || old?.playing != new?.playing {
            NSLog("%@", "Islet music [YouTube Music] \(new.map { "\($0.playing ? "playing" : "paused"): \($0.title) — \($0.artist) [\(TimerManager.format($0.position)) / \(TimerManager.format($0.duration))]" } ?? "(no track)")")
            notify()
        } else if old?.queue != new?.queue {
            notify()
        }
        if old?.queue?.count != new?.queue?.count {
            NSLog("%@", "Islet music [YouTube Music] queue: \(new?.queue.map { "\($0.count) next, first: \($0.first?.title ?? "-")" } ?? "not sent")")
        }
    }

    private func broadcast(_ data: Data) {
        let context = NWConnection.ContentContext(identifier: "message",
                                                  metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        for connection in connections.values {
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        }
    }

    private func notify() {
        DispatchQueue.main.async { self.onChange?() }
    }
}
