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

func normalizeSwiftVersion(_ version: String) -> String {
    if version == "6.4" {
        return "6.4.0"
    }
    return version
}

func hostSwiftVersion() throws -> String {
    let process = Process()
    let outputPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "--version"]
    process.standardOutput = outputPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw ScriptError(message: "Unable to determine the host Swift version.")
    }

    let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard
        let version =
            output
            .split(whereSeparator: \.isWhitespace)
            .drop(while: { $0 != "version" })
            .dropFirst()
            .first
    else {
        throw ScriptError(message: "Unable to parse the host Swift version from `swift --version`.")
    }
    return normalizeSwiftVersion(String(version))
}

func requiredArgument(at index: Int, named name: String, in arguments: [String]) throws -> String {
    guard arguments.indices.contains(index), !arguments[index].isEmpty else {
        throw ScriptError(message: "You must provide a \(name).")
    }
    return arguments[index]
}

func optionalArgument(at index: Int, named name: String, in arguments: [String]) -> String? {
    guard arguments.indices.contains(index), !arguments[index].isEmpty else {
        return nil
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

    print()
    print("==================================================================================")
    print("Generating Swift SDK \(sdkName)...")

    if fileManager.fileExists(atPath: bundleURL.path) {
        print("Swift SDK \(sdkName) already exists. Skipping generation.")
        return
    }

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
        try run("wget", ["-nc", "-nv", "-o", "/dev/null", downloadURL, "-O", archivePath.path])
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

func testSDK(
    targetArchitecture: String,
    swiftVersion: String,
    distributionName: String,
    distributionVersion: String,
    bundlesDirectory: URL,
    workingDirectory: URL,
    fileManager: FileManager
) throws {
    let sdkName = "\(swiftVersion)-RELEASE_\(distributionName)_\(distributionVersion)_\(targetArchitecture)"

    print()
    print("==================================================================================")
    print("Testing Swift SDK \(sdkName)...")

    let buildArguments = [
        "--swift-sdks-path", bundlesDirectory.path,
        "--swift-sdk", sdkName
    ]

    // 6.4 defaults to swiftbuild, which generates a different test runner than previous versions
    // which default to the native build system. We should not try to use swiftbuild with <6.4 as
    // it does not work correctly with Swift SDKs
    var testRunnerPath = workingDirectory.appendingPathComponent(".build/debug/test_projectPackageTests.xctest")
    if swiftVersion.hasPrefix("6.4") {
        testRunnerPath = workingDirectory.appendingPathComponent(".build/debug/test_projectTests-test-runner")
    }

    // Develop build + tests
    try run("swift", ["build", "-c", "debug", "--build-tests"] + buildArguments, in: workingDirectory)
    try run("file", [workingDirectory.appendingPathComponent(".build/debug/test_project").path], in: workingDirectory)
    try run(
        "file", [testRunnerPath.path],
        in: workingDirectory)

    // Release build
    try run("swift", ["build", "-c", "release"] + buildArguments, in: workingDirectory)
    try run("file", [workingDirectory.appendingPathComponent(".build/release/test_project").path], in: workingDirectory)
}

let fileManager = FileManager.default
let rootDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let generatorDirectory = rootDirectory.appendingPathComponent("swift-sdk-generator", isDirectory: true)

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    var swiftVersion = try requiredArgument(at: 0, named: "Swift version. E.g. 6.4.0", in: arguments)
    swiftVersion = normalizeSwiftVersion(swiftVersion)
    let distributionName = try requiredArgument(at: 1, named: "distribution name. E.g. ubuntu", in: arguments)
    let distributionVersion = try requiredArgument(at: 2, named: "distribution version. E.g. noble", in: arguments)
    let option = optionalArgument(at: 3, named: "--install or --test", in: arguments)

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

        switch option {
        case "--install":
            // TODO: Install support
            break
        case "--test":
            let bundlesDirectory = generatorDirectory.appendingPathComponent("Bundles", isDirectory: true)
            let testProjectDirectory = rootDirectory.appendingPathComponent("test-project", isDirectory: true)

            let actualSwiftVersion = try hostSwiftVersion()
            guard actualSwiftVersion == swiftVersion else {
                throw ScriptError(
                    message:
                        "Host Swift version is \(actualSwiftVersion), but Swift \(swiftVersion) was requested for testing."
                )
            }

            guard fileManager.fileExists(atPath: bundlesDirectory.path) else {
                throw ScriptError(
                    message:
                        "swift-sdk-generator Bundles directory not found. Please run generate-swift-sdks.swift first.")
            }

            guard fileManager.fileExists(atPath: testProjectDirectory.path) else {
                throw ScriptError(
                    message:
                        "test-project directory not found. This should be available at the root of the source tree for testing the Swift SDKs."
                )
            }

            try testSDK(
                targetArchitecture: targetArchitecture,
                swiftVersion: swiftVersion,
                distributionName: distributionName,
                distributionVersion: distributionVersion,
                bundlesDirectory: bundlesDirectory,
                workingDirectory: testProjectDirectory,
                fileManager: fileManager
            )
        default:  // ignore other options
            break
        }
    }
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
