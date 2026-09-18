#!/usr/bin/env swift
import Foundation

let fileManager = FileManager.default
let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let bundlesDirectory =
    workingDirectory
    .appendingPathComponent("swift-sdk-generator", isDirectory: true)
    .appendingPathComponent("Bundles", isDirectory: true)

// No files available, exit
guard fileManager.fileExists(atPath: bundlesDirectory.path) else {
    print("No Bundles directory found. Nothing to cleanup...")
    exit(1)
}

// List all files in the Bundles directory
print("The following Swift SDKs will be cleaned up:")
let bundleContents = try fileManager.contentsOfDirectory(
    at: bundlesDirectory,
    includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
    options: [.skipsHiddenFiles]
)
for item in bundleContents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
    print("  \(item.lastPathComponent)")
}

// Ask for confirmation
print("Are you sure you want to delete all Swift SDKs in swift-sdk-generator/Bundles? (y/n): ", terminator: "")
let confirmation = readLine()
guard confirmation == "y" else {
    print("Cleanup aborted.")
    exit(0)
}

for item in bundleContents {
    try fileManager.removeItem(at: item)
}
