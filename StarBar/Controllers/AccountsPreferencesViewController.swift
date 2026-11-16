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

    lazy var lastfmTextField: NSTextField = {
        return NSTextField(labelWithString: "Last.fm: ")
    }()
    let lastfmConnectButton: NSButton = {
        return NSButton(title: "Connect", target: nil, action: nil)
    }()
    /// What connecting does, or how the sign-in and the scrobbling stand
    let lastfmStatusTextField: NSTextField = {
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 300
        return field
    }()
    let lastfmSpotifyCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Scrobble songs played in Spotify", target: nil, action: nil)
        // Last.fm's own Spotify link scrobbles on its servers, so both would count each play twice
        button.toolTip = "Leave this off if Spotify is connected to Last.fm in your Last.fm settings, or every Spotify song is scrobbled twice."
        return button
    }()
    let lastfmLoveCheckboxButton: NSButton = {
        let button = NSButton(checkboxWithTitle: "Love songs on Last.fm when I favourite them", target: nil, action: nil)
        return button
    }()

    lazy var gridView: NSGridView = {
        let empty = NSGridCell.emptyContentView
        return PreferencesViewController.makeGrid([
            [spotifyTextField, spotifyConnectButton],
            [empty, spotifyStatusTextField],
            [NSBox.separatorLine],
            [lastfmTextField, lastfmConnectButton],
            [empty, lastfmStatusTextField],
            [empty, lastfmSpotifyCheckboxButton],
            [empty, lastfmLoveCheckboxButton],
        ], baselineLabels: [spotifyTextField, lastfmTextField])
    }()

    var lastfmSpotifyObservation: NSKeyValueObservation?
    var lastfmLoveObservation: NSKeyValueObservation?

    override func loadView() {
        self.view = NSView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        lastfmSpotifyObservation?.invalidate()
        lastfmLoveObservation?.invalidate()
    }

}

// MARK: - Spotify

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

// MARK: - Last.fm

extension AccountsPreferencesViewController {

    @objc private func lastfmConnectButtonPressed(_ sender: NSButton) {
        let account = LastfmAccount.shared
        if account.state == .connected {
            account.disconnect()
        } else {
            account.connect(presentingFrom: view.window)
        }
    }

    @objc private func lastfmSpotifyCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.lastfmScrobbleSpotify = sender.state == .on
    }

    @objc private func lastfmLoveCheckboxButtonChanged(_ sender: NSButton) {
        UserDefaults.standard.lastfmLoveSync = sender.state == .on
    }

    @objc private func lastfmDidChange(_ notification: Notification) {
        refreshLastfm()
    }

    /// The button, the text under it and the two settings follow the sign-in, the pause and
    /// what is waiting to be sent
    func refreshLastfm() {
        let account = LastfmAccount.shared
        let defaults = UserDefaults.standard
        let isConnected = account.state == .connected
        lastfmConnectButton.title = isConnected ? "Disconnect" : "Connect"
        lastfmConnectButton.isEnabled = isConnected || (account.state != .connecting && account.canConnect)
        // The settings say what happens to a signed-in user's plays, so they wait for one
        lastfmSpotifyCheckboxButton.isEnabled = isConnected
        lastfmLoveCheckboxButton.isEnabled = isConnected
        lastfmStatusTextField.stringValue = AccountsPreferencesViewController.lastfmStatus(
            state: account.state,
            username: account.username,
            canConnect: account.canConnect,
            problem: account.lastProblem,
            isPaused: defaults.lastfmPaused,
            waiting: LastfmScrobbler.shared.waitingCount,
            isDryRun: defaults.lastfmDryRun
        )
    }

    /// What the text under Last.fm's Connect button says. A dry run says so whatever else
    /// is true, since nothing is sent then; a problem comes first, as Spotify's does, except
    /// while connecting, when it belongs to the attempt before.
    static func lastfmStatus(state: LastfmAccount.State, username: String?, canConnect: Bool, problem: String?, isPaused: Bool, waiting: Int, isDryRun: Bool) -> String {
        if isDryRun {
            return "Dry run: StarBar logs what it would send to Last.fm and sends nothing."
        }
        let status: String
        switch state {
        case .connected:
            let name = username ?? "your Last.fm user"
            var text = isPaused ? "Connected as \(name). Scrobbling is paused." : "Scrobbling as \(name)."
            if waiting == 1 {
                text += " 1 play waiting to be sent."
            } else if waiting > 1 {
                text += " \(waiting) plays waiting to be sent."
            }
            status = text + " To remove StarBar's access, go to Applications in your Last.fm settings."
        case .connecting:
            return "Waiting for you to allow access on last.fm…"
        case .disconnected:
            status = canConnect
                ? "Scrobble what you play in Music to your Last.fm profile."
                : "This copy of StarBar was built without a Last.fm key, so it can't connect."
        }
        guard let problem = problem else { return status }
        return problem + " " + status
    }

}

// MARK: - Set-up

extension AccountsPreferencesViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        PreferencesViewController.install(gridView, in: view)

        spotifyConnectButton.target = self
        spotifyConnectButton.action = #selector(AccountsPreferencesViewController.spotifyConnectButtonPressed(_:))
        NotificationCenter.default.addObserver(self, selector: #selector(AccountsPreferencesViewController.spotifyAccountDidChange(_:)), name: .spotifyAccountDidChange, object: nil)
        refreshSpotify()

        lastfmConnectButton.target = self
        lastfmConnectButton.action = #selector(AccountsPreferencesViewController.lastfmConnectButtonPressed(_:))
        lastfmSpotifyCheckboxButton.target = self
        lastfmSpotifyCheckboxButton.action = #selector(AccountsPreferencesViewController.lastfmSpotifyCheckboxButtonChanged(_:))
        lastfmSpotifyObservation = UserDefaults.standard.observe(\.lastfmScrobbleSpotify, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.lastfmSpotifyCheckboxButton.state = defaults.lastfmScrobbleSpotify ? .on : .off
        }
        lastfmLoveCheckboxButton.target = self
        lastfmLoveCheckboxButton.action = #selector(AccountsPreferencesViewController.lastfmLoveCheckboxButtonChanged(_:))
        lastfmLoveObservation = UserDefaults.standard.observe(\.lastfmLoveSync, options: [.initial, .new]) { [weak self] defaults, _ in
            self?.lastfmLoveCheckboxButton.state = defaults.lastfmLoveSync ? .on : .off
        }
        NotificationCenter.default.addObserver(self, selector: #selector(AccountsPreferencesViewController.lastfmDidChange(_:)), name: .lastfmAccountDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(AccountsPreferencesViewController.lastfmDidChange(_:)), name: .lastfmScrobblerDidChange, object: nil)
        // Nothing here observes the pause or the dry run, so read them again on coming back
        NotificationCenter.default.addObserver(self, selector: #selector(AccountsPreferencesViewController.lastfmDidChange(_:)), name: NSApplication.didBecomeActiveNotification, object: nil)
        refreshLastfm()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refreshLastfm()
    }

}
