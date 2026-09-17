import Foundation
import Testing
@testable import Notchline

/// A read Trae row across the companion connection dropping and coming back, through the real
/// socket, boundary, runtime and read gate.
@MainActor
struct TraeReconnectTests {
    private let thread = String(repeating: "a", count: 24)

    private func eventually(_ check: () async -> Bool) async -> Bool {
        for _ in 0..<300 { if await check() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
        return false
    }

    /// Reported 2026-09-16: two read Trae rows were back, unread, after a night with the lid shut.
    /// Waking expires the connection's 35 s lease; while it was down the rows drew nothing and the
    /// gate forgot them, and the reconnect's baseline re-sends every Thread Notchline kept.
    @Test func aReadRowStaysRetiredWhenTheCompanionReconnects() async throws {
        let directory = URL(fileURLWithPath: "/tmp/nl-rc-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let peer = try Companion(directory: directory); defer { peer.stop() }
        let source = TraeSource(installation: TraeInstallation(directory: directory))
        let front = Front()
        let runtime = ProductMonitoringRuntime(
            agent: .trae, lifecycle: Lifecycle(repository: source.repository),
            sessions: SeparateSessionReading(presence: Open(), admission: AdmitsEveryObservedThread()),
            rowContent: source,
            readEvidence: TraeReadEvidence(screen: Screen(), foreground: front, transport: source.transport))
        source.transport.start(); defer { source.transport.stop() }
        func rows() async -> [MonitoredSession] { await runtime.fetchSnapshot(dismissedRowIDs: []).sessions }

        #expect(await eventually { await source.transport.reading().0 })
        peer.command("start \(thread)")
        #expect(await eventually { await rows().first?.status == .running })
        peer.command("complete \(thread)")
        #expect(await eventually { await rows().first?.status == .completed }, "Unread while Trae is behind")
        peer.command("focus \(thread)")
        await front.set(true)
        #expect(await eventually { await rows().isEmpty }, "Read once Trae shows it")
        await front.set(false)

        peer.command("drop")
        #expect(await eventually { await !source.transport.reading().0 })
        #expect(await rows().isEmpty)
        // Any change to the directory makes the transport look for peers again.
        try Data().write(to: directory.appendingPathComponent("rescan"))
        #expect(await eventually { peer.watches == 2 })
        #expect(peer.retained == [thread], "The reconnect asks for the Thread back")
        #expect(await eventually { await source.transport.route(for: thread) != nil })
        #expect(await rows().isEmpty, "A read row does not come back unread")
        #expect(await runtime.nextRefreshDeadline() == nil, "and books no re-check")
    }

    private struct Lifecycle: MonitoringLifecycleSource {
        let repository: MonitoringRepository
        func gate(productName: String) async -> MonitoringSourceGate { .open(.active) }
        func disconnect() {}
    }
    private struct Open: ProductPresenceReporting {
        func presence() async -> AgentPresence { .open }
    }
    private struct Screen: ScreenAvailabilityReporting {
        func isAvailable() -> Bool { true }
        func changeEvents() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    }
    private actor Front: DesktopReadingReporting {
        private var value = false
        func set(_ value: Bool) { self.value = value }
        func isInFrontOfTheUser() -> Bool { value }
    }

    /// The companion's wire behaviour: a baseline carries running Threads and the ones the watch
    /// asked to keep, as `trae-renderer.js` does.
    private final class Companion {
        private let process = Process()
        private let input = Pipe()
        private let prefix: String
        var watches: Int {
            (try? FileManager.default.contentsOfDirectory(atPath: (prefix as NSString).deletingLastPathComponent))?
                .filter { $0.hasPrefix((prefix as NSString).lastPathComponent + ".watch") }.count ?? 0
        }
        var retained: [String] {
            (try? JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: prefix + ".retained")))) ?? []
        }
        init(directory: URL) throws {
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-u", "-c", Self.script, directory.path]
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            prefix = directory.appendingPathComponent(String(process.processIdentifier)).path
            guard output.fileHandleForReading.readData(ofLength: 1) == Data([82]) else { stop(); throw TraeBridgeError.unavailable }
        }
        func command(_ command: String) { try? input.fileHandleForWriting.write(contentsOf: Data((command + "\n").utf8)) }
        func stop() { try? input.fileHandleForWriting.close(); if process.isRunning { process.terminate(); process.waitUntilExit() } }
        private static let script = #"""
        import os,socket,json,sys,time,threading
        prefix=sys.argv[1]+'/'+str(os.getpid())
        listener=socket.socket(socket.AF_UNIX);listener.bind(prefix+'.sock');os.chmod(prefix+'.sock',0o600);listener.listen(8)
        lock=threading.Lock()
        state={'watch':None,'seq':0,'rows':{},'retained':[],'focus':None,'watches':0}
        def emit(c,x):c.sendall((json.dumps(x)+'\n').encode())
        def snapshot(rows,baseline=False):
          if state['watch'] is None:return
          state['seq']=1 if baseline else state['seq']+1
          emit(state['watch'],dict(type='snapshot',schema=1,version='3.5.91',sequence=state['seq'],baseline=baseline,observedAt=time.time(),rows=rows))
        def handle(c):
          try:
            q=json.loads(c.makefile('rb').readline())
            if q['op']=='watch':
              with lock:
                state['watch']=c;state['retained']=q.get('retainedThreadIDs',[]);state['watches']+=1
                json.dump(state['retained'],open(prefix+'.retained','w'))
                emit(c,dict(type='hello',schema=1,version='3.5.91',bridgeVersion='1.2.3',pid=os.getpid()))
                snapshot([r for t,r in state['rows'].items() if r['status']=='in_progress' or t in state['retained']],baseline=True)
                open(prefix+'.watch'+str(state['watches']),'w').close()
              return
            if q['op']=='read':
              with lock:
                r=state['rows'].get(state['focus'])
                proof=dict(windowID=1,threadID=r['threadID'],turnID=r['turnID'],messageID=r['messageID'],observedAt=time.time()) if r else None
              emit(c,dict(ok=True,schema=1,version='3.5.91',reading=proof))
          except (OSError,ValueError):pass
          finally:
            if c is not state['watch']:c.close()
        def accept():
          while True:
            c,_=listener.accept();threading.Thread(target=handle,args=(c,),daemon=True).start()
        threading.Thread(target=accept,daemon=True).start();print('R',end='',flush=True)
        for line in sys.stdin:
          words=line.split()
          with lock:
            if words[0]=='start':
              t=words[1]
              state['rows'][t]=dict(threadID=t,turnID='b'*24,messageID='c'*24,userMessageID='d'*24,title='Native title',folder='/Projects/example',status='in_progress',startedAt=time.time(),endedAt=None,historical=False,preview='Working',requests=[])
              snapshot([state['rows'][t]])
            elif words[0]=='complete':
              r=state['rows'][words[1]];r['status']='completed';r['endedAt']=time.time();r['preview']='Done'
              snapshot([r])
            elif words[0]=='focus':state['focus']=words[1]
            elif words[0]=='drop':
              c=state['watch'];state['watch']=None
              if c:c.shutdown(socket.SHUT_RDWR);c.close()
        """#
    }
}
