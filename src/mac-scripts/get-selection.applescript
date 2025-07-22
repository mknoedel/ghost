-- mac-scripts/get-selection.applescript  (my‑prefix added)

use scripting additions

on logIt(msg)
    log msg -- goes to osascript stderr
end logIt

try
    my logIt("=== script start ===")

    -- 0)  UI‑scripting permission
    tell application "System Events"
        if not (UI elements enabled) then
            my logIt("UI‑scripting NOT enabled")
            return ""
        end if
    end tell

    -- 1)  Frontmost process
    tell application "System Events"
        set frontProc to first application process whose frontmost is true
    end tell
    my logIt("front app: " & (name of frontProc))

    -- 2)  Focused element
    set focusedOK to false
    try
        tell application "System Events"
            set focusedElem to value of attribute "AXFocusedUIElement" of frontProc
            set focusedOK to true
        end tell
    on error errMsg number errNum
        my logIt("AXFocusedUIElement error " & errNum & ": " & errMsg)
    end try
    if not focusedOK then return ""

    -- 3)  Selected text
    set selText to ""
    try
        tell application "System Events"
            set selText to value of attribute "AXSelectedText" of focusedElem
        end tell
    on error errMsg number errNum
        my logIt("AXSelectedText error " & errNum & ": " & errMsg)
    end try

    if selText is not missing value and selText is not "" then
        my logIt("selText length: " & (length of selText))
        return selText
    end if

    ----------------------------------------------------------------
    -- 4) Clipboard fallback
    ----------------------------------------------------------------
    my logIt("fallback -> Command‑C")

    set savedClip to the clipboard
    tell application "System Events" to keystroke "c" using command down
    delay 0.20
    set newClip to the clipboard
    set the clipboard to savedClip
    my logIt("newClip len: " & (length of newClip))
    return newClip

on error e number n
    my logIt("ERROR " & n & ": " & e)
    return ""
end try
