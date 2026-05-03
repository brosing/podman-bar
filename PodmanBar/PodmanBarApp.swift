//
//  PodmanBarApp.swift
//  PodmanBar
//
//  Created by Lit on 02/05/26.
//

import SwiftUI
import AppKit

@main
struct PodmanBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var podmanService = PodmanService()
    var loadingTimer: Timer?
    var isLoading = false
    var menuRefreshTimer: Timer?
    var lastMachineStates: [String: Bool] = [:]  // name -> running
    var lastContainerStates: [String: Bool] = [:]  // id -> isRunning
    var lastImageIDs: [String] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        updateIcon(isLoading: false)
        
        // Setup initial menu first
        setupMenu()
        
        // Load data immediately on launch
        Task {
            await MainActor.run {
                self.podmanService.refreshData()
            }
            // Small delay to let data load then update menu
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await MainActor.run {
                self.updateMenu()
            }
        }
        
        // Initial data load for icon status
        podmanService.refreshData()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        updateMenu()
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        updateMenu()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        // Refresh immediately when menu opens
        podmanService.refreshData()
        updateMenu(force: true)
        
        // Start periodic refresh while menu is open (for live status)
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            self.podmanService.refreshData()
            self.updateMenu()
        }
        // Allow firing during event tracking so updates happen while menu visible
        if let timer = menuRefreshTimer {
            RunLoop.current.add(timer, forMode: .eventTracking)
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        // Stop refresh timer when menu closes to save CPU
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
    }
    
    func updateMenu(force: Bool = false) {
        guard let menu = statusItem?.menu else { return }
        
        // Check if anything actually changed
        let currentMachineStates = Dictionary(uniqueKeysWithValues: podmanService.machines.map { ($0.name, $0.running) })
        let currentContainerStates = Dictionary(uniqueKeysWithValues: podmanService.containers.map { ($0.containerID, containerIsRunning($0)) })
        let currentImageIDs = podmanService.images.map { $0.imageID }.sorted()
        
        if !force && currentMachineStates == lastMachineStates && currentContainerStates == lastContainerStates && currentImageIDs == lastImageIDs {
            return  // Nothing changed, skip UI update
        }
        
        lastMachineStates = currentMachineStates
        lastContainerStates = currentContainerStates
        lastImageIDs = currentImageIDs
        
        menu.removeAllItems()
        
        // Machines Section
        let machinesHeader = NSMenuItem(title: "Machines", action: nil, keyEquivalent: "")
        machinesHeader.attributedTitle = NSAttributedString(
            string: "Machines",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
        )
        machinesHeader.isEnabled = false
        menu.addItem(machinesHeader)
        
        if podmanService.machines.isEmpty {
            let noMachines = NSMenuItem(title: "No machines found", action: nil, keyEquivalent: "")
            noMachines.isEnabled = false
            menu.addItem(noMachines)
        } else {
            for machine in podmanService.machines {
                let machineItem = createMachineMenuItem(machine)
                menu.addItem(machineItem)
            }
        }
        
        // Check if any machine is running
        let isMachineRunning = podmanService.machines.contains { $0.running }
        
        if isMachineRunning {
            menu.addItem(NSMenuItem.separator())
            
            // Containers Section
            let containersHeader = NSMenuItem(title: "Containers", action: nil, keyEquivalent: "")
            containersHeader.attributedTitle = NSAttributedString(
                string: "Containers",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
            )
            containersHeader.isEnabled = false
            menu.addItem(containersHeader)
            
            if podmanService.containers.isEmpty {
                let noContainers = NSMenuItem(title: "No containers", action: nil, keyEquivalent: "")
                noContainers.isEnabled = false
                menu.addItem(noContainers)
            } else {
                for container in podmanService.containers {
                    let containerItem = createContainerMenuItem(container)
                    menu.addItem(containerItem)
                }
            }
            
            menu.addItem(NSMenuItem.separator())
            
            // Images Section
            let imagesHeader = NSMenuItem(title: "Images", action: nil, keyEquivalent: "")
            imagesHeader.attributedTitle = NSAttributedString(
                string: "Images",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]
            )
            imagesHeader.isEnabled = false
            menu.addItem(imagesHeader)
            
            if podmanService.images.isEmpty {
                let noImages = NSMenuItem(title: "No images", action: nil, keyEquivalent: "")
                noImages.isEnabled = false
                menu.addItem(noImages)
            } else {
                for image in podmanService.images {
                    let imageItem = createImageMenuItem(image)
                    menu.addItem(imageItem)
                }
            }
        } else {
            // Show message to start machine
            menu.addItem(NSMenuItem.separator())
            let startMachineItem1 = NSMenuItem(title: "Start a machine to view", action: nil, keyEquivalent: "")
            startMachineItem1.isEnabled = false
            menu.addItem(startMachineItem1)
            let startMachineItem2 = NSMenuItem(title: "containers & images", action: nil, keyEquivalent: "")
            startMachineItem2.isEnabled = false
            menu.addItem(startMachineItem2)
        }
        
        // Refresh and Quit
        menu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshData), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    func createMachineMenuItem(_ machine: PodmanMachine) -> NSMenuItem {
        let status = machine.running ? "●" : "○"
        let title = "\(status) \(machine.name)"
        let item = NSMenuItem(title: title, action: #selector(machineItemClicked(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = machine
        
        // Add submenu for machine actions
        let submenu = NSMenu()
        
        // Status
        let statusItem = NSMenuItem(title: "Status: \(machine.running ? "Running" : "Stopped")", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        submenu.addItem(statusItem)
        
        // VM Type
        if let vmType = machine.vmType {
            let vmTypeItem = NSMenuItem(title: "VM Type: \(vmType)", action: nil, keyEquivalent: "")
            vmTypeItem.isEnabled = false
            submenu.addItem(vmTypeItem)
        }
        
        // Created
        if let created = machine.created {
            let createdItem = NSMenuItem(title: "Created: \(formatDate(created))", action: nil, keyEquivalent: "")
            createdItem.isEnabled = false
            submenu.addItem(createdItem)
        }
        
        // Last Up
        if let lastUp = machine.lastUp, !lastUp.isEmpty, lastUp != "0001-01-01T00:00:00Z" {
            let lastUpItem = NSMenuItem(title: "Last Up: \(formatDate(lastUp))", action: nil, keyEquivalent: "")
            lastUpItem.isEnabled = false
            submenu.addItem(lastUpItem)
        }
        
        submenu.addItem(NSMenuItem.separator())
        
        // CPUs
        if let cpus = machine.cpus {
            let cpusItem = NSMenuItem(title: "CPUs: \(cpus)", action: nil, keyEquivalent: "")
            cpusItem.isEnabled = false
            submenu.addItem(cpusItem)
        }
        
        // Memory
        if let memory = machine.memory {
            let memoryItem = NSMenuItem(title: "Memory: \(formatBytes(memory))", action: nil, keyEquivalent: "")
            memoryItem.isEnabled = false
            submenu.addItem(memoryItem)
        }
        
        // Disk Size
        if let diskSize = machine.diskSize {
            let diskItem = NSMenuItem(title: "Disk Size: \(formatBytes(diskSize))", action: nil, keyEquivalent: "")
            diskItem.isEnabled = false
            submenu.addItem(diskItem)
        }
        
        submenu.addItem(NSMenuItem.separator())
        
        let actionTitle = machine.running ? "Stop Machine" : "Start Machine"
        let actionItem = NSMenuItem(title: actionTitle, action: #selector(toggleMachine(_:)), keyEquivalent: "")
        actionItem.target = self
        actionItem.representedObject = machine
        submenu.addItem(actionItem)
        
        item.submenu = submenu
        return item
    }
    
    func createContainerMenuItem(_ container: PodmanContainer) -> NSMenuItem {
        let name = container.names?.first ?? "unnamed"
        let isRunning = containerIsRunning(container)
        let status = isRunning ? "●" : "○"
        let title = "\(status) \(name)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        
        // Add submenu with details
        let submenu = NSMenu()
        
        let imageItem = NSMenuItem(title: "Image: \(container.image)", action: nil, keyEquivalent: "")
        imageItem.isEnabled = false
        submenu.addItem(imageItem)
        
        let statusDetailItem = NSMenuItem(title: "Status: \(container.status)", action: nil, keyEquivalent: "")
        statusDetailItem.isEnabled = false
        submenu.addItem(statusDetailItem)
        
        if let ports = container.ports, !ports.isEmpty {
            let portStrings = ports.map { "\($0.hostPort):\($0.containerPort)" }
            let portsItem = NSMenuItem(title: "Ports: \(portStrings.joined(separator: ", "))", action: nil, keyEquivalent: "")
            portsItem.isEnabled = false
            submenu.addItem(portsItem)
        }
        
        let idItem = NSMenuItem(title: "ID: \(container.containerID.prefix(12))", action: nil, keyEquivalent: "")
        idItem.isEnabled = false
        submenu.addItem(idItem)
        
        submenu.addItem(NSMenuItem.separator())
        
        // Start/Stop action
        let actionTitle = isRunning ? "Stop Container" : "Start Container"
        let actionItem = NSMenuItem(title: actionTitle, action: #selector(toggleContainer(_:)), keyEquivalent: "")
        actionItem.target = self
        actionItem.representedObject = container
        submenu.addItem(actionItem)
        
        let renameItem = NSMenuItem(title: "Rename...", action: #selector(renameContainer(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = container
        submenu.addItem(renameItem)
        
        item.submenu = submenu
        return item
    }
    
    func containerIsRunning(_ container: PodmanContainer) -> Bool {
        let statusLower = container.status.lowercased()
        return statusLower.contains("running") || statusLower.contains("up")
    }
    
    func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
    
    func formatBytes(_ bytesString: String) -> String {
        guard let bytes = Int64(bytesString) else { return bytesString }
        
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        let mb = Double(bytes) / (1024 * 1024)
        
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        } else if mb >= 1 {
            return String(format: "%.0f MB", mb)
        } else {
            return "\(bytes) bytes"
        }
    }
    
    func createImageMenuItem(_ image: PodmanImage) -> NSMenuItem {
        let title = "\(image.displayName) - \(image.formattedSize)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        
        let submenu = NSMenu()
        let idItem = NSMenuItem(title: "ID: \(image.imageID.prefix(12))", action: nil, keyEquivalent: "")
        idItem.isEnabled = false
        submenu.addItem(idItem)
        
        item.submenu = submenu
        return item
    }
    
    @objc func machineItemClicked(_ sender: NSMenuItem) {
        // Machine item clicked - submenu will handle actions
    }
    
    @objc func toggleMachine(_ sender: NSMenuItem) {
        guard let machine = sender.representedObject as? PodmanMachine else { return }
        let wasRunning = machine.running
        
        Task {
            if wasRunning {
                _ = await podmanService.stopMachine(machine.name)
            } else {
                _ = await podmanService.startMachine(machine.name)
            }
            
            // Poll until machine state changes, then refresh containers/images
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                await self.podmanService.refreshData()
                await MainActor.run {
                    self.updateMenu(force: true)
                }
                // Check if the machine state has flipped
                let machineNow = self.podmanService.machines.first { $0.name == machine.name }
                if let m = machineNow, m.running != wasRunning {
                    // Machine state changed — do one more refresh to get containers/images
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    await self.podmanService.refreshData()
                    await MainActor.run {
                        self.updateMenu(force: true)
                    }
                    return
                }
            }
        }
    }
    
    func setLoadingState(_ loading: Bool) {
        isLoading = loading
        
        if loading {
            // Start cycling through rotation symbols
            loadingTimer?.invalidate()
            var rotationIndex = 0
            let rotationSymbols = ["arrow.clockwise", "arrow.2.circlepath"]
            loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                guard let button = self.statusItem?.button else { return }
                button.image = NSImage(systemSymbolName: rotationSymbols[rotationIndex % 2], accessibilityDescription: "Loading")
                button.image?.isTemplate = true
                rotationIndex += 1
            }
        } else {
            loadingTimer?.invalidate()
            loadingTimer = nil
            updateIcon(isLoading: false)
        }
    }
    
    func updateIcon(isLoading: Bool) {
        guard let button = statusItem?.button else { return }
        
        if isLoading {
            button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Loading")
        } else {
            if let icon = NSImage(named: "MenuBarIcon") {
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "cube.box", accessibilityDescription: "Podman")
            }
        }
        button.image?.isTemplate = true
    }
    
    @objc func renameMachine(_ sender: NSMenuItem) {
        guard let machine = sender.representedObject as? PodmanMachine else { return }
        
        // Machine must be stopped to rename
        if machine.running {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Cannot Rename"
            errorAlert.informativeText = "Please stop the machine before renaming."
            errorAlert.alertStyle = .warning
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Rename Machine"
        alert.informativeText = "Enter new name for \(machine.name):"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = machine.name
        alert.accessoryView = textField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != machine.name {
                Task {
                    self.setLoadingState(true)
                    let result = await self.podmanService.renameMachine(machine.name, to: newName)
                    await MainActor.run {
                        switch result {
                        case .success:
                            self.podmanService.refreshData()
                            self.updateMenu()
                        case .failure(let error):
                            self.showError("Failed to rename machine: \(error.localizedDescription)")
                        }
                        self.setLoadingState(false)
                    }
                }
            }
        }
    }
    
    @objc func toggleContainer(_ sender: NSMenuItem) {
        guard let container = sender.representedObject as? PodmanContainer else { return }
        
        Task {
            let isRunning = self.containerIsRunning(container)
            let result: Result<Void, Error>
            
            if isRunning {
                result = await podmanService.stopContainer(container.containerID)
            } else {
                result = await podmanService.startContainer(container.containerID)
            }
            
            switch result {
            case .success:
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                await self.podmanService.refreshData()
                await MainActor.run {
                    self.updateMenu(force: true)
                }
            case .failure(let error):
                await MainActor.run {
                    self.showError("Failed to \(isRunning ? "stop" : "start") container: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc func renameContainer(_ sender: NSMenuItem) {
        guard let container = sender.representedObject as? PodmanContainer,
              let currentName = container.names?.first else { return }
        
        let alert = NSAlert()
        alert.messageText = "Rename Container"
        alert.informativeText = "Enter new name for \(currentName):"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = currentName
        alert.accessoryView = textField
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty && newName != currentName {
                Task {
                    self.setLoadingState(true)
                    let result = await self.podmanService.renameContainer(currentName, to: newName)
                    await MainActor.run {
                        switch result {
                        case .success:
                            self.podmanService.refreshData()
                            self.updateMenu()
                        case .failure(let error):
                            self.showError("Failed to rename container: \(error.localizedDescription)")
                        }
                        self.setLoadingState(false)
                    }
                }
            }
        }
    }
    
    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func refreshData() {
        podmanService.refreshData()
        updateMenu()
        // Menu will close naturally after action, no need to force it
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
