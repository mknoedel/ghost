-- Returns "true" if the app is trusted for accessibility.
use framework "Foundation"
use framework "AppKit"
use scripting additions

on logInfo(msg)
    try
        set timestamp to (current date) as string
        do shell script "echo '[AppleScript][INFO] " & timestamp & " " & msg & "' >> /tmp/ghost-applescript.log"
    end try
end logInfo

on logError(msg)
    try
        set timestamp to (current date) as string
        do shell script "echo '[AppleScript][ERROR] " & timestamp & " " & msg & "' >> /tmp/ghost-applescript.log"
    end try
end logError

try
    set isTrusted to (current application's AXIsProcessTrusted()) as boolean
    
    if isTrusted then
        logInfo("Accessibility is trusted")
    else
        logError("Accessibility is NOT trusted")
    end if
    
    return isTrusted
on error e
    logError("Failed to check accessibility trust: " & e)
    return false
end try