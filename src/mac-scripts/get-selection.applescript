-- mac-scripts/get-selection-quiet.applescript
use scripting additions
use framework "AppKit" -- gives us NSPasteboard

-- Structured logging functions
on logInfo(msg)
    try
        set timestamp to (current date) as string
        do shell script "echo " & quoted form of ("[AppleScript][INFO] " & timestamp & " " & msg) & " >> /tmp/ghost-applescript.log"
    end try
end logInfo

on logError(msg)
    try
        set timestamp to (current date) as string
        do shell script "echo " & quoted form of ("[AppleScript][ERROR] " & timestamp & " " & msg) & " >> /tmp/ghost-applescript.log"
    end try
end logError

-- Legacy compatibility function
on logIt(msg)
    logInfo(msg)
end logIt

-- UI Elements check utility
on checkUIElementsEnabled()
    try
        tell application "System Events"
            return (UI elements enabled)
        end tell
    on error
        return false
    end try
end checkUIElementsEnabled

try
    ------------------------------------------------------------------
    -- 0) Preconditions
    ------------------------------------------------------------------
    if not checkUIElementsEnabled() then return ""
    
    tell application "System Events"
        set frontProc to first application process whose frontmost is true
    end tell

    ------------------------------------------------------------------
    -- 1) Clipboard
    ------------------------------------------------------------------
    -- a) SIMPLE IDLE DETECTION
    try
        set idleTimeSeconds to (do shell script "python3 -c \"import Quartz; print(int(Quartz.CGEventSourceSecondsSinceLastEventType(Quartz.kCGEventSourceStateHIDSystemState, Quartz.kCGAnyInputEventType)))\"")
        set idleTime to idleTimeSeconds as integer
        
        -- Require 30 seconds of complete system idle time (no keyboard/mouse activity)
        if idleTime < 5 then
            return "" -- User was active within last 5 seconds
        end if
    end try
    
    -- b) Skip if "Copy" is disabled (avoids beep)
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

    -- c) Snapshot current clipboard & changeCount
    set pb to current application's NSPasteboard's generalPasteboard()
    set origCount to pb's changeCount()
    set origData to (do shell script "pbpaste | base64")

    -- d) Stage 1: Check if user already has something selected
    tell application "System Events" to keystroke "c" using {command down}

    -- e) Wait for changeCount bump from Stage 1 (reduced polling)
    set pasteboardUpdated to false
    repeat 6 times
        delay 0.05
        if (pb's changeCount()) > origCount then
            set pasteboardUpdated to true
            exit repeat
        end if
    end repeat

    -- f) Stage 2: If no selection, select all text to the left of cursor
    if pasteboardUpdated is false then
        -- Select all text to the left of the cursor to understand textbox context
        tell application "System Events"
            keystroke (ASCII character 28) using {command down, shift down}
            keystroke "c" using {command down}
        end tell
        
        -- Wait for changeCount bump from Stage 2 (reduced polling)
        repeat 4 times
            delay 0.05
            if (pb's changeCount()) > origCount then
                set pasteboardUpdated to true
                exit repeat
            end if
        end repeat
        
        -- Reset cursor to original position (move right to deselect)
        if pasteboardUpdated is true then
            tell application "System Events" to keystroke (ASCII character 29) -- Right arrow
        end if
    end if

    -- g) Stage 3: Final fallback - copy URL from address bar
    if pasteboardUpdated is false then
        logIt("[URL] Attempting to copy page URL")
        
        tell application "System Events"
            -- Select address bar and copy URL in one sequence
            keystroke "l" using {command down}
            keystroke "c" using {command down}
            -- Restore address bar
            key code 53 -- Escape
        end tell
        
        -- Wait for changeCount bump from Stage 3 (reduced polling)
        repeat 4 times
            delay 0.05
            if (pb's changeCount()) > origCount then
                set pasteboardUpdated to true
                logIt("[URL] Successfully copied page URL")
                exit repeat
            end if
        end repeat
        
        if not pasteboardUpdated then
            logIt("[URL] Failed to copy page URL")
        end if
    end if

    -- g) Read clipboard (may still match old)
    set currentTextbox to (do shell script "pbpaste")

    -- h) Restore only if we actually changed it
    if (pb's changeCount()) > origCount then
        do shell script "echo " & quoted form of origData & " | base64 -D | pbcopy"
    end if

    logIt("Current Textbox: " & currentTextbox)

    if currentTextbox ≠ "" and currentTextbox ≠ (do shell script "echo " & quoted form of origData & " | base64 -D") then
        return currentTextbox
    else
        return ""
    end if

on error e number n
    logIt("ERROR " & n & ": " & e)
    return ""
end try
