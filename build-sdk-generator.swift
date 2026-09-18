#!/usr/bin/env swift
import Foundation

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
    try process.run()
    process.waitUntilExit()

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
try run("swift", ["build", "-c", "release"], in: generatorDirectory)
