import Darwin
import Foundation
import Testing
@testable import Notchline

@MainActor
struct TraeTransportTests {
    /// A private test directory and a real Unix peer exercise the production
    /// framing/ownership/epoch boundary without connecting to any user window.
    @Test func fragmentedFramesReachTheReducerAndCorruptionWithholdsTheRoute() async throws {
        let peer = try Peer(); defer { peer.stop() }
        let repository = MonitoringRepository(policy: .explicit)
        let transport = TraeBridgeTransport(directory: peer.directory, repository: repository)
        transport.start(); defer { transport.stop() }
        #expect(await eventually { await transport.reading().0 })
        peer.send("start")
        #expect(await eventually { await repository.drainDeliveredEvents().turns.first?.status == .approvalNeeded })
        let route = await transport.route(for: String(repeating: "1", count: 24))
        #expect(route?.hasSuffix("\(peer.process.processIdentifier).sock") == true)
        peer.send("corrupt")
        #expect(await eventually { !(await transport.reading().0) })
        #expect(await transport.route(for: String(repeating: "1", count: 24)) == nil)
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .approvalNeeded,
                "A parse failure withholds observation, never resolves a native wait")
        transport.stop()
        #expect(await transport.content().isEmpty)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    private final class Peer {
        let directory: URL
        let process = Process()
        private let input = Pipe()
        init() throws {
            directory = URL(fileURLWithPath: "/tmp/nl-trae-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-u", "-c", Self.script, directory.path]
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let ready = output.fileHandleForReading.readData(ofLength: 1)
            guard ready == Data([82]) else { stop(); throw TraeBridgeError.unavailable }
        }
        func send(_ value: String) { try? input.fileHandleForWriting.write(contentsOf: Data((value + "\n").utf8)) }
        func stop() {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            try? FileManager.default.removeItem(at: directory)
        }
        private static let script = #"""
        import os,socket,json,sys,time
        s=socket.socket(socket.AF_UNIX);p=sys.argv[1]+'/'+str(os.getpid())+'.sock'
        s.bind(p);os.chmod(p,0o600);s.listen(1);print('R',end='',flush=True)
        c,_=s.accept();q=json.loads(c.makefile('rb').readline());assert q['op']=='watch' and q['schema']==1
        def emit(f):
          b=(json.dumps(f)+'\n').encode();c.sendall(b[:7]);time.sleep(.01);c.sendall(b[7:])
        emit(dict(type='hello',schema=1,version='3.5.91',bridgeVersion='1.2.1',pid=os.getpid()))
        now=time.time();sequence=1
        emit(dict(type='snapshot',schema=1,version='3.5.91',sequence=1,baseline=True,observedAt=now,rows=[]))
        for command in sys.stdin:
          if command.strip()=='corrupt':c.sendall(b'{broken}\n');break
          if command.strip()=='start':
            sequence+=1
            request=dict(id='5'*24,toolID='6'*24,producer='root',name='RunCommand',kind='command',command='printf test')
            row=dict(threadID='1'*24,turnID='2'*24,messageID='3'*24,userMessageID='4'*24,title='Test',preview=str(sequence),status='in_progress',startedAt=now+.1,historical=False,requests=[request])
            emit(dict(type='snapshot',schema=1,version='3.5.91',sequence=sequence,baseline=False,observedAt=now+.2,rows=[row]))
        """#
    }
}
