import Foundation

/// Public `hooks/list` evidence, never a private trust-key or hash parser. This source only
/// verifies setup; it cannot admit a Thread or manufacture a Hook delivery receipt.
actor CodexHookActivation {
    private let paths: HookIntegrationPaths
    private let clock: any MonitorClock
    nonisolated private let configuration: DirectoryChangeWatcher
    nonisolated private let definitions: DirectoryChangeWatcher
    private var generation = 0
    /// Bumped only by `stop`: a read retired by a newer one joins it, one retired by a disconnect stops.
    private var lifetime = 0
    private var cached: (revision: [UInt64], verified: Bool?, retryAt: Date?)?
    private var pending: Task<Bool?, Never>?
    private var pendingRevision: [UInt64]?

    init(paths: HookIntegrationPaths, clock: any MonitorClock) {
        self.paths = paths
        self.clock = clock
        configuration = DirectoryChangeWatcher(
            directoryURL: paths.hooksConfiguration.deletingLastPathComponent()
                .appendingPathComponent("config.toml"),
            debounceInterval: 0.15, absenceIsExpected: true
        )
        definitions = DirectoryChangeWatcher(directoryURL: paths.hooksConfiguration,
                                             debounceInterval: 0.15, absenceIsExpected: true)
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        DirectoryChangeWatcher.merged([configuration.events(), definitions.events()])
    }

    private func revision() -> [UInt64] {
        configuration.resume()
        definitions.resume()
        return [configuration.changeCount, definitions.changeCount]
    }

    func invalidate() {
        generation += 1
        pending?.cancel()
        pending = nil
        pendingRevision = nil
        cached = nil
    }

    func stop() {
        invalidate()
        lifetime += 1
        configuration.pause()
        definitions.pause()
    }

    func nextDeadline() -> Date? { pending == nil ? cached?.retryAt : nil }

    /// Unsupported servers retain the legacy delivery-based activation rule. An available API
    /// that reports incomplete setup, malformed data or a failed read never verifies activation.
    func verified(using client: any CodexAppServerCommunicating) async -> Bool? {
        let life = lifetime
        // A retired read reported `false`, drawing a trusted row `not yet verified` for up to the
        // request's 3 s; join the read that retired it instead, as `ProductConnectionMonitor` does.
        for _ in 0..<3 {
            let stamp = revision()
            if let cached, cached.revision == stamp,
               cached.retryAt.map({ $0 > clock.now() }) ?? true {
                return cached.verified
            }
            if pending != nil, pendingRevision != stamp { invalidate() }
            let epoch = generation
            let paths = paths
            let request = pending ?? Task<Bool?, Never> {
                do {
                    let response = try await client.request(
                        method: "hooks/list",
                        params: .object(["cwds": .array([
                            .string(paths.hooksConfiguration.deletingLastPathComponent().path)
                        ])]),
                        timeoutNanoseconds: 3_000_000_000
                    )
                    return Self.allManagedHooksAreTrusted(in: response, paths: paths)
                } catch let error as CodexAppServerError where error.isUnsupportedMethod {
                    return nil
                } catch {
                    return false
                }
            }
            pending = request
            pendingRevision = stamp
            let value = await request.value
            guard generation == epoch else {
                guard life == lifetime, !Task.isCancelled else { break }
                continue
            }
            pending = nil
            pendingRevision = nil
            // An edit during the request invalidates that response, even if it said "trusted".
            guard revision() == stamp else {
                cached = (revision(), false, clock.now().addingTimeInterval(5))
                return false
            }
            cached = (stamp, value, value == false ? clock.now().addingTimeInterval(5) : nil)
            return value
        }
        return false
    }

    nonisolated static func allManagedHooksAreTrusted(in response: JSONValue,
                                                      paths: HookIntegrationPaths) -> Bool {
        guard let entries = response["data"]?.arrayValue, entries.count == 1,
              let entry = entries.first,
              entry["cwd"]?.stringValue == paths.hooksConfiguration.deletingLastPathComponent().path,
              let errors = entry["errors"]?.arrayValue, errors.isEmpty,
              entry["warnings"]?.arrayValue != nil,
              let hooks = entry["hooks"]?.arrayValue else { return false }
        let command = CodexHookRegistrar.command(forHelper: paths.hookHelper)
        return CodexHookVocabulary().managedDefinitions.allSatisfy { definition in
            let event = definition.event.prefix(1).lowercased() + definition.event.dropFirst()
            let expectedCommand = definition.argument.map { "\(command) \($0)" } ?? command
            let matching = hooks.filter {
                $0["sourcePath"]?.stringValue == paths.hooksConfiguration.path
                    && $0["eventName"]?.stringValue == event
                    && $0["command"]?.stringValue == expectedCommand
            }
            guard matching.count == 1, let hook = matching.first else { return false }
            return hook["source"]?.stringValue == "user"
                && hook["handlerType"]?.stringValue == "command"
                && hook["enabled"]?.boolValue == true
                && hook["trustStatus"]?.stringValue == "trusted"
                && hook["matcher"] == (definition.matcher.map(JSONValue.string) ?? .null)
                && hook["timeoutSec"] == .number(Double(definition.timeoutSeconds))
                && (hook["async"] == nil || hook["async"] == .bool(false))
        }
    }
}
