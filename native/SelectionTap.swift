// native/SelectionTap.swift
//
// Streams JSON whenever the user changes the text selection.
// Handles both normal AX notifications and the fallback timer path.

import Foundation
import ApplicationServices
import Cocoa

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

func focusedElement() -> AXUIElement? {
    // Use frontmost app instead of system-wide (more reliable)
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
        fputs("LiveSel helper: no frontmost app\n", stderr)
        return nil
    }
    
    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
    var val: AnyObject?
    let result = AXUIElementCopyAttributeValue(appElement,
                                              kAXFocusedUIElementAttribute as CFString,
                                              &val)
    if result == .success {
        return val as! AXUIElement
    } else {
        fputs("LiveSel helper: failed to get focused element from \(frontApp.localizedName ?? "unknown") (error: \(result.rawValue))\n", stderr)
        return nil
    }
}

func selectedText(_ elem: AXUIElement) -> String? {
    var v: AnyObject?
    let result = AXUIElementCopyAttributeValue(elem,
                                              kAXSelectedTextAttribute as CFString,
                                              &v)
    if result == .success {
        if let s = v as? String, !s.isEmpty {
            fputs("LiveSel helper: found selected text: '\(s.prefix(50))'\n", stderr)
            return s
        } else {
            fputs("LiveSel helper: selected text attribute exists but is empty\n", stderr)
        }
    } else {
        fputs("LiveSel helper: no selected text attribute (error: \(result.rawValue))\n", stderr)
    }
    return nil
}

func mousePoint() -> (Int, Int) {
    let p = NSEvent.mouseLocation
    let h = NSScreen.screens.first!.frame.height
    return (Int(p.x), Int(h - p.y))
}

func emit(_ text: String) {
    let (x, y) = mousePoint()
    let obj: [String: Any] = [
        "text": text,
        "x": x,
        "y": y,
        "ts": Int(Date().timeIntervalSince1970 * 1000)
    ]
    if let d = try? JSONSerialization.data(withJSONObject: obj),
       let s = String(data: d, encoding: .utf8) {
        print(s); fflush(stdout)
    }
}

// ---------------------------------------------------------------------------
// globals
// ---------------------------------------------------------------------------

var selObserver: AXObserver?
var currentObservedElem: AXUIElement?

// ---------------------------------------------------------------------------
// selection‑observer callback
// ---------------------------------------------------------------------------

let selectionCB: AXObserverCallback = { _, elem, _, _ in
    if let t = selectedText(elem) { emit(t) }
}

// ---------------------------------------------------------------------------
// (re)attach selection observer to a new focused element
// ---------------------------------------------------------------------------

func hookSelection(on elem: AXUIElement) {
    // detach previous
    if let oldObs = selObserver, let oldElem = currentObservedElem {
        AXObserverRemoveNotification(oldObs,
                                     oldElem,
                                     kAXSelectedTextChangedNotification as CFString)
    }

    // attach new
    var newObsPtr: AXObserver?
    if AXObserverCreate(0,
                        selectionCB,
                        &newObsPtr) == .success,
       let newObs = newObsPtr,
       AXObserverAddNotification(newObs,
                                 elem,
                                 kAXSelectedTextChangedNotification as CFString,
                                 nil) == .success {

        CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           AXObserverGetRunLoopSource(newObs),
                           .defaultMode)
        selObserver        = newObs
        currentObservedElem = elem
    }
}

// ---------------------------------------------------------------------------
// focus‑change callback (only if AX lets us register it)
// ---------------------------------------------------------------------------

let focusCB: AXObserverCallback = { _, _, _, _ in
    if let f = focusedElement() { hookSelection(on: f) }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

guard AXIsProcessTrusted() else {
    fputs("AX_NOT_TRUSTED\n", stderr); exit(1)
}

// 1) try to get current focused element and hook it immediately
if let f0 = focusedElement() { 
    hookSelection(on: f0)
    fputs("LiveSel helper: initial focus hooked\n", stderr)
}

// 2) Since system-wide focus notifications don't work reliably, go straight to polling
    // ----------------------------------------------------------------------
    // 2) fallback: poll every 200 ms for focus changes
    // ----------------------------------------------------------------------
    fputs("LiveSel helper: using polling for focus changes\n", stderr)
    var last: AXUIElement?

    let timer = Timer(timeInterval: 0.50, repeats: true) { _ in  // Slower polling to reduce log spam
        if let cur = focusedElement() {
            // Use CFEqual to properly compare AXUIElement objects
            let changed = (last == nil) || !CFEqual(cur, last)
            if changed {
                last = cur
                hookSelection(on: cur)
                fputs("LiveSel helper: focus changed\n", stderr)
            }
        }
    }
RunLoop.current.add(timer, forMode: .default)
RunLoop.current.run()
