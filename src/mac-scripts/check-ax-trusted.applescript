-- Returns "true" if the app is trusted for accessibility.
use framework "Foundation"
use framework "AppKit"
use scripting additions
return (current application's AXIsProcessTrusted()) as boolean
