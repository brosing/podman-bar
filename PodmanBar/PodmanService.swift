//
//  PodmanService.swift
//  PodmanBar
//
//  Created by Lit on 02/05/26.
//

import Foundation
import Combine

struct PodmanMachine: Codable, Identifiable {
    let id = UUID()
    let name: String
    let vmType: String?
    let cpus: Int?
    let memory: String?
    let diskSize: String?
    let running: Bool
    let created: String?
    let lastUp: String?
    
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case cpus = "CPUs"
        case memory = "Memory"
        case running = "Running"
        case created = "Created"
        case vmType = "VMType"
        case diskSize = "DiskSize"
        case lastUp = "LastUp"
    }
}

struct PodmanContainer: Codable, Identifiable {
    let id = UUID()
    let containerID: String
    let image: String
    let command: [String]?
    let created: String
    let status: String
    let ports: [PodmanPort]?
    let names: [String]?
    
    enum CodingKeys: String, CodingKey {
        case containerID = "Id"
        case image = "Image"
        case command = "Command"
        case created = "CreatedAt"
        case status = "Status"
        case ports = "Ports"
        case names = "Names"
    }
}

struct PodmanPort: Codable {
    let hostIP: String
    let containerPort: Int
    let hostPort: Int
    let range: Int
    let proto: String
    
    enum CodingKeys: String, CodingKey {
        case hostIP = "host_ip"
        case containerPort = "container_port"
        case hostPort = "host_port"
        case range
        case proto = "protocol"
    }
}

struct PodmanImage: Codable, Identifiable {
    let id = UUID()
    let imageID: String
    let repoTags: [String]?
    let size: Int64
    
    enum CodingKeys: String, CodingKey {
        case imageID = "Id"
        case repoTags = "RepoTags"
        case size = "Size"
    }
    
    var displayName: String {
        guard let tags = repoTags, !tags.isEmpty else { return "<none>" }
        return tags.first ?? "<none>"
    }
    
    var formattedSize: String {
        let gb = Double(size) / (1024 * 1024 * 1024)
        let mb = Double(size) / (1024 * 1024)
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        } else {
            return String(format: "%.1f MB", mb)
        }
    }
}

