import Foundation
import Testing
@testable import Notchline

/// Trae rows across the companion connection dropping and coming back, through the real socket,
/// boundary, runtime and read gate.
@MainActor
struct TraeReconnectTests {
    private func thread(_ n: Int) -> String { String(format: "%024x", n) }

    private func eventually(_ check: () async -> Bool) async -> Bool {
        for _ in 0..<500 { if await check() { return true }; try? await Task.sleep(for: .milliseconds(10)) }
        return false
    }

    /// Reported 2026-09-16: two read Trae rows were back, unread, after a night with the lid shut.
    /// Waking expires the connection's 35 s lease; while it was down the rows drew nothing and the
    /// gate forgot them, and the reconnect's baseline re-sent every Thread Notchline kept.
    @Test func aReadRowStaysRetiredWhenTheCompanionReconnects() async throws {
        let fixture = try Fixture(); defer { fixture.stop() }
        let thread = thread(0xa)
        #expect(await eventually { await fixture.source.transport.reading().0 })
        fixture.peer.command("start \(thread)")
        #expect(await eventually { await fixture.rows().first?.status == .running })
        fixture.peer.command("complete \(thread)")
        #expect(await eventually { await fixture.rows().first?.status == .completed }, "Unread while Trae is behind")
        fixture.peer.command("focus \(thread)")
        await fixture.front.set(true)
        #expect(await eventually { await fixture.rows().isEmpty }, "Read once Trae shows it")
        await fixture.front.set(false)

        try await fixture.reconnect()
        #expect(fixture.peer.retained.isEmpty, "A read Thread is not asked for again")
        // A companion re-sending it anyway, as a window with a stale view would, draws nothing.
        fixture.peer.command("resend \(thread)")
        #expect(await eventually { await fixture.source.transport.route(for: thread) != nil })
        #expect(await fixture.rows().isEmpty, "A read row does not come back unread")
        #expect(await fixture.runtime.nextRefreshDeadline() == nil, "and books no re-check")
    }

