#!/usr/bin/env swift
import Foundation
import Glibc
import Synchronization

enum ScriptError: Error, CustomStringConvertible {
    case commandFailed(String, Int32)

    var description: String {
        switch self {
        case .commandFailed(let command, let status):
            return "Command failed with exit status \(status): \(command)"
        }
    }
}

func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments
    process.currentDirectoryURL = directory

    let interruptedBySIGINT = Atomic<Bool>(false)
    let interruptSource = DispatchSource.makeSignalSource(
        signal: SIGINT,
        queue: DispatchQueue.global()
    )
    interruptSource.setEventHandler {
        if process.isRunning {
            _ = interruptedBySIGINT.exchange(true, ordering: .relaxed)
            process.interrupt()
        }
    }
    signal(SIGINT, SIG_IGN)
    interruptSource.resume()
    defer {
        interruptSource.cancel()
        signal(SIGINT, SIG_DFL)
    }

    try process.run()
    process.waitUntilExit()

    // Print special message that we got interrupted
    let wasInterrupted = interruptedBySIGINT.load(ordering: .relaxed)
    if wasInterrupted {
        print("\nProcess was interrupted by SIGINT, exiting now...")
        return
    }

    guard process.terminationStatus == 0 else {
        throw ScriptError.commandFailed(([executable] + arguments).joined(separator: " "), process.terminationStatus)
    }
}

let fileManager = FileManager.default
let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let generatorDirectory = workingDirectory.appendingPathComponent("swift-sdk-generator", isDirectory: true)

// Clone the generator if needed
if !fileManager.fileExists(atPath: generatorDirectory.path) {
    print("Cloning SDK generator...")
    try run("git", ["clone", "https://github.com/swiftlang/swift-sdk-generator.git"])
}

// Pull and rebuild the generator in release mode
print("Checking for SDK generator updates and rebuilding...")
try run("git", ["pull", "origin"], in: generatorDirectory)
print("NOTE: Using --static-swift-stdlib so it is easy to switch host Swift versions without rebuilding the generator.")
try run("swift", ["build", "-c", "release", "--static-swift-stdlib"], in: generatorDirectory)
