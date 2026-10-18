import Foundation
import Darwin
import LidLessCore
import os

/// The child owns the override. EOF on its private pipe restores sleep if the UI
/// exits, including a force quit. Nothing is installed or run as root.
final class WorkerSession: SleepOverride {
    private var process: Process?
    private var commands: FileHandle?
    private var replies: FileHandle?
    var isRunning: Bool { process?.isRunning == true }

    func start() throws {
        let input = Pipe()
        let output = Pipe()
        let child = Process()
        child.executableURL = Bundle.main.executableURL
        child.arguments = ["--hold-worker"]
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.standardError
        try child.run()
        process = child
        commands = input.fileHandleForWriting
        replies = output.fileHandleForReading
        // Only the child must retain these ends, so crashes produce EOF.
        input.fileHandleForReading.closeFile()
        output.fileHandleForWriting.closeFile()
        try receiveReply(expected: UInt8(ascii: "a"))
    }

    func refresh() throws {
        guard isRunning else { throw SessionError("The keep-awake worker stopped unexpectedly.") }
        try commands?.write(contentsOf: Data([UInt8(ascii: "r")]))
        try receiveReply(expected: UInt8(ascii: "r"))
    }

    func stop() throws {
        guard let process else { return }
        commands?.closeFile()
        commands = nil
        var failure: Error?
        do { try receiveReply(expected: UInt8(ascii: "s")) } catch { failure = error }
        if failure != nil {
            // Stop any in-flight reapplication before attempting fallback cleanup.
            if process.isRunning { process.terminate() }
            let deadline = Date().addingTimeInterval(1)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            guard !process.isRunning else {
                throw SessionError("Worker is not responding. Retry Disarm; restart the Mac if restoration keeps failing.")
            }
            try SystemPower().restoreLidSleep()
        }
        replies?.closeFile()
        replies = nil
        self.process = nil
    }

    private func receiveReply(expected: UInt8) throws {
        guard let replies else { throw SessionError("Keep-awake worker is unavailable.") }
        var descriptor = pollfd(fd: replies.fileDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&descriptor, 1, 3_000) > 0,
              let response = try replies.read(upToCount: 1), response == Data([expected]) else {
            throw SessionError("macOS did not confirm the power request. See Console for LidLess errors.")
        }
    }
}

func runWorker() -> Int32 {
    var power: SystemPower?
    func reply(_ response: UInt8) {
        try? FileHandle.standardOutput.write(contentsOf: Data([response]))
    }
    func report(_ error: Error) {
        Logger(subsystem: "dev.lid-less.app", category: "Power").error("\(error.localizedDescription, privacy: .public)")
        FileHandle.standardError.write(Data("LidLess: \(error.localizedDescription)\n".utf8))
    }
    do {
        let controller = try SystemPower()
        power = controller
        try controller.start()
        reply(UInt8(ascii: "a"))
        while let command = try FileHandle.standardInput.read(upToCount: 1), !command.isEmpty {
            guard command == Data([UInt8(ascii: "r")]) else { break }
            try controller.refresh()
            reply(UInt8(ascii: "r"))
        }
        try controller.stop()
        reply(UInt8(ascii: "s"))
        return 0
    } catch {
        report(error)
        do { try power?.stop() } catch { report(error) }
        reply(UInt8(ascii: "-"))
        return 1
    }
}
