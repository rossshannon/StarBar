//
//  AccountsPreferencesViewController.swift
//  StarBar
//
//  Created by Ross Shannon on 2026-11-16.
//

import Cocoa

/// The Accounts pane of Preferences: the services StarBar signs in to, each with its
/// Connect button and a line under it saying how the sign-in stands
final class AccountsPreferencesViewController: NSViewController {

    lazy var spotifyTextField: NSTextField = {
        return NSTextField(labelWithString: "Spotify: ")
    }()
    let spotifyConnectButton: NSButton = {
        return NSButton(title: "Connect", target: nil, action: nil)
    }()
    /// What connecting does, or how the sign-in stands
    let spotifyStatusTextField: NSTextField = {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 300
        return field
    }()

    lazy var gridView: NSGridView = {
        let empty = NSGridCell.emptyContentView
        return PreferencesViewController.makeGrid([
            [spotifyTextField, spotifyConnectButton],
            [empty, spotifyStatusTextField],
        ], baselineLabels: [spotifyTextField])
    }()

    override func loadView() {
        self.view = NSView()
    }

}

extension AccountsPreferencesViewController {

    @objc private func spotifyConnectButtonPressed(_ sender: NSButton) {
        let account = SpotifyAccount.shared
        if account.state == .connected {
            account.disconnect()
        } else {
            account.connect(presentingFrom: view.window)
        }
    }

    @objc private func spotifyAccountDidChange(_ notification: Notification) {
        refreshSpotify()
    }

    /// The button and the text under it follow the sign-in
    func refreshSpotify() {
        let account = SpotifyAccount.shared
        spotifyConnectButton.title = account.state == .connected ? "Disconnect" : "Connect"
        spotifyConnectButton.isEnabled = account.state != .connecting
        spotifyStatusTextField.stringValue = AccountsPreferencesViewController.spotifyStatus(state: account.state, problem: account.lastProblem)
    }

    /// What the text under the Connect button says
    static func spotifyStatus(state: SpotifyAccount.State, problem: String?) -> String {
        let status: String
        switch state {
        case .connected:
            status = "Connected. Click the green heart in the menu bar to like or unlike the Spotify song playing."
        case .connecting:
            status = "Waiting for Spotify's sign-in…"
        case .disconnected:
            status = "Connect your Spotify account to like songs with the menu bar's green heart."
        }
        guard let problem = problem else { return status }
        return problem + " " + status
    }

}

extension AccountsPreferencesViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        PreferencesViewController.install(gridView, in: view)

        spotifyConnectButton.target = self
        spotifyConnectButton.action = #selector(AccountsPreferencesViewController.spotifyConnectButtonPressed(_:))
        NotificationCenter.default.addObserver(self, selector: #selector(AccountsPreferencesViewController.spotifyAccountDidChange(_:)), name: .spotifyAccountDidChange, object: nil)
        refreshSpotify()
    }

}
