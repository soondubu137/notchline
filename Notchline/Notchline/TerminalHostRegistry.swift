import Foundation

/// How a terminal host names a session's pane, so a click selects it rather than only raising
/// the app. Hosts without an entry are raised by process ancestry (`tiered-support.md` §6.2).
/// An entry finds the pane by its controlling terminal device through the host's public
/// interface, never a title, working directory, geometry or Accessibility (PRD §10).
enum PaneLocator: Sendable {
    /// The closure takes the tty as a quoted AppleScript literal and returns a script that selects
    /// and fronts that pane, evaluating to `true` when found.
    case appleScript(selecting: @Sendable (_ deviceLiteral: String) -> String)
}

struct TerminalHostAdapter: Sendable {
    let bundleIdentifier: String
    let paneLocator: PaneLocator
}

enum TerminalHostRegistry {
    /// Hosts that publish a tty: Terminal.app on `tab`, iTerm2 on `session`. Ghostty 1.3.1 exposes
    /// none (`Ghostty.sdef`, 2026-08-19); kitty, WezTerm and Alacritty have no dictionary. A test
    /// keeps those unregistered.
    static let builtIn: [TerminalHostAdapter] = [terminalApp, iTerm2]

    static func adapter(
        for bundleIdentifier: String,
        in adapters: [TerminalHostAdapter] = builtIn
    ) -> TerminalHostAdapter? {
        adapters.first { $0.bundleIdentifier == bundleIdentifier }
    }

    static let terminalApp = TerminalHostAdapter(
        bundleIdentifier: "com.apple.Terminal",
        paneLocator: .appleScript { literal in
            """
            tell application id "com.apple.Terminal"
                repeat with theWindow in windows
                    repeat with theTab in tabs of theWindow
                        if tty of theTab is \(literal) then
                            set selected of theTab to true
                            set frontmost of theWindow to true
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        }
    )

    static let iTerm2 = TerminalHostAdapter(
        bundleIdentifier: "com.googlecode.iterm2",
        paneLocator: .appleScript { literal in
            """
            tell application id "com.googlecode.iterm2"
                repeat with theWindow in windows
                    repeat with theTab in tabs of theWindow
                        repeat with theSession in sessions of theTab
                            if tty of theSession is \(literal) then
                                select theWindow
                                select theTab
                                select theSession
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        }
    )
}