    /// A reconnect used to ask for every Thread ever observed, read or removed. The companion refuses
    /// a baseline of more than 128 rows (`capture` in `trae-renderer.js`) and retries with the same
    /// list, so once 129 Threads had run in one Trae lifetime, a wake left Trae unobserved for good.
    @Test func aReconnectAfterManyFinishedThreadsAsksOnlyForWhatIsStillListed() async throws {
        let fixture = try Fixture(); defer { fixture.stop() }
        let threads = (1...130).map(thread)
        let unread = threads[0], removed = threads[1], read = Array(threads.dropFirst(2))
        #expect(await eventually { await fixture.source.transport.reading().0 })
        fixture.peer.command("start " + threads.joined(separator: " "))
        #expect(await eventually { await fixture.rows().count == 130 })
        fixture.peer.command("complete " + threads.joined(separator: " "))
        #expect(await eventually { await fixture.rows().allSatisfy { $0.status == .completed } })

        let removedRow = try #require(await fixture.rows().first { $0.threadID == removed }).id
        await fixture.front.set(true)
        for (index, thread) in read.enumerated() {
            fixture.peer.command("focus \(thread)")
            #expect(await eventually {
                await fixture.rows(dismissing: [removedRow]).filter { read.contains($0.threadID) }.count == read.count - index - 1
            }, "Read \(thread)")
        }
        await fixture.front.set(false)
        #expect(await fixture.rows(dismissing: [removedRow]).contains { $0.threadID == unread })

        try await fixture.reconnect()
        #expect(fixture.peer.retained == [unread], "Only the unread row is asked for again")
        #expect(await eventually { await fixture.source.transport.reading().0 }, "Observation comes back")
        // The removed row is not listed either; nothing will draw it again.
        let rows = await fixture.rows(dismissing: [removedRow])
        #expect(rows.map(\.threadID) == [unread])
        #expect(rows.first { $0.threadID == unread }?.preview == "Done", "The unread row keeps its words")
        #expect(rows.first { $0.threadID == unread }?.status == .completed)

        fixture.peer.command("start \(thread(0x999))")
        #expect(await eventually { await fixture.rows().contains { $0.threadID == thread(0x999) && $0.status == .running } })
    }

    /// The runtime and transport of one Trae Provider, with a fake companion and injected foreground.
    @MainActor
    private final class Fixture {
        let directory = URL(fileURLWithPath: "/tmp/nl-rc-\(UUID())")
        let peer: Companion
        let source: TraeSource
        let front: Front
        let runtime: ProductMonitoringRuntime

        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            peer = try Companion(directory: directory)
            source = TraeSource(installation: TraeInstallation(directory: directory))
            front = Front()
            runtime = ProductMonitoringRuntime(
                agent: .trae, lifecycle: Lifecycle(repository: source.repository),
                sessions: SeparateSessionReading(presence: Open(), admission: AdmitsEveryObservedThread()),
                rowContent: source,
                readEvidence: TraeReadEvidence(screen: Screen(), foreground: front, transport: source.transport))
            source.transport.start()
        }
        func stop() {
            source.transport.stop(); peer.stop()
            try? FileManager.default.removeItem(at: directory)
        }
        func rows(dismissing dismissed: Set<String> = []) async -> [MonitoredSession] {
            await runtime.fetchSnapshot(dismissedRowIDs: dismissed).sessions
        }
        /// What waking does: the connection goes, one refresh sees it gone, and the transport watches again.
        func reconnect() async throws {
            let watches = peer.watches
            peer.command("drop")
            var waited = 0
            while await source.transport.reading().0, waited < 500 { try await Task.sleep(for: .milliseconds(10)); waited += 1 }
            _ = await rows()
            // Any change to the directory makes the transport look for peers again.
            try Data().write(to: directory.appendingPathComponent("rescan-\(watches)"))
            waited = 0
            while peer.watches == watches, waited < 500 { try await Task.sleep(for: .milliseconds(10)); waited += 1 }
        }
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
    /// asked to keep, and more than 128 rows makes it unavailable instead, as `trae-renderer.js` does.
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
        state={'watch':None,'seq':0,'rows':{},'retained':[],'focus':None,'watches':0,'held':[]}
        def emit(c,x):c.sendall((json.dumps(x)+'\n').encode())
        def snapshot(rows,baseline=False):
          if state['watch'] is None:return
          for i in range(0,max(len(rows),1),100):
            state['seq']=1 if baseline else state['seq']+1
            emit(state['watch'],dict(type='snapshot',schema=1,version='3.5.91',sequence=state['seq'],baseline=baseline,observedAt=time.time(),rows=rows[i:i+100]))
            baseline=False
        def handle(c):
          try:
            q=json.loads(c.makefile('rb').readline())
            if q['op']=='watch':
              with lock:
                state['held'].append(c);state['retained']=q.get('retainedThreadIDs',[]);state['watches']+=1
                json.dump(state['retained'],open(prefix+'.retained','w'))
                emit(c,dict(type='hello',schema=1,version='3.5.91',bridgeVersion='1.2.3',pid=os.getpid()))
                rows=[r for t,r in state['rows'].items() if r['status']=='in_progress' or t in state['retained']]
                if len(rows)>128:
                  state['watch']=None
                  emit(c,dict(type='unavailable',error='Trae companion is not ready. Reopen the Trae window if this persists.'))
                else:
                  state['watch']=c
                  state['seq']=1
                  emit(c,dict(type='snapshot',schema=1,version='3.5.91',sequence=1,baseline=True,observedAt=time.time(),rows=rows))
                open(prefix+'.watch'+str(state['watches']),'w').close()
              return
            if q['op']=='read':
              with lock:
                r=state['rows'].get(state['focus'])
                proof=dict(windowID=1,threadID=r['threadID'],turnID=r['turnID'],messageID=r['messageID'],observedAt=time.time()) if r else None
              emit(c,dict(ok=True,schema=1,version='3.5.91',reading=proof))
          except (OSError,ValueError):pass
          finally:
            if c not in state['held']:c.close()
        def accept():
          while True:
            c,_=listener.accept();threading.Thread(target=handle,args=(c,),daemon=True).start()
        threading.Thread(target=accept,daemon=True).start();print('R',end='',flush=True)
        for line in sys.stdin:
          words=line.split()
          with lock:
            if words[0]=='start':
              for t in words[1:]:
                state['rows'][t]=dict(threadID=t,turnID='b'*24,messageID='c'*24,userMessageID='d'*24,title='Native title',folder='/Projects/example',status='in_progress',startedAt=time.time(),endedAt=None,historical=False,preview='Working',requests=[])
              snapshot([state['rows'][t] for t in words[1:]])
            elif words[0]=='complete':
              for t in words[1:]:
                r=state['rows'][t];r['status']='completed';r['endedAt']=time.time();r['preview']='Done'
              snapshot([state['rows'][t] for t in words[1:]])
            elif words[0]=='resend':snapshot([state['rows'][t] for t in words[1:]])
            elif words[0]=='focus':state['focus']=words[1]
            elif words[0]=='drop':
              c=state['watch'];state['watch']=None
              if c:c.shutdown(socket.SHUT_RDWR);c.close()
        """#
    }
}
