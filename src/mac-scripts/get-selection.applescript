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

    set sentinel to do shell script "uuidgen" -- random value unlikely to collide

    -- cache original clipboard (may be binary)
    set origClip to (do shell script "pbpaste | base64")

    -- set clipboard to sentinel
    do shell script "printf " & quoted form of sentinel & " | pbcopy"

    -- try to copy
    tell application "System Events" to keystroke "c" using command down

    -- wait up to 1 s for pasteboard change
    set newClipboard to ""
    repeat 20 times -- 20 × 0.05 s = 1 s
        delay 0.05
        set newClipboard to (do shell script "pbpaste")
        if newClipboard is not equal to sentinel then exit repeat
    end repeat

    -- restore original clipboard (even if we timed out)
    do shell script "echo " & quoted form of origClip & " | base64 -D | pbcopy"

    if newClipboard is equal to sentinel or newClipboard is "" then
        my logIt("No new text found in clipboard")
        return ""
    else
        my logIt("newClip len: " & (length of newClipboard))
        return newClipboard
    end if

on error e number n
    my logIt("ERROR " & n & ": " & e)
    return ""
end try
