import Darwin
import Foundation
import Testing
@testable import Notchline

@MainActor
struct TraeReadTransportTests {
    private func eventually(_ check: () async -> Bool) async -> Bool {
        for _ in 0..<200 { if await check() { return true }; try? await Task.sleep(for:.milliseconds(10)) }
        return false
    }
    @Test func anotherPeerCanProveReadingWithoutTakingLifecycleOwnership() async throws {
        let directory = URL(fileURLWithPath:"/tmp/nl-tr-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let a = try Peer(directory:directory,window:1); defer { a.stop() }
        let repository = MonitoringRepository(policy:.explicit)
        let transport = TraeBridgeTransport(directory:directory,repository:repository)
        transport.start(); defer { transport.stop() }
        #expect(await eventually { await transport.route(for:String(repeating:"1",count:24)) != nil })
        let owner = await transport.route(for:String(repeating:"1",count:24))
        a.command("blur")
        let b = try Peer(directory:directory,window:2); defer { b.stop() }
        #expect(await eventually { b.watched })
        #expect(await eventually { await transport.readCompletions().first?.windowID == 2 })
        #expect(await transport.route(for:String(repeating:"1",count:24)) == owner)
        #expect(await repository.drainDeliveredEvents().turns.isEmpty,"Read queries never admit historical Turns")
        b.command("broken")
        #expect(await eventually { await transport.readCompletions().isEmpty })
        #expect(await transport.reading().0,"A malformed optional reply leaves lifecycle observation healthy")
    }
    @Test func lateReplyAfterDisconnectCannotBecomeReadEvidence() async throws {
        let directory = URL(fileURLWithPath:"/tmp/nl-tr-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let peer = try Peer(directory:directory,window:1,delay:0.25); defer { peer.stop() }
        let transport = TraeBridgeTransport(directory:directory,repository:MonitoringRepository(policy:.explicit))
        transport.start(); defer { transport.stop() }
        #expect(await eventually { await transport.reading().0 })
        let pending = Task { await transport.readCompletions() }
        #expect(await eventually { peer.queried })
        transport.stop()
        #expect(await pending.value.isEmpty)
    }
    /// Opt-in Release measurement of the production query/framing/boundary path.
    @Test func measureReadQueriesWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["NOTCHLINE_TRAE_READ_MEASURE"] == "1" else { return }
        let directory = URL(fileURLWithPath:"/tmp/nl-tm-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let peer = try Peer(directory:directory,window:1); defer { peer.stop() }
        let transport = TraeBridgeTransport(directory:directory,repository:MonitoringRepository(policy:.explicit))
        transport.start(); defer { transport.stop() }
        #expect(await eventually { await transport.reading().0 })
        func cpu() -> Double {
            var value = rusage(); getrusage(RUSAGE_SELF, &value)
            return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
                + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
        }
        let before = cpu(), start = Date()
        for _ in 0..<100 { #expect(await transport.readCompletions().count == 1) }
        print("TRAE_READ_MEASURE queries=100 cpuSeconds=\(cpu()-before) wallSeconds=\(Date().timeIntervalSince(start))")
    }
    private final class Peer {
        let process = Process()
        let directory: URL
        private let input = Pipe()
        var watched: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(process.processIdentifier).watched").path) }
        var queried: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(process.processIdentifier).queried").path) }
        init(directory:URL,window:Int,delay:Double=0) throws {
            self.directory=directory
            let output=Pipe()
            process.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
            process.arguments=["-u","-c",Self.script,directory.path,String(window),String(delay)]
            process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
            try process.run()
            guard output.fileHandleForReading.readData(ofLength:1)==Data([82]) else { stop();throw TraeBridgeError.unavailable }
        }
        func command(_ command:String) { try? input.fileHandleForWriting.write(contentsOf:Data((command+"\n").utf8)) }
        func stop() { try? input.fileHandleForWriting.close();if process.isRunning { process.terminate();process.waitUntilExit() } }
        private static let script = #"""
        import os,socket,json,sys,time,threading
        prefix=sys.argv[1]+'/'+str(os.getpid());window=int(sys.argv[2]);delay=float(sys.argv[3])
        listener=socket.socket(socket.AF_UNIX);listener.bind(prefix+'.sock');os.chmod(prefix+'.sock',0o600);listener.listen(8)
        state={'focused':True,'broken':False};watches=[]
        def emit(c,x):c.sendall((json.dumps(x)+'\n').encode())
        def handle(c):
          try:
            q=json.loads(c.makefile('rb').readline())
            if q['op']=='watch':
              watches.append(c)
              emit(c,dict(type='hello',schema=1,version='3.5.91',bridgeVersion='1.1.0',pid=os.getpid()))
              now=time.time()
              row=dict(threadID='1'*24,turnID='2'*24,messageID='3'*24,userMessageID='4'*24,title='Test',status='completed',startedAt=now-10,endedAt=now-3,historical=True,requests=[])
              emit(c,dict(type='snapshot',schema=1,version='3.5.91',sequence=1,baseline=True,observedAt=now,rows=[row]))
              open(prefix+'.watched','w').close()
              return
            if q['op']=='read':
              open(prefix+'.queried','w').close();time.sleep(delay)
              if state['broken']:c.sendall(b'{broken}\n')
              else:
                proof=dict(windowID=window,threadID='1'*24,turnID='2'*24,messageID='3'*24,observedAt=time.time()) if state['focused'] else None
                emit(c,dict(ok=True,schema=1,version='3.5.91',reading=proof))
          except (OSError,ValueError):pass
          finally:
            if c not in watches:c.close()
        def accept():
          while True:
            c,_=listener.accept();threading.Thread(target=handle,args=(c,),daemon=True).start()
        threading.Thread(target=accept,daemon=True).start();print('R',end='',flush=True)
        for command in sys.stdin:
          if command.strip()=='blur':state['focused']=False
          if command.strip()=='broken':state['broken']=True
        """#
    }
}
