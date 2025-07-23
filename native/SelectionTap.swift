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
    fputs("LiveSel helper: getting frontmost application...\n", stderr)
    guard let frontApp = NSWorkspace.shared.frontmostApplication else {
        fputs("LiveSel helper: no frontmost app\n", stderr)
        return nil
    }
    
    fputs("LiveSel helper: frontmost app is \(frontApp.localizedName ?? "unknown") (pid: \(frontApp.processIdentifier))\n", stderr)
    let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
    fputs("LiveSel helper: created app element: \(appElement)\n", stderr)
    
    var val: AnyObject?
    fputs("LiveSel helper: getting focused UI element...\n", stderr)
    let result = AXUIElementCopyAttributeValue(appElement,
                                              kAXFocusedUIElementAttribute as CFString,
                                              &val)
    fputs("LiveSel helper: AXUIElementCopyAttributeValue result: \(result.rawValue)\n", stderr)
    
    if result == .success {
        fputs("LiveSel helper: successfully got focused element\n", stderr)
        // Use forced downcast with parentheses as we know it will succeed
        let element = (val as! AXUIElement)
        fputs("LiveSel helper: element is valid AXUIElement\n", stderr)
        return element
    } else {
        fputs("LiveSel helper: failed to get focused element from \(frontApp.localizedName ?? "unknown") (error: \(result.rawValue))\n", stderr)
        // Print error description
        switch result {
        case .attributeUnsupported:
            fputs("LiveSel helper: error detail: attribute unsupported\n", stderr)
        case .noValue:
            fputs("LiveSel helper: error detail: no value\n", stderr)
        case .illegalArgument:
            fputs("LiveSel helper: error detail: illegal argument\n", stderr)
        case .invalidUIElement:
            fputs("LiveSel helper: error detail: invalid UI element\n", stderr)
        case .cannotComplete:
            fputs("LiveSel helper: error detail: cannot complete\n", stderr)
        case .notImplemented:
            fputs("LiveSel helper: error detail: not implemented\n", stderr)
        default:
            fputs("LiveSel helper: error detail: unknown error\n", stderr)
        }
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

// Helper function to translate AX error codes to readable strings
func axErrorString(_ error: AXError) -> String {
    switch error {
    case .success: return "success (0)"
    case .failure: return "failure (-25200)"
    case .illegalArgument: return "illegal argument (-25201)"
    case .invalidUIElement: return "invalid UI element (-25202)"
    case .invalidUIElementObserver: return "invalid UI element observer (-25203)"
    case .cannotComplete: return "cannot complete (-25204)"
    case .attributeUnsupported: return "attribute unsupported (-25205)"
    case .actionUnsupported: return "action unsupported (-25206)"
    case .notificationUnsupported: return "notification unsupported (-25207)"
    case .notImplemented: return "not implemented (-25208)"
    case .notificationAlreadyRegistered: return "notification already registered (-25209)"
    case .notificationNotRegistered: return "notification not registered (-25210)"
    case .apiDisabled: return "API disabled (-25211)"
    case .noValue: return "no value (-25212)"
    case .parameterizedAttributeUnsupported: return "parameterized attribute unsupported (-25213)"
    case .notEnoughPrecision: return "not enough precision (-25214)"
    default: return "unknown error (\(error.rawValue))"
    }
}

// Helper function to inspect AXUIElement properties
func inspectElement(_ element: AXUIElement) {
    fputs("LiveSel helper: INSPECTING ELEMENT PROPERTIES\n", stderr)
    
    // Get all attributes
    var attributeNames: CFArray?
    let copyResult = AXUIElementCopyAttributeNames(element, &attributeNames)
    
    if copyResult == .success, let attributes = attributeNames as? [String] {
        fputs("LiveSel helper: Element has \(attributes.count) attributes: \(attributes.joined(separator: ", "))\n", stderr)
        
        // Try to get role
        var roleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String {
            fputs("LiveSel helper: Element role: \(role)\n", stderr)
        }
        
        // Try to get subrole
        var subroleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue) == .success,
           let subrole = subroleValue as? String {
            fputs("LiveSel helper: Element subrole: \(subrole)\n", stderr)
        }
        
        // Try to get title
        var titleValue: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue) == .success,
           let title = titleValue as? String {
            fputs("LiveSel helper: Element title: \(title)\n", stderr)
        }
        
        // Check if element supports text selection
        var notificationNames: CFArray?
        if AXUIElementCopyActionNames(element, &notificationNames) == .success,
           let notifications = notificationNames as? [String] {
            fputs("LiveSel helper: Element supports notifications: \(notifications.joined(separator: ", "))\n", stderr)
        }
        
        // Check if element supports text selection notification specifically
        var isSupported: DarwinBoolean = false
        let supportResult = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSupported)
        fputs("LiveSel helper: Element supports selected text attribute? \(isSupported.boolValue) (result: \(axErrorString(supportResult)))\n", stderr)
    } else {
        fputs("LiveSel helper: Failed to get element attributes: \(axErrorString(copyResult))\n", stderr)
    }
    
    // Get process ID
    var pid: pid_t = 0
    let pidResult = AXUIElementGetPid(element, &pid)
    if pidResult == .success {
        fputs("LiveSel helper: Element belongs to process ID: \(pid)\n", stderr)
    } else {
        fputs("LiveSel helper: Failed to get element process ID: \(axErrorString(pidResult))\n", stderr)
    }
}

