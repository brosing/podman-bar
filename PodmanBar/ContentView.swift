//
//  ContentView.swift
//  PodmanBar
//
//  Created by Lit on 02/05/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var podmanService = PodmanService()
    @State private var selectedTab: Tab = .machines
    
    enum Tab: String, CaseIterable {
        case machines = "server.rack"
        case containers = "cube.box"
        case images = "photo.stack"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            
            TabView(selection: $selectedTab) {
                MachinesView(podmanService: podmanService)
                    .tag(Tab.machines)
                ContainersView(podmanService: podmanService)
                    .tag(Tab.containers)
                ImagesView(podmanService: podmanService)
                    .tag(Tab.images)
            }
            .frame(height: 320)
        }
        .frame(width: 300, height: 400)
    }
    
    private var headerView: some View {
        HStack {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    Image(systemName: tab.rawValue)
                        .font(.system(size: 16, weight: selectedTab == tab ? .bold : .regular))
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(maxWidth: .infinity)
            }
            
            Button(action: { podmanService.refreshData() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct MachinesView: View {
    @ObservedObject var podmanService: PodmanService
    
    var body: some View {
        VStack {
            if podmanService.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = podmanService.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if podmanService.machines.isEmpty {
                VStack {
                    Image(systemName: "server.rack")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No machines found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(podmanService.machines) { machine in
                            MachineRowView(machine: machine, podmanService: podmanService)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

struct MachineRowView: View {
    let machine: PodmanMachine
    @ObservedObject var podmanService: PodmanService
    @State private var isStarting = false
    @State private var isStopping = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Circle()
                            .fill(machine.running ? .green : .red)
                            .frame(width: 6, height: 6)
                        Text(machine.running ? "Running" : "Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    if machine.running {
                        stopMachine()
                    } else {
                        startMachine()
                    }
                }) {
                    if isStarting || isStopping {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(machine.running ? "Stop" : "Start")
                            .font(.caption)
                    }
                }
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.small)
                .disabled(isStarting || isStopping)
            }
            
            if machine.running {
                if let cpus = machine.cpus {
                    Text("CPUs: \(cpus)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let memory = machine.memory {
                    Text("Memory: \(memory)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    private func startMachine() {
        Task {
            isStarting = true
            let _ = await podmanService.startMachine(machine.name)
            isStarting = false
        }
    }
    
    private func stopMachine() {
        Task {
            isStopping = true
            let _ = await podmanService.stopMachine(machine.name)
            isStopping = false
        }
    }
}

struct ContainersView: View {
    @ObservedObject var podmanService: PodmanService
    
    var body: some View {
        VStack {
            if podmanService.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if podmanService.containers.isEmpty {
                VStack {
                    Image(systemName: "cube.box")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No containers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(podmanService.containers) { container in
                            ContainerRowView(container: container, podmanService: podmanService)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

struct ContainerRowView: View {
    let container: PodmanContainer
    @ObservedObject var podmanService: PodmanService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(container.names?.first ?? "unnamed")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(container.image)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(container.status)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                    
                    if let ports = container.ports, !ports.isEmpty {
                        Text(formatPorts(ports))
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
            }
            
            Text(container.containerID.prefix(12))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
    
    private var statusColor: Color {
        switch container.status.lowercased() {
        case let status where status.contains("running"):
            return .green
        case let status where status.contains("exited"):
            return .red
        default:
            return .secondary
        }
    }
    
    private func formatPorts(_ ports: [PodmanPort]) -> String {
        return ports.map { "\($0.hostPort):\($0.containerPort)" }.joined(separator: ", ")
    }
}

struct ImagesView: View {
    @ObservedObject var podmanService: PodmanService
    
    var body: some View {
        VStack {
            if podmanService.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if podmanService.images.isEmpty {
                VStack {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("No images")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(podmanService.images) { image in
                            ImageRowView(image: image)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

struct ImageRowView: View {
    let image: PodmanImage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(image.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(image.imageID.prefix(12))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

#Preview {
    ContentView()
}
