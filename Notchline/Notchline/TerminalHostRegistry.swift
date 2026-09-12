import Foundation

/// How one terminal host names the pane a session is running in, so that a
/// click on the row can select it rather than merely raise the application.
///
/// Every host is raised by process ancestry with no entry here (T0 in
/// `tiered-support.md` §6.2). An entry enables pane focus for a host, and the rule for
/// earning one is the PRD's (§10): the pane is found **by identity** — the
/// controlling terminal device the kernel already reports for the session —
/// through the host's **own public interface**, never by a title, a working
/// directory, window geometry or Accessibility.
///
/// One mechanism exists today. A host whose public interface is a command
/// line rather than a scripting dictionary (WezTerm, kitty, tmux are the
/// candidates, none measured) gets a second case here and a second branch in
/// the runner, once; after that it is an entry like the others.
enum PaneLocator: Sendable {
    /// The host's scripting dictionary exposes each pane's tty. The closure is
    /// handed the device path already quoted as an AppleScript string literal
    /// and returns a script that selects the pane attached to it, bringing the
    /// window forward, and evaluates to `true` when it found one.
    case appleScript(selecting: @Sendable (_ deviceLiteral: String) -> String)
}

/// One terminal host this app can do more than raise.
struct TerminalHostAdapter: Sendable {
    let bundleIdentifier: String
    let paneLocator: PaneLocator
}

enum TerminalHostRegistry {
    /// The hosts that publish a tty, by measurement rather than by choice.
    ///
    /// Terminal.app puts `tty` on `tab` and iTerm2 on `session`. Ghostty
    /// publishes a full dictionary — windows, tabs, terminal surfaces, `select
    /// tab`, `activate window` — and **no tty anywhere in it** (`Ghostty.sdef`,
    /// 1.3.1, checked 2026-08-19); the only identifiers it exposes are the
    /// title and the working directory, and matching on either is the
    /// guessing the PRD forbids. kitty, WezTerm and Alacritty ship no
    /// scripting dictionary at all. All of them take the documented degrade:
    /// the application is raised and the row says so. A test holds that the
    /// unregistered ones stay unregistered until somebody measures a way in.
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
