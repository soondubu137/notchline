import AppKit
import Carbon.HIToolbox

/// One key and the modifiers held with it, as a person would draw it.
///
/// **The chord that brings the panel down already latched**
/// ([`answer-in-notch.md`](../../docs/answer-in-notch.md) §9.3), and the only
/// thing on this surface that can fail before anybody uses it. It is a value so
/// that the preference, the registration and the settings row are all talking
/// about the same object: what is stored, what was asked for and what is
/// actually held are three states of one chord rather than three strings.
nonisolated struct KeyChord: Sendable, Equatable {
    /// The virtual key code, which is a position on the keyboard rather than a
    /// character — `49` is the space bar on every layout.
    let keyCode: UInt32
    /// The device-independent modifier flags, as `NSEvent` reports them.
    let modifiers: NSEvent.ModifierFlags

    /// `⌥Space`, answered by the board's owner on 2026-09-05 (§15 q03).
    static let `default` = KeyChord(
        keyCode: UInt32(kVK_Space),
        modifiers: .option
    )

    nonisolated init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    /// The chord a key event is, or `nil` where it is not one.
    ///
    /// **A chord needs a modifier**, and that is a rule about what a global
    /// hotkey may be rather than about this app: a bare key registered
    /// system-wide takes that key away from every application on the machine,
    /// including the one the person is typing into.
    nonisolated init?(recording event: NSEvent) {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .function, .numericPad])
        guard !modifiers.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    /// How it is drawn: the modifiers in the order macOS draws them, then the
    /// key.
    nonisolated var drawn: String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols + Self.name(of: keyCode)
    }

    /// What Carbon calls these modifiers.
    nonisolated var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if modifiers.contains(.control) { carbon |= UInt32(controlKey) }
        if modifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if modifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if modifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    // MARK: - Persistence

    /// `keyCode:modifiers`, which is what reaches the preference file.
    ///
    /// Two integers rather than the drawn form: what is stored is a position on
    /// the keyboard, and the character at that position belongs to whichever
    /// layout is current when the row is drawn.
    nonisolated var stored: String { "\(keyCode):\(modifiers.rawValue)" }

    nonisolated init?(stored: String) {
        let parts = stored.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]),
              let raw = UInt(parts[1]) else { return nil }
        self.init(
            keyCode: keyCode,
            modifiers: NSEvent.ModifierFlags(rawValue: raw)
        )
    }

    // MARK: - Naming a key

    /// The keys whose name is not the character they type.
    ///
    /// Everything else is asked of the current keyboard layout, so a chord
    /// recorded on one layout is drawn in the letters of whichever layout is in
    /// front when somebody looks at it.
    private static let specialNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "⏎",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Escape: "⎋",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    nonisolated static func name(of keyCode: UInt32) -> String {
        if let special = specialNames[Int(keyCode)] { return special }
        return character(of: keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// What this key types with nothing held down, on the layout in front now.
    private nonisolated static func character(of keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?
            .takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(
                  source,
                  kTISPropertyUnicodeKeyLayoutData
              )
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        return (data as Data).withUnsafeBytes { bytes -> String? in
            guard let layout = bytes.baseAddress?
                .assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}

/// What the app is actually holding, which is not always what it asked for.
///
/// §9.3: the chord is registered through the ordinary system path **so that a
/// clash fails loudly at registration rather than quietly at use**, and the
/// settings row shows the chord it actually holds. That is the whole reason
/// this is a value the store publishes rather than a `Bool` inside the
/// registration: a hotkey another application already owns is a fact the person
/// has to be told, and the only moment it is knowable is the moment the app
/// asks for it.
nonisolated enum PanelChordHold: Sendable, Equatable {
    /// Nothing has been asked for yet — the state a test host and a store with
    /// no panel stay in.
    case unasked
    /// Held: this chord reaches this app from anywhere.
    case holding(KeyChord)
    /// Asked for and refused, with what the system said.
    case refused(KeyChord, OSStatus)

    /// The chord this is about, whichever way it went.
    nonisolated var chord: KeyChord? {
        switch self {
        case .unasked: nil
        case let .holding(chord): chord
        case let .refused(chord, _): chord
        }
    }

    nonisolated var isHeld: Bool {
        if case .holding = self { return true }
        return false
    }
}

/// Registers one global hotkey, and says what happened.
///
/// **The ordinary system path** (§9.3), which is `RegisterEventHotKey`: it is
/// what a global shortcut on macOS is, it needs no accessibility permission,
/// and — the reason it was chosen over watching every key event — it
/// **answers**. A monitor that quietly never fires is exactly the failure §9.3
/// exists to rule out; this one returns a status the settings row can print.
///
/// Held by ``OverlayPanelController``, because the chord's whole effect is on
/// the panel and the controller is what owns it.
@MainActor
final class PanelChordHolder {
    /// What the chord does when it lands. Set by the controller.
    var onChord: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var hold: PanelChordHold = .unasked

    /// A signature of this app's own, so the id belongs to nobody else.
    private static let signature: OSType = 0x6E6F7463 // 'notc'

    /// Asks for one chord, releasing whatever was held before.
    ///
    /// Returns what is now held, which the caller publishes: the drawn row says
    /// *the chord the app actually holds rather than the one it asked for*.
    @discardableResult
    func hold(_ chord: KeyChord) -> PanelChordHold {
        release()
        installHandlerIfNeeded()

        var reference: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            chord.keyCode,
            chord.carbonModifiers,
            id,
            GetEventDispatcherTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            hold = .refused(chord, status)
            return hold
        }
        hotKey = reference
        hold = .holding(chord)
        return hold
    }

    /// Gives the chord back to the system, leaving the handler in place.
    func release() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        hold = .unasked
    }

    /// Called from the Carbon handler below, on the main thread it dispatches
    /// on.
    fileprivate func fire() {
        onChord?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            panelChordHandler,
            1,
            &specification,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

/// The C callback Carbon dispatches a pressed hotkey to.
///
/// It arrives on the main thread — the event dispatcher target is the main run
/// loop's — so the hop the isolation checker wants is one that has already
/// happened, which is what ``MainActor/assumeIsolated(_:)`` is for.
private nonisolated func panelChordHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let holder = Unmanaged<PanelChordHolder>
        .fromOpaque(userData)
        .takeUnretainedValue()
    MainActor.assumeIsolated { holder.fire() }
    return noErr
}
