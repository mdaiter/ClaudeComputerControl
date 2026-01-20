import Foundation
import AppAutomationCore

final class StreamCoordinator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.automation.streams")
    private var writers: [AutomationStreamToken: JSONRPCMessageWriter] = [:]
    private var timers: [AutomationStreamToken: DispatchSourceTimer] = [:]
    private var lastSnapshots: [AutomationStreamToken: AutomationSnapshot] = [:]

    func attach(writer: JSONRPCMessageWriter, token: AutomationStreamToken) {
        queue.sync {
            writers[token] = writer
        }
    }

    func detach(token: AutomationStreamToken) {
        queue.sync {
            if let timer = timers[token] {
                timer.cancel()
            }
            timers[token] = nil
            writers[token] = nil
            lastSnapshots[token] = nil
        }
    }

    func start(
        token: AutomationStreamToken,
        intervalMs: Int,
        onTick: @escaping () -> (AutomationSnapshot?, AutomationDiff?)
    ) -> Bool {
        let interval = max(intervalMs, 250)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(interval))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let (snapshot, diff) = onTick()
            if let snapshot {
                self.lastSnapshots[token] = snapshot
                self.send(token: token, event: .snapshot, payload: snapshot)
            }
            if let diff {
                self.send(token: token, event: .diff, payload: diff)
            }
        }
        timers[token] = timer
        timer.resume()
        return true
    }

    func send<T: Codable>(token: AutomationStreamToken, event: AutomationStreamEvent, payload: T) {
        guard let writer = queue.sync(execute: { writers[token] }) else {
            return
        }
        let envelope = JSONRPCStreamEvent(token: token.value, event: event.rawValue, data: payload)
        guard let data = try? JSONEncoder().encode(envelope) else {
            return
        }
        try? writer.sendRaw(data)
    }
}