class PodmanService: ObservableObject {
    @Published var machines: [PodmanMachine] = []
    @Published var containers: [PodmanContainer] = []
    @Published var images: [PodmanImage] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private var podmanPath: String {
        // Try common Podman installation paths
        let possiblePaths = [
            "/opt/homebrew/bin/podman",  // Homebrew on Apple Silicon
            "/usr/local/bin/podman",     // Homebrew on Intel
            "/usr/bin/podman",           // System installation
            "~/.local/bin/podman"        // User installation
        ]
        
        for path in possiblePaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return expandedPath
            }
        }
        
        // Fallback: try to find in PATH
        if let path = findPodmanInPath() {
            return path
        }
        
        return "/opt/homebrew/bin/podman" // Default fallback
    }
    
    private var podmanRemotePath: String {
        // Try common Podman Remote installation paths
        let possiblePaths = [
            "/opt/homebrew/bin/podman-remote",  // Homebrew on Apple Silicon
            "/usr/local/bin/podman-remote",     // Homebrew on Intel
            "/usr/bin/podman-remote",           // System installation
            "~/.local/bin/podman-remote"        // User installation
        ]
        
        for path in possiblePaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return expandedPath
            }
        }
        
        // Fallback: try to find in PATH
        if let path = findPodmanRemoteInPath() {
            return path
        }
        
        return "/opt/homebrew/bin/podman-remote" // Default fallback
    }
    
    private func findPodmanInPath() -> String? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        
        let pathComponents = path.split(separator: ":")
        for component in pathComponents {
            let podmanPath = "\(component)/podman"
            if FileManager.default.fileExists(atPath: podmanPath) {
                return podmanPath
            }
        }
        
        return nil
    }
    
    private func findPodmanRemoteInPath() -> String? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        
        let pathComponents = path.split(separator: ":")
        for component in pathComponents {
            let podmanPath = "\(component)/podman-remote"
            if FileManager.default.fileExists(atPath: podmanPath) {
                return podmanPath
            }
        }
        
        return nil
    }
    
    init() {
        refreshData()
    }
    
    func refreshData() {
        Task {
            await MainActor.run {
                isLoading = true
                error = nil
            }
            
            async let machinesTask = fetchMachines()
            async let containersTask = fetchContainers()
            async let imagesTask = fetchImages()
            
            let (machinesResult, containersResult, imagesResult) = await (machinesTask, containersTask, imagesTask)
            
            await MainActor.run {
                switch machinesResult {
                case .success(let machines):
                    self.machines = machines
                case .failure(let error):
                    self.error = "Failed to fetch machines: \(error.localizedDescription)"
                }
                
                switch containersResult {
                case .success(let containers):
                    self.containers = containers
                case .failure(let error):
                    self.error = "Failed to fetch containers: \(error.localizedDescription)"
                }
                
                switch imagesResult {
                case .success(let images):
                    self.images = images
                case .failure(let error):
                    self.error = "Failed to fetch images: \(error.localizedDescription)"
                }
                
                isLoading = false
            }
        }
    }
    
    private func executeCommand(_ command: String, arguments: [String]) async -> Result<String, Error> {
        // Check if Podman executable exists
        if !FileManager.default.fileExists(atPath: podmanPath) {
            return .failure(NSError(domain: "PodmanError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Podman executable not found at \(podmanPath). Please ensure Podman is installed."
            ]))
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: podmanPath)
        process.arguments = [command] + arguments
        
        // Set up environment with PATH
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return .success(output)
            } else {
                return .failure(NSError(domain: "PodmanError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output]))
            }
        } catch {
            return .failure(error)
        }
    }
    
    private func executeMachineCommand(_ command: String, arguments: [String]) async -> Result<String, Error> {
        // Check if Podman Remote executable exists
        if !FileManager.default.fileExists(atPath: podmanRemotePath) {
            return .failure(NSError(domain: "PodmanError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Podman Remote executable not found at \(podmanRemotePath). Please ensure Podman Remote is installed."
            ]))
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: podmanRemotePath)
        process.arguments = [command] + arguments
        
        // Set up environment with PATH
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                return .success(output)
            } else {
                return .failure(NSError(domain: "PodmanError", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output]))
            }
        } catch {
            return .failure(error)
        }
    }
    
    private func fetchMachines() async -> Result<[PodmanMachine], Error> {
        let result = await executeMachineCommand("machine", arguments: ["list", "--format", "json"])
        
        switch result {
        case .success(let output):
            do {
                let machines = try JSONDecoder().decode([PodmanMachine].self, from: output.data(using: .utf8) ?? Data())
                return .success(machines)
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    private func fetchContainers() async -> Result<[PodmanContainer], Error> {
        let result = await executeCommand("ps", arguments: ["-a", "--format", "json"])
        
        switch result {
        case .success(let output):
            do {
                let containers = try JSONDecoder().decode([PodmanContainer].self, from: output.data(using: .utf8) ?? Data())
                return .success(containers)
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    private func fetchImages() async -> Result<[PodmanImage], Error> {
        let result = await executeCommand("images", arguments: ["--all", "--format", "json"])
        
        switch result {
        case .success(let output):
            do {
                let images = try JSONDecoder().decode([PodmanImage].self, from: output.data(using: .utf8) ?? Data())
                return .success(images)
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func startMachine(_ name: String) async -> Result<Void, Error> {
        let result = await executeMachineCommand("machine", arguments: ["start", name])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func stopMachine(_ name: String) async -> Result<Void, Error> {
        let result = await executeMachineCommand("machine", arguments: ["stop", name])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func renameMachine(_ name: String, to newName: String) async -> Result<Void, Error> {
        let result = await executeMachineCommand("machine", arguments: ["rename", name, newName])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func renameContainer(_ name: String, to newName: String) async -> Result<Void, Error> {
        let result = await executeCommand("rename", arguments: [name, newName])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func startContainer(_ id: String) async -> Result<Void, Error> {
        let result = await executeCommand("start", arguments: [id])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func stopContainer(_ id: String) async -> Result<Void, Error> {
        let result = await executeCommand("stop", arguments: [id])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func removeContainer(_ id: String) async -> Result<Void, Error> {
        let result = await executeCommand("rm", arguments: [id])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
    
    func removeImage(_ id: String) async -> Result<Void, Error> {
        let result = await executeCommand("rmi", arguments: [id])
        
        switch result {
        case .success:
            refreshData()
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }
}