func hookSelection(on elem: AXUIElement) {
    fputs("LiveSel helper: hookSelection called with element \(elem)\n", stderr)
    
    // Inspect the element to understand its properties
    inspectElement(elem)
    
    // detach previous
    if let oldObs = selObserver, let oldElem = currentObservedElem {
        fputs("LiveSel helper: detaching previous observer\n", stderr)
        let removeResult = AXObserverRemoveNotification(oldObs,
                                     oldElem,
                                     kAXSelectedTextChangedNotification as CFString)
        fputs("LiveSel helper: remove notification result: \(axErrorString(removeResult))\n", stderr)
    } else {
        fputs("LiveSel helper: no previous observer to detach\n", stderr)
    }

    // attach new
    var newObsPtr: AXObserver?
    
    // Get the process ID of the element
    var pid: pid_t = 0
    let pidResult = AXUIElementGetPid(elem, &pid)
    if pidResult != .success {
        fputs("LiveSel helper: failed to get process ID for element: \(axErrorString(pidResult))\n", stderr)
        return // Cannot create observer without process ID
    }
    
    fputs("LiveSel helper: creating observer for process ID: \(pid)\n", stderr)
    let createResult = AXObserverCreate(pid, selectionCB, &newObsPtr)
    fputs("LiveSel helper: observer create result: \(axErrorString(createResult))\n", stderr)
    
    if createResult == .success {
        fputs("LiveSel helper: observer created successfully\n", stderr)
        
        if let newObs = newObsPtr {
            fputs("LiveSel helper: adding notification...\n", stderr)
            let addResult = AXObserverAddNotification(newObs,
                                 elem,
                                 kAXSelectedTextChangedNotification as CFString,
                                 nil)
            fputs("LiveSel helper: add notification result: \(axErrorString(addResult))\n", stderr)
            
            if addResult == .success {
                fputs("LiveSel helper: notification added successfully\n", stderr)
                fputs("LiveSel helper: adding to run loop...\n", stderr)
                
                CFRunLoopAddSource(CFRunLoopGetCurrent(),
                           AXObserverGetRunLoopSource(newObs),
                           .defaultMode)
                           
                fputs("LiveSel helper: added to run loop\n", stderr)
                selObserver = newObs
                currentObservedElem = elem
                fputs("LiveSel helper: observer setup complete\n", stderr)
            } else {
                fputs("LiveSel helper: failed to add notification to observer\n", stderr)
            }
        } else {
            fputs("LiveSel helper: observer pointer is nil despite successful creation\n", stderr)
        }
    } else {
        fputs("LiveSel helper: failed to create observer\n", stderr)
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
    var pollCount = 0

    let timer = Timer(timeInterval: 0.50, repeats: true) { _ in  // Slower polling to reduce log spam
        pollCount += 1
        fputs("LiveSel helper: poll #\(pollCount) starting...\n", stderr)
        
        if let cur = focusedElement() {
            fputs("LiveSel helper: poll #\(pollCount) found focused element\n", stderr)
            
            // Use CFEqual to properly compare AXUIElement objects
            let changed = (last == nil) || !CFEqual(cur, last)
            fputs("LiveSel helper: poll #\(pollCount) focus changed? \(changed)\n", stderr)
            
            if changed {
                fputs("LiveSel helper: poll #\(pollCount) focus changed, updating last element\n", stderr)
                last = cur
                fputs("LiveSel helper: poll #\(pollCount) calling hookSelection...\n", stderr)
                hookSelection(on: cur)
                fputs("LiveSel helper: poll #\(pollCount) focus changed and hookSelection called\n", stderr)
            } else {
                fputs("LiveSel helper: poll #\(pollCount) no focus change detected\n", stderr)
            }
        } else {
            fputs("LiveSel helper: poll #\(pollCount) no focused element found\n", stderr)
        }
        
        fputs("LiveSel helper: poll #\(pollCount) complete\n", stderr)
    }
RunLoop.current.add(timer, forMode: .default)
RunLoop.current.run()
