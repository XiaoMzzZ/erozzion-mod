import SwiftUI
import UIKit
import ZIPFoundation
import UniformTypeIdentifiers

struct AppsManagementView: View {
    @EnvironmentObject private var airlift: AirliftBridge
    @State private var preparedDirectories: [String: URL] = [:]
    @State private var preparingBundleIDs: Set<String> = []
    @State private var processingBundleIDs: Set<String> = []
    @State private var alertMessage: String?
    @State private var selectedInfoApp: AirliftAppBundlePath?
    @AppStorage("listStyle") private var listStyle = 1

    private var sortedApps: [AirliftAppBundlePath] {
        airlift.installedAppBundlePaths.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        appList
            .onAppear {
                reloadPreparedApps()
                airlift.scanInstalledAppBundlePathsIfNeeded()
            }
            .onChange(of: airlift.installedAppBundlePaths) { _, _ in
                reloadPreparedApps()
            }
            .alert("App Decrypt", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
            .sheet(item: $selectedInfoApp) { app in
                InfoViewer(bundleInfoItem(for: app))
            }
    }

    /// Root list for installed application bundles.
    private var appList: some View {
        List {
            if airlift.appScanRunning {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading installed applications…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if sortedApps.isEmpty && !airlift.appScanRunning {
                Section {
                    ContentUnavailableView(
                        "No installed apps found",
                        systemImage: "app.dashed",
                        description: Text("Check that LocalDevVPN is enabled and a pairing file is imported, then return to this screen.")
                    )
                }
            } else if !sortedApps.isEmpty {
                Section {
                    ForEach(sortedApps) { app in
                        appRow(app)
                    }
                } header: {
                    HStack {
                        Text("Installed Apps")
                        Spacer()
                        Text("\(sortedApps.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("App Decrypt")
        .navigationBarTitleDisplayMode(.inline)
        .customListStyle(listStyle)
        .adaptiveListMargin()
    }

    @ViewBuilder
    private func appRow(_ app: AirliftAppBundlePath) -> some View {
        HStack(spacing: 12) {
            AppsManagementAppIcon(bundleID: app.bundleID)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(app.displayName)
                    .font(.body)
                    .lineLimit(1)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if preparedDirectories[app.bundleID] != nil {
                    Text("Prepared")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                } else if preparingBundleIDs.contains(app.bundleID) {
                    Text("Preparing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if preparingBundleIDs.contains(app.bundleID) || processingBundleIDs.contains(app.bundleID) {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                selectedInfoApp = app
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary)
            .accessibilityLabel("Get Info for \(app.displayName)")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                prepare(app)
            } label: {
                Label("Prepare", systemImage: "arrow.down.doc")
            }
            .disabled(preparingBundleIDs.contains(app.bundleID) || processingBundleIDs.contains(app.bundleID))

            Button {
                createIPA(for: app)
            } label: {
                Label("Decrypt", systemImage: "doc.zipper")
            }
            .disabled(preparedDirectories[app.bundleID] == nil
                || preparingBundleIDs.contains(app.bundleID)
                || processingBundleIDs.contains(app.bundleID))

        }
    }

    private func bundleInfoItem(for app: AirliftAppBundlePath) -> FileItem {
        let url = URL(fileURLWithPath: app.path, isDirectory: true)
        let epoch = Date(timeIntervalSince1970: 0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd-yyyy h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        let epochText = formatter.string(from: epoch)

        return FileItem(
            name: app.displayName,
            fileURL: url,
            destURL: url,
            type: .folder,
            uttype: .folder,
            size: 0,
            creationDate: epoch,
            modifiedDate: epoch,
            creationDateStr: epochText,
            modifiedDateStr: epochText,
            hidden: false,
            posixPerms: "",
            owner: "root",
            group: "wheel",
            readable: false,
            writable: false,
            executable: false
        )
    }

    private func reloadPreparedApps() {
        preparedDirectories = PreparedAppsStorage.preparedDirectories()
    }

    private func prepare(_ app: AirliftAppBundlePath) {
        guard !preparingBundleIDs.contains(app.bundleID),
              !processingBundleIDs.contains(app.bundleID) else { return }
        preparingBundleIDs.insert(app.bundleID)
        airlift.appendFeatureLog("app-decrypt", "Preparing \(app.displayName) (\(app.bundleID)) through Airlift")
        airlift.readRemotePathForFileOperations(path: app.path, kind: .folder, feature: "apps-management") { success, archiveURL, detail in
            guard success, let archiveURL else {
                preparingBundleIDs.remove(app.bundleID)
                airlift.appendFeatureLog("app-decrypt", "Prepare failed for \(app.displayName): \(detail)")
                alertMessage = detail.isEmpty ? "Airlift could not read this app bundle." : detail
                return
            }

            Task {
                do {
                    let preparedURL = try await Task.detached(priority: .utility) {
                        try PreparedAppsStorage.installSnapshot(archiveURL, for: app)
                    }.value
                    preparedDirectories[app.bundleID] = preparedURL
                    preparingBundleIDs.remove(app.bundleID)
                    airlift.appendFeatureLog("app-decrypt", "Prepared \(app.displayName). The app bundle is saved in Erosion storage.")
                } catch {
                    try? FileManager.default.removeItem(at: archiveURL)
                    preparingBundleIDs.remove(app.bundleID)
                    airlift.appendFeatureLog("app-decrypt", "Prepare failed for \(app.displayName): \(error.localizedDescription)")
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func createIPA(for app: AirliftAppBundlePath) {
        guard let preparedURL = preparedDirectories[app.bundleID] else { return }
        guard !processingBundleIDs.contains(app.bundleID) else { return }
        processingBundleIDs.insert(app.bundleID)
        airlift.appendFeatureLog("app-decrypt", "Building Payload and packaging \(app.displayName).ipa")
        Task {
            do {
                let ipaURL = try await Task.detached(priority: .utility) {
                    try PreparedAppsStorage.makeIPA(from: preparedURL, displayName: app.displayName)
                }.value
                processingBundleIDs.remove(app.bundleID)
                airlift.appendFeatureLog("app-decrypt", "IPA package ready: \(ipaURL.lastPathComponent). This packages the prepared .app and does not decrypt FairPlay-encrypted executables.")
                presentShareSheet(with: ipaURL)
            } catch {
                processingBundleIDs.remove(app.bundleID)
                airlift.appendFeatureLog("app-decrypt", "IPA packaging failed for \(app.displayName): \(error.localizedDescription)")
                alertMessage = error.localizedDescription
            }
        }
    }
}

private struct AppsManagementAppIcon: View {
    @EnvironmentObject private var airlift: AirliftBridge
    let bundleID: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(uiColor: .systemGray4))
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .task(id: bundleID) {
            guard image == nil else { return }
            image = await airlift.fetchAppIcon(bundleID: bundleID)
        }
    }
}

private struct PreparedAppManifest: Codable {
    let bundleID: String
    let displayName: String
    let sourcePath: String
    let appDirectoryName: String
    let preparedAt: Date
}

private enum PreparedAppsStorage {
    private static var rootURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("ErosionAppsManagement", isDirectory: true)
    }

    private static var preparedRootURL: URL {
        rootURL.appendingPathComponent("Prepared", isDirectory: true)
    }

    private static var exportRootURL: URL {
        rootURL.appendingPathComponent("Exports", isDirectory: true)
    }

    static func preparedDirectories() -> [String: URL] {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: preparedRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var results: [String: URL] = [:]
        for directory in children {
            let manifestURL = directory.appendingPathComponent("prepared.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(PreparedAppManifest.self, from: data) else { continue }
            let appURL = directory.appendingPathComponent(manifest.appDirectoryName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: appURL.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            results[manifest.bundleID] = appURL
        }
        return results
    }

    static func installSnapshot(_ archiveURL: URL, for app: AirliftAppBundlePath) throws -> URL {
        let appName = URL(fileURLWithPath: app.path).lastPathComponent
        guard isValidBundlePath(app.path), appName.lowercased().hasSuffix(".app") else {
            throw StorageError.invalidBundlePath
        }

        let fileManager = FileManager.default
        let appStorageDirectory = preparedRootURL.appendingPathComponent(safeComponent(app.bundleID), isDirectory: true)
        if fileManager.fileExists(atPath: appStorageDirectory.path) {
            try fileManager.removeItem(at: appStorageDirectory)
        }
        try fileManager.createDirectory(at: appStorageDirectory, withIntermediateDirectories: true)

        let appURL = appStorageDirectory.appendingPathComponent(appName, isDirectory: true)
        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        do {
            // The Airlift folder ZIP contains the contents of the remote .app
            // directory at its root, so extract directly into the .app folder.
            try fileManager.unzipItem(at: archiveURL, to: appURL)
            let entries = try fileManager.contentsOfDirectory(atPath: appURL.path)
            guard !entries.isEmpty else { throw StorageError.emptyBundle }
            let restoredExecutables = try restoreExecutablePermissions(in: appURL)

            let manifest = PreparedAppManifest(
                bundleID: app.bundleID,
                displayName: app.displayName,
                sourcePath: app.path,
                appDirectoryName: appName,
                preparedAt: Date()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: appStorageDirectory.appendingPathComponent("prepared.json"), options: .atomic)
            try? fileManager.removeItem(at: archiveURL)
            _ = restoredExecutables
            return appURL
        } catch {
            try? fileManager.removeItem(at: appStorageDirectory)
            throw error
        }
    }

    /// AFC folder snapshots do not consistently expose remote st_mode bits.
    /// Restore the executable bit for each bundle's declared CFBundleExecutable
    /// so the prepared app and the resulting IPA do not inherit ZIP's 0600 file
    /// mode for every regular file.
    @discardableResult
    private static func restoreExecutablePermissions(in appURL: URL) throws -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: appURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var executablePaths = Set<String>()
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "Info.plist" {
            guard let data = try? Data(contentsOf: fileURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dictionary = plist as? [String: Any],
                  let executable = dictionary["CFBundleExecutable"] as? String,
                  !executable.isEmpty,
                  !executable.contains("/"),
                  executable != ".", executable != ".." else { continue }

            let executableURL = fileURL.deletingLastPathComponent().appendingPathComponent(executable)
            let path = executableURL.standardizedFileURL.path
            guard path == appURL.standardizedFileURL.path
                    || path.hasPrefix(appURL.standardizedFileURL.path + "/") else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            executablePaths.insert(path)
        }

        // Embedded dynamic libraries are loadable Mach-O images as well. They
        // are not guaranteed to have a separate Info.plist in every package.
        if let enumerator = fileManager.enumerator(at: appURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "dylib" {
                executablePaths.insert(fileURL.standardizedFileURL.path)
            }
        }

        for path in executablePaths {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }
        return executablePaths.count
    }

    static func makeIPA(from appURL: URL, displayName: String) throws -> URL {
        guard appURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: appURL.path) else {
            throw StorageError.preparedBundleMissing
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: exportRootURL, withIntermediateDirectories: true)
        let workingDirectory = rootURL.appendingPathComponent("Working-\(UUID().uuidString)", isDirectory: true)
        let payloadDirectory = workingDirectory.appendingPathComponent("Payload", isDirectory: true)
        try fileManager.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workingDirectory) }

        let payloadAppURL = payloadDirectory.appendingPathComponent(appURL.lastPathComponent, isDirectory: true)
        try fileManager.copyItem(at: appURL, to: payloadAppURL)

        let packageName = safeFileName(displayName)
        let zipURL = workingDirectory.appendingPathComponent("\(packageName).zip")
        try fileManager.zipItem(at: payloadDirectory, to: zipURL, shouldKeepParent: true)

        let ipaURL = exportRootURL.appendingPathComponent("\(packageName)-\(UUID().uuidString.prefix(8)).ipa")
        try fileManager.moveItem(at: zipURL, to: ipaURL)
        return ipaURL
    }

    private static func isValidBundlePath(_ path: String) -> Bool {
        let root = "/var/containers/Bundle/Application/"
        guard path.hasPrefix(root) else { return false }
        let components = path.dropFirst(root.count).split(separator: "/", omittingEmptySubsequences: false)
        return components.count == 2
            && UUID(uuidString: String(components[0])) != nil
            && String(components[1]).lowercased().hasSuffix(".app")
    }

    private static func safeComponent(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }

    private static func safeFileName(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "[/\\\\:\\n\\r]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Application" : cleaned
    }

    private enum StorageError: LocalizedError {
        case invalidBundlePath
        case emptyBundle
        case preparedBundleMissing

        var errorDescription: String? {
            switch self {
            case .invalidBundlePath: return "The app path is not a valid Bundle/Application UUID/<name>.app path."
            case .emptyBundle: return "The Airlift snapshot was empty; the app bundle was not marked as prepared."
            case .preparedBundleMissing: return "The prepared .app bundle could not be found in Erosion storage."
            }
        }
    }
}
