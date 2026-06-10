//
//  RepoStudioApp.swift
//  RepoStudio
//
//  Created by Kryštof Sláma on 28.05.2026.
//

import AppKit
import SwiftUI

@main
struct RepoStudioApp: App {
    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    var body: some Scene {
        WindowGroup("RepoStudio") {
            WorkspaceView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    RepoStudioSettingsPresenter.showSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            DashboardCommands()
        }

        Settings {
            RepoStudioSettingsView()
        }
    }
}

enum AppPreferenceKeys {
    static let appearanceMode = "repoDraft.appearanceMode"
    static let defaultRemoteName = "repoDraft.defaultRemoteName"
    static let recentGitHubUsernames = "repoDraft.recentGitHubUsernames"
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum RepoStudioSettingsPresenter {
    static func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

struct RepoStudioSettingsView: View {
    @AppStorage(AppPreferenceKeys.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue

    private var appearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var body: some View {
        TabView {
            GitHubAccountsSettingsPane()
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }

            AppearanceSettingsPane()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            GitSettingsPane()
                .tabItem {
                    Label("Git", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }
        }
        .padding(20)
        .frame(width: 560, height: 390)
        .preferredColorScheme(appearanceMode.colorScheme)
    }
}

struct GitHubAccountsSettingsPane: View {
    @State private var savedUsernames: [String] = []
    @State private var username = ""
    @State private var token = ""
    @State private var makeDefault = true
    @State private var isSaving = false
    @State private var settingsError: String?

    private let credentialService = GitCLIRepositoryService()

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("GitHub Accounts") {
                if savedUsernames.isEmpty {
                    Text("No accounts saved.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedUsernames, id: \.self) { account in
                        HStack {
                            Label(account, systemImage: "person.crop.circle")
                            Spacer()
                            Button {
                                setDefaultAccount(account)
                            } label: {
                                Label("Make Default", systemImage: "checkmark.circle")
                            }
                            .labelStyle(.iconOnly)
                            .help("Make Default")
                            .disabled(isSaving)

                            Button(role: .destructive) {
                                removeAccount(account)
                            } label: {
                                Label("Remove Account", systemImage: "trash")
                            }
                            .labelStyle(.iconOnly)
                            .help("Remove Account")
                            .disabled(isSaving)
                        }
                    }
                }
            }

            Section("Add Account") {
                TextField("GitHub username", text: $username)
                    .textFieldStyle(.roundedBorder)

                SecureField("Personal access token", text: $token)
                    .textFieldStyle(.roundedBorder)

                Toggle("Use as default HTTPS account", isOn: $makeDefault)

                HStack {
                    Button {
                        openTokenSettings()
                    } label: {
                        Label("Create Token", systemImage: "key")
                    }

                    Spacer()

                    Button {
                        saveAccount()
                    } label: {
                        Label(isSaving ? "Saving..." : "Save Account", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedUsername.isEmpty || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSavedUsernames()
        }
        .alert(
            "Settings Error",
            isPresented: Binding(
                get: { settingsError != nil },
                set: { value in
                    if value == false {
                        settingsError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                settingsError = nil
            }
        } message: {
            Text(settingsError ?? "Unknown error")
        }
    }

    private func loadSavedUsernames() {
        savedUsernames = UserDefaults.standard.stringArray(forKey: AppPreferenceKeys.recentGitHubUsernames) ?? []
    }

    private func saveAccount() {
        let accountUsername = trimmedUsername
        let accountToken = trimmedToken
        guard accountUsername.isEmpty == false else {
            return
        }

        isSaving = true
        Task { @MainActor in
            do {
                try await credentialService.saveGlobalGitHubCredential(
                    username: accountUsername,
                    token: accountToken,
                    setAsDefault: makeDefault
                )
                addSavedUsername(accountUsername)
                username = ""
                token = ""
            } catch {
                settingsError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func setDefaultAccount(_ account: String) {
        isSaving = true
        Task { @MainActor in
            do {
                try await credentialService.configureGlobalGitHubCredentialUsername(account)
                addSavedUsername(account)
            } catch {
                settingsError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func removeAccount(_ account: String) {
        isSaving = true
        Task { @MainActor in
            do {
                try await credentialService.rejectGlobalGitHubCredential(username: account)
                savedUsernames.removeAll {
                    $0.localizedCaseInsensitiveCompare(account) == .orderedSame
                }
                persistSavedUsernames()
            } catch {
                settingsError = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func addSavedUsername(_ account: String) {
        savedUsernames.removeAll {
            $0.localizedCaseInsensitiveCompare(account) == .orderedSame
        }
        savedUsernames.insert(account, at: 0)
        savedUsernames = Array(savedUsernames.prefix(8))
        persistSavedUsernames()
    }

    private func persistSavedUsernames() {
        UserDefaults.standard.set(savedUsernames, forKey: AppPreferenceKeys.recentGitHubUsernames)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
    }

    private func openTokenSettings() {
        guard let url = URL(string: "https://github.com/settings/tokens") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

struct AppearanceSettingsPane: View {
    @AppStorage(AppPreferenceKeys.appearanceMode) private var appearanceModeRawValue = AppAppearanceMode.system.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearanceModeRawValue) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

struct GitSettingsPane: View {
    @AppStorage(AppPreferenceKeys.defaultRemoteName) private var defaultRemoteName = "origin"

    var body: some View {
        Form {
            Section("Git") {
                TextField("Default publish remote", text: $defaultRemoteName)
                    .textFieldStyle(.roundedBorder)

                Toggle("Pull with fast-forward only", isOn: .constant(true))
                    .disabled(true)
            }
        }
        .formStyle(.grouped)
    }
}
