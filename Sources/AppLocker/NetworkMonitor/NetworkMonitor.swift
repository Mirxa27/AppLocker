// Sources/AppLocker/NetworkMonitor/NetworkMonitor.swift
#if os(macOS)
import Foundation
import AppKit

@MainActor
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published var connections: [NetworkConnection] = []
    @Published var isPaused: Bool = false
    @Published var showLockedAppsOnly: Bool = true

    private var refreshTask: Task<Void, Never>?
    private var orgCache: [String: String] = [:]

    private init() { startRefreshing() }

    func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                if !self.isPaused {
                    let raw = await self.fetchLsofOutput()
                    let parsed = self.parseConnections(raw)
                    let filtered = self.applyFilter(parsed)
                    self.connections = filtered
                    await self.annotateOrgs()
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }


    func stopRefreshing() {
        refreshTask?.cancel(); refreshTask = nil
    }

    // MARK: - lsof

    private func fetchLsofOutput() async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-i", "-n", "-P"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    // MARK: - Parsing

    func parseConnections(_ output: String) -> [NetworkConnection] {
        var result: [NetworkConnection] = []
        let lines = output.components(separatedBy: "\n").dropFirst()

        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 9 else { continue }
            let typeField = parts[4]
            guard typeField == "IPv4" || typeField == "IPv6" else { continue }

            let cmd = parts[0]
            let pid = Int32(parts[1]) ?? 0

            guard let protoIdx = parts.firstIndex(where: { $0 == "TCP" || $0 == "UDP" }),
                  protoIdx + 1 < parts.count else { continue }
            let proto = parts[protoIdx]
            let nameField = parts[protoIdx + 1]
            guard nameField.contains("->") else { continue }

            let arrowParts = nameField.components(separatedBy: "->")
            let local = arrowParts[0]
            let remoteRaw = arrowParts[1]

            var state = ""
            if protoIdx + 2 < parts.count {
                let raw = parts[protoIdx + 2]
                if raw.hasPrefix("(") && raw.hasSuffix(")") {
                    state = String(raw.dropFirst().dropLast())
                }
            }

            let remoteIP: String
            let remotePort: String
            if remoteRaw.hasPrefix("[") {
                let closeBracket = remoteRaw.firstIndex(of: "]") ?? remoteRaw.endIndex
                remoteIP = String(remoteRaw[remoteRaw.index(after: remoteRaw.startIndex)..<closeBracket])
                let afterBracket = remoteRaw[remoteRaw.index(after: closeBracket)...]
                remotePort = afterBracket.hasPrefix(":") ? String(afterBracket.dropFirst()) : ""
            } else {
                let components = remoteRaw.components(separatedBy: ":")
                remoteIP = components.dropLast().joined(separator: ":")
                remotePort = components.last ?? ""
            }

            result.append(NetworkConnection(
                processName: cmd, pid: pid,
                remoteIP: remoteIP, remotePort: remotePort,
                remoteOrg: orgCache[remoteIP] ?? (isPrivateIP(remoteIP) ? "Local" : ""),
                localAddress: local, proto: proto, state: state
            ))
        }
        return result
    }

    private func applyFilter(_ all: [NetworkConnection]) -> [NetworkConnection] {
        guard showLockedAppsOnly else { return all }
        let lockedNames = Set(AppMonitor.shared.lockedApps.map { $0.displayName.lowercased() })
        return all.filter { lockedNames.contains($0.processName.lowercased()) }
    }

    // MARK: - Org Annotation

    private func annotateOrgs() async {
        let unknownIPs = connections
            .filter { !$0.remoteIP.isEmpty && orgCache[$0.remoteIP] == nil && !isPrivateIP($0.remoteIP) }
            .map { $0.remoteIP }
        let unique = Array(Set(unknownIPs)).prefix(5)

        for ip in unique {
            let org = await whoisOrg(for: ip)
            orgCache[ip] = org ?? "Unknown"
            for i in connections.indices where connections[i].remoteIP == ip {
                connections[i].remoteOrg = orgCache[ip] ?? ""
            }
        }
    }

    private func whoisOrg(for ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/whois")
            process.arguments = [ip]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: extractOrgFromWhois(output))
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func extractOrgFromWhois(_ output: String) -> String? {
        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("orgname:") || lower.hasPrefix("org-name:") || lower.hasPrefix("netname:") {
                let value = line.components(separatedBy: ":").dropFirst()
                    .joined(separator: ":").trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    func isPrivateIP(_ ip: String) -> Bool {
        if ip.isEmpty || ip == "*" { return true }
        for prefix in ["10.", "192.168.", "127.", "::1", "fe80:"] where ip.hasPrefix(prefix) { return true }
        if ip.hasPrefix("172.") {
            let parts = ip.components(separatedBy: ".")
            if parts.count > 1, let second = Int(parts[1]), (16...31).contains(second) { return true }
        }
        return false
    }

    var groupedConnections: [(name: String, connections: [NetworkConnection])] {
        let grouped = Dictionary(grouping: connections, by: { $0.processName })
        return grouped.map { (name: $0.key, connections: $0.value) }
            .sorted { $0.connections.count > $1.connections.count }
    }
}
#endif
