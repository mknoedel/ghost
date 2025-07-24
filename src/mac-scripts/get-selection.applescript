-- mac-scripts/get-selection-quiet.applescript
use scripting additions
use framework "AppKit" -- gives us NSPasteboard

on logIt(msg)
    log msg
end logIt

try
    ------------------------------------------------------------------
    -- 0) Preconditions
    ------------------------------------------------------------------
    tell application "System Events"
        if not (UI elements enabled) then return ""
        set frontProc to first application process whose frontmost is true
    end tell

    ------------------------------------------------------------------
    -- 1) AXSelectedText (preferred path)
    ------------------------------------------------------------------
    try
        tell application "System Events"
            set selText to value of attribute "AXSelectedText" ¬
                         of attribute "AXFocusedUIElement" of frontProc
        end tell
        if selText is not missing value and selText ≠ "" then return selText
    end try

    ------------------------------------------------------------------
    -- 2) Clipboard fallback (quiet)
    ------------------------------------------------------------------
    -- a) Skip if “Copy” is disabled (avoids beep)
    set canCopy to false
    try
        tell application "System Events"
            tell menu bar 1 of frontProc
                set canCopy to (enabled of menu item "Copy" of ¬
                                menu 1 of menu bar item "Edit")
            end tell
        end tell
    end try
    if not canCopy then return ""

    -- b) Snapshot current clipboard & changeCount
    set pb to current application's NSPasteboard's generalPasteboard()
    set origCount to pb's changeCount()
    set origData to (do shell script "pbpaste | base64")

    -- c) Trigger copy
    tell application "System Events" to keystroke "c" using command down

    -- d) Wait (≤1 s) for changeCount bump
    repeat 20 times
        delay 0.05
        if (pb's changeCount()) > origCount then exit repeat
    end repeat

    -- e) Read clipboard (may still match old)
    set grabbed to (do shell script "pbpaste")

    -- f) Restore only if we actually changed it
    if (pb's changeCount()) > origCount then ¬
        do shell script "echo " & quoted form of origData & " | base64 -D | pbcopy"

    if grabbed ≠ "" and grabbed ≠ (do shell script "echo " & quoted form of origData & " | base64 -D") then
        return grabbed
    else
        return ""
    end if

on error e number n
    logIt("ERROR " & n & ": " & e)
    return ""
end try
