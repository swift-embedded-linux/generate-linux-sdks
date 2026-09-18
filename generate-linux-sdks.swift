#!/usr/bin/env swift
import Foundation
import Glibc
import Synchronization

struct ScriptError: Error, CustomStringConvertible {
    let message: String

    var description: String { message }
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
        let command = ([executable] + arguments).joined(separator: " ")
        throw ScriptError(message: "Command failed with exit status \(process.terminationStatus): \(command)")
    }
}

func requiredArgument(at index: Int, named name: String, in arguments: [String]) throws -> String {
    guard arguments.indices.contains(index), !arguments[index].isEmpty else {
        throw ScriptError(message: "You must provide a \(name).")
    }
    return arguments[index]
}

func generateSDK(
    targetArchitecture: String,
    swiftVersion: String,
    distributionName: String,
    distributionVersion: String,
    workingDirectory: URL,
    fileManager: FileManager
) throws {
    let sdkName = "\(swiftVersion)-RELEASE_\(distributionName)_\(distributionVersion)_\(targetArchitecture)"
    let bundleURL =
        workingDirectory
        .appendingPathComponent("Bundles", isDirectory: true)
        .appendingPathComponent("\(sdkName).artifactbundle", isDirectory: true)

    if fileManager.fileExists(atPath: bundleURL.path) {
        print("Swift SDK \(sdkName) already exists. Skipping generation.")
        return
    }

    print()
    print("==================================================================================")
    print("Generating Swift SDK \(sdkName)...")

    var generatorArguments = [
        "make-linux-sdk",
        "--swift-version", "\(swiftVersion)-RELEASE",
        "--distribution-name", distributionName,
        "--distribution-version", distributionVersion,
        "--target"
    ]

    if targetArchitecture == "armv7" {
        let downloadFilename = "swift-\(swiftVersion)-RELEASE-\(distributionName)-\(distributionVersion)-armv7-install"
        let downloadPath =
            workingDirectory
            .appendingPathComponent("Artifacts", isDirectory: true)
            .appendingPathComponent(downloadFilename, isDirectory: true)
        let archivePath = URL(fileURLWithPath: "\(downloadPath.path).tar.gz")
        let downloadURL =
            "https://github.com/swift-embedded-linux/armhf-debian/releases/download/\(swiftVersion)/\(downloadFilename).tar.gz"

        print("Downloading & extracting armv7 runtime...")
        try run("wget", ["-nc", "-nv", downloadURL, "-O", archivePath.path])
        if fileManager.fileExists(atPath: downloadPath.path) {
            try fileManager.removeItem(at: downloadPath)
        }
        try fileManager.createDirectory(at: downloadPath, withIntermediateDirectories: true)
        try run("tar", ["-xf", archivePath.path, "-C", downloadPath.path])

        generatorArguments += ["armv7-unknown-linux-gnueabihf", "--target-swift-package-path", downloadPath.path]
    } else {
        generatorArguments += ["\(targetArchitecture)-unknown-linux-gnu"]
    }

    try run("./.build/release/swift-sdk-generator", generatorArguments, in: workingDirectory)
}

let fileManager = FileManager.default
let rootDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let generatorDirectory = rootDirectory.appendingPathComponent("swift-sdk-generator", isDirectory: true)

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let swiftVersion = try requiredArgument(at: 0, named: "Swift version. E.g. 6.4.0", in: arguments)
    let distributionName = try requiredArgument(at: 1, named: "distribution name. E.g. ubuntu", in: arguments)
    let distributionVersion = try requiredArgument(at: 2, named: "distribution version. E.g. noble", in: arguments)

    guard fileManager.fileExists(atPath: generatorDirectory.path) else {
        throw ScriptError(message: "swift-sdk-generator not found. Please run build-sdk-generator.swift first.")
    }

    for targetArchitecture in ["x86_64", "aarch64", "armv7"] {
        try generateSDK(
            targetArchitecture: targetArchitecture,
            swiftVersion: swiftVersion,
            distributionName: distributionName,
            distributionVersion: distributionVersion,
            workingDirectory: generatorDirectory,
            fileManager: fileManager
        )
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
