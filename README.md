# Swift Embedded Linux SDK Generator

This repository contains convenience scripts for building the upstream Swift SDK generator and then producing Swift SDK bundles for Linux distributions used by Swift Embedded Linux projects.

Important:

- These scripts require Swift 6.0 or later.
- They currently support generating and testing Swift 6.0 or later Swift SDKs only.
- The supported workflow is to build the generator in `swift-sdk-generator`, then use the helper scripts in this repo to generate bundle artifacts under `swift-sdk-generator/Bundles`.
- These scripts only support generating Swift SDKs for **Debian** and **Ubuntu** distributions since armv7 support is required.
   - Raspberry Pi OS is not supported since the SDK generator does not support it yet.
- Docker is not required for generating these Swift SDKs as only the package-based builds are used with the SDK generator.

## Getting started

Follow these steps in order.

1. Install Swift 6.0 or later

   Make sure your local toolchain is Swift 6.0+ before running any of the scripts.

   ```bash
   swift --version
   ```

   You should see a Swift 6.0+ release, such as 6.0, 6.1, 6.3, or 6.4.

   NOTE: This is best used with [swiftly](https://github.com/swiftlang/swiftly), which can be installed from [Swift.org](https://www.swift.org/install/linux/). With swiftly it is then easy to switch Swift versions before generating and testing Swift SDKs that require those versions of Swift.

2. Ensure that needed dependencies are installed

   Debian/Ubuntu:

   ```bash
   sudo apt install zstd xz-utils libsqlite3-dev
   ```

   macOS:

   ```bash
   cd swift-sdk-generator
   brew bundle install
   ```

3. Clone this repository and enter it

   ```bash
   git clone https://github.com/swift-embedded-linux/generate-linux-sdks.git
   cd generate-linux-sdks
   ```

4. Build the SDK generator

   This script checks out or updates the upstream generator project, then builds it in release mode with a static Swift standard library.

   ```bash
   ./build-sdk-generator.swift
   ```

   This prepares the generator at:

   - `swift-sdk-generator/.build/release/swift-sdk-generator`

5. Generate Swift SDK bundles

   The main script generates Linux Swift SDK bundles for multiple target architectures.

   ```bash
   ./generate-linux-sdks.swift 6.4.0 ubuntu noble --test
   ```

   This example does two things:

   - generates bundles for `x86_64`, `aarch64`, and `armv7`
   - runs the test project against the generated SDKs for the requested Swift version

   The arguments are:

   - `6.4.0` = Swift version to target
   - `ubuntu` = Linux distribution name
   - `noble` = distribution version
   - `--test` = optional; validates the result using the local test project

   If you only want to generate the bundles without testing, omit the final option:

   ```bash
   ./generate-linux-sdks.swift 6.4.0 ubuntu noble
   ```

6. Check the generated bundles

   Generated artifact bundles appear under the generator’s `Bundles` directory:

   ```bash
   ls -1 swift-sdk-generator/Bundles
   ```

   Typical output looks like this:

   ```text
   6.4.0-RELEASE_ubuntu_noble_aarch64.artifactbundle
   6.4.0-RELEASE_ubuntu_noble_armv7.artifactbundle
   6.4.0-RELEASE_ubuntu_noble_x86_64.artifactbundle
   ```

7. (Optional): Clean up generated bundles when needed

   ```bash
   ./clean-linux-sdks.swift
   ```

   This prompts for confirmation before deleting all generated SDK bundle directories in `swift-sdk-generator/Bundles`.

   Or, just delete the entire `swift-sdk-generator` directory if you want to completely cleanup.

---

## Script reference

### build-sdk-generator.swift

This script keeps the underlying `swift-sdk-generator` project up to date and rebuilds it locally.

#### What it does

- clones the generator repo if it is missing
- runs `git pull origin` in `swift-sdk-generator`
- builds the generator in release mode with:

  ```bash
  swift build -c release --static-swift-stdlib
  ```

#### Usage

```bash
./build-sdk-generator.swift
```

#### Notes

- This is the first step in the workflow.
- The script is intentionally designed to make it easy to switch host Swift versions without rebuilding the generator repeatedly- it only needs to be built once before using it against different Swift versions and target distributions.
- It is meant to work with the upstream Swift SDK generator project in the sibling `swift-sdk-generator` directory.

---

### generate-linux-sdks.swift

This is the main orchestration script for generating Linux Swift SDK bundles.

#### Syntax

```bash
./generate-linux-sdks.swift <swift-version> <distribution-name> <distribution-version> [--test|--install]
```

#### Parameters

- `swift-version`: target Swift version, for example `6.0`, `6.3.3`, or `6.4.0`
- `distribution-name`: Linux distribution name, such as `ubuntu` or `debian`
- `distribution-version`: distribution release, such as `noble`, `bookworm`, or `jammy`
- `--test`: optional; runs the local validation project against the generated SDK bundles
- `--install`: accepted by the script but currently stubbed out; installation support is not implemented yet

#### Examples

Generate SDKs for Ubuntu 24.04 using Swift 6.4:

```bash
./generate-linux-sdks.swift 6.4.0 ubuntu noble
```

Generate and validate SDKs for Debian 12 using Swift 6.3.3:

```bash
./generate-linux-sdks.swift 6.3.3 debian bookworm --test
```

#### Behavior

For each target architecture in:

- `x86_64`
- `aarch64`
- `armv7`

it runs the generator command and produces a bundle named like:

```text
6.4.0-RELEASE_ubuntu_noble_x86_64.artifactbundle
```

For `armv7`, the script also downloads the matching armv7 runtime archive before invoking the generator.

#### Testing mode

When `--test` is supplied, the script validates that the host toolchain matches the requested Swift version before building the sample project.

It then runs:

```bash
swift build -c debug --build-tests --swift-sdks-path <bundles-dir> --swift-sdk <sdk-name>
swift build -c release --swift-sdks-path <bundles-dir> --swift-sdk <sdk-name>
```

The test workflow uses the project in `test-project` and checks the generated binaries with `file`.

> The testing path enforces a matching host Swift version and is intended for Swift 6.0+ only.

---

### clean-linux-sdks.swift

This script removes generated Swift SDK bundles from the generator’s `Bundles` directory.

#### Usage

```bash
./clean-linux-sdks.swift
```

#### Behavior

- checks whether `swift-sdk-generator/Bundles` exists
- prints every bundle it is about to delete
- asks for confirmation
- deletes only after the user enters `y`

#### Example

```bash
./clean-linux-sdks.swift
The following Swift SDKs will be cleaned up:
  6.4.0-RELEASE_ubuntu_noble_aarch64.artifactbundle
  6.4.0-RELEASE_ubuntu_noble_armv7.artifactbundle
  6.4.0-RELEASE_ubuntu_noble_x86_64.artifactbundle
Are you sure you want to delete all Swift SDKs in swift-sdk-generator/Bundles? (y/n): y
```

---

## Supported Swift versions for these scripts

This repo is intentionally scoped to Swift 6.0 and later.

Examples of supported target versions include:

- `6.0`
- `6.0.x`
- `6.1.x`
- `6.2.x`
- `6.3.x`
- `6.4.x`

The scripts normalize `6.4` to `6.4.0` internally and expect the host `swift` tool to be a compatible Swift 6 toolchain when validating generated SDKs.

---

## Typical full workflow

```bash
./build-sdk-generator.swift
./generate-linux-sdks.swift 6.4.0 ubuntu noble --test
ls -1 swift-sdk-generator/Bundles
```

This is the standard path for creating and validating Linux Swift SDK bundles with this repo.
