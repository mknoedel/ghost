// WorkflowAnalyzer.swift – Content Analysis and App/Site Categorization
// -------------------------------------------------------------
// Handles content analysis, workflow context generation, and
// categorization of applications and websites for better event
// understanding and filtering.
// -------------------------------------------------------------

import Foundation

// MARK: - Workflow Analysis Utilities

class WorkflowAnalyzer {
    private static var currentSessionId = UUID().uuidString
    private static var sequenceCounter: Int64 = 0
    private static var lastEventTime: Date = .init()
    private static var lastContextHash = ""
    private static var appCategoryCache: [String: String] = [:]

    static func generateWorkflowContext(
        for event: String,
        content: String? = nil
    )
        -> WorkflowContext {
        // Ultra-safe version to prevent all crashes
        let now = Date()
        let timeSinceLastEvent = max(0, now.timeIntervalSince(lastEventTime))

        // Reset session if too much time has passed (30 minutes)
        if timeSinceLastEvent > 1800 {
            currentSessionId = UUID().uuidString
            sequenceCounter = 0
        }

        // Safe increment with bounds checking
        if sequenceCounter < Int64.max - 1 {
            sequenceCounter += 1
        }
        else {
            sequenceCounter = 1
        }

        lastEventTime = now

        // Simple, safe hash without complex operations
        let simpleHash = String((event + (content ?? "")).count)
        let phase = lastContextHash == simpleHash ? "focused" : "transition"

        lastContextHash = simpleHash

        return WorkflowContext(
            sessionId: currentSessionId,
            sequenceNumber: sequenceCounter,
            timeSinceLastEvent: timeSinceLastEvent,
            contextHash: simpleHash,
            workflowPhase: phase
        )
    }

    static func analyzeContent(_ text: String) -> ContentMetadata {
        let contentType = classifyContentType(text)

        return ContentMetadata(
            contentType: contentType
        )
    }

    static func generateInteractionContext() -> InteractionContext {
        let isMultitasking = isMultitaskingActive()

        return InteractionContext(
            isMultitasking: isMultitasking
        )
    }

    // MARK: - Content Analysis Functions

    /// Classifies text content into semantic categories for better context understanding
    /// - Parameter text: The text content to classify
    /// - Returns: A string representing the content type, or "text" as fallback
    private static func classifyContentType(_ text: String) -> String {
        // Early exit for empty or very short text
        guard
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.count >= 3
        else {
            return "text"
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if isEmailContent(trimmed, lowercased: lowercased) {
            return "email"
        }
        if isCodeContent(trimmed, lowercased: lowercased) {
            return "code"
        }
        if isWebContent(trimmed, lowercased: lowercased) {
            return "web"
        }
        if isTaskContent(trimmed, lowercased: lowercased) {
            return "task"
        }
        if isCalendarContent(trimmed, lowercased: lowercased) {
            return "calendar"
        }
        return "text"
    }

    // MARK: - Content Type Detectors

    /// Detects email content with safe pattern matching (no regex)
    private static func isEmailContent(_ text: String, lowercased: String) -> Bool {
        // Simple email detection without dangerous regex
        let hasAtAndDot = lowercased.contains("@") && lowercased.contains(".")

        // Email header patterns
        let emailHeaders = [
            "from:",
            "to:",
            "subject:",
            "cc:",
            "bcc:",
            "reply-to:",
            "date:"
        ]
        let hasEmailHeaders = emailHeaders.contains { lowercased.contains($0) }

        // Email signature patterns
        let hasEmailSignature = lowercased.contains("sent from my") ||
            lowercased.contains("best regards") ||
            lowercased.contains("sincerely")

        return hasAtAndDot || hasEmailHeaders || hasEmailSignature
    }

    /// Detects code content with comprehensive language patterns
    private static func isCodeContent(_ text: String, lowercased: String) -> Bool {
        // Programming language keywords and patterns
        let codeKeywords = [
            // General programming
            "func ", "function ", "def ", "class ", "struct ", "enum ", "interface ",
            "import ", "#include", "require(", "from ", "export ",
            // Control flow
            "if (", "else {", "for (", "while (", "switch (", "case ",
            // Common symbols
            " => ", " -> ", "() {", "} else", "return ", "throw ",
            // Language specific
            "console.log", "print(", "println", "std::", "public class", "private "
        ]

        let hasCodeKeywords = codeKeywords.contains { lowercased.contains($0) }

        // Check for code-like structure (brackets, semicolons, etc.)
        let codeStructureCount = text.filter { "{};()[]<>".contains($0) }.count
        let hasCodeStructure = codeStructureCount > text
            .count / 20 // At least 5% structural chars

        // File extension patterns in text
        let codeExtensions = [
            ".js",
            ".py",
            ".swift",
            ".java",
            ".cpp",
            ".c",
            ".h",
            ".ts",
            ".go",
            ".rs"
        ]
        let hasCodeExtensions = codeExtensions.contains { lowercased.contains($0) }

        return hasCodeKeywords || (hasCodeStructure && text.count > 50) ||
            hasCodeExtensions
    }

    /// Detects web content (URLs, HTML, etc.) - safe string matching only
    private static func isWebContent(_ text: String, lowercased: String) -> Bool {
        // URL patterns
        let urlPrefixes = ["http://", "https://", "www.", "ftp://"]
        let hasURL = urlPrefixes.contains { lowercased.contains($0) }

        // HTML/XML patterns
        let htmlPatterns = ["<html", "<div", "<span", "<p>", "</", "href=", "src="]
        let hasHTML = htmlPatterns.contains { lowercased.contains($0) }

        // Simple domain detection without dangerous regex
        let domainSuffixes = [".com", ".org", ".net", ".edu", ".gov", ".io", ".co"]
        let hasDomain = domainSuffixes.contains { lowercased.contains($0) }

        return hasURL || hasHTML || hasDomain
    }

    /// Detects task/todo content
    private static func isTaskContent(_ text: String, lowercased: String) -> Bool {
        let taskKeywords = [
            "todo:", "task:", "fixme:", "hack:", "note:",
            "[ ]", "[x]", "- [ ]", "- [x]",
            "deadline:", "due:", "priority:", "assigned:"
        ]

        let hasTaskKeywords = taskKeywords.contains { lowercased.contains($0) }

        // Check for numbered/bulleted lists that might be tasks - safe string matching
        let lines = text.components(separatedBy: .newlines)
        let taskLikeLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") ||
                (trimmed.count > 3 && trimmed.prefix(3)
                    .allSatisfy { $0.isNumber || $0 == "." || $0 == " " }
                )
        }

        let hasTaskStructure = taskLikeLines.count >= 2 && taskLikeLines.count > lines
            .count / 3

        return hasTaskKeywords || hasTaskStructure
    }

    /// Detects calendar/meeting content
    private static func isCalendarContent(_ text: String, lowercased: String) -> Bool {
        let calendarKeywords = [
            "meeting", "schedule", "appointment", "calendar", "event",
            "zoom", "teams", "webex", "conference call",
            "agenda", "attendees", "location:", "when:", "time:",
            "am", "pm", "today", "tomorrow", "monday", "tuesday", "wednesday", "thursday",
            "friday"
        ]

        let keywordMatches = calendarKeywords.filter { lowercased.contains($0) }.count

        // Simple time/date detection without dangerous regex
        let hasTimePattern = lowercased
            .contains(":") && (lowercased.contains("am") || lowercased.contains("pm"))

        let hasDatePattern = lowercased.contains("/") || lowercased.contains("-") ||
            lowercased.contains("monday") || lowercased.contains("tuesday") ||
            lowercased.contains("2024") || lowercased.contains("2025")

        return keywordMatches >= 2 || hasTimePattern || hasDatePattern
    }

    private static func isMultitaskingActive() -> Bool {
        // Simplified multitasking detection to avoid expensive NSWorkspace calls
        // Just return a reasonable default for now
        true
    }

    /// Categorizes applications by their bundle identifier with comprehensive pattern
    /// matching
    /// - Parameter bundleId: The application bundle identifier
    /// - Returns: A category string or nil if unable to categorize
    static func categorizeApp(_ bundleId: String) -> String? {
        // Check cache first for performance
        if let cached = appCategoryCache[bundleId] {
            return cached
        }

        guard !bundleId.isEmpty else { return "other" }

        let lowercased = bundleId.lowercased()
        let category = determineAppCategory(lowercased)

        // Cache the result for future lookups with size limit
        if let category {
            // Prevent unbounded cache growth
            if appCategoryCache.count > 100 {
                appCategoryCache.removeAll()
                logWarn("App category cache exceeded size limit (100) and was cleared")
            }
            appCategoryCache[bundleId] = category
        }

        return category
    }

    /// Categorizes websites by their domain with enhanced pattern recognition
    /// - Parameter domain: The website domain
    /// - Returns: A category string representing the website type
    static func categorizeWebsite(_ domain: String) -> String? {
        guard !domain.isEmpty else { return "web" }

        let cleaned = cleanDomain(domain)
        let lowercased = cleaned.lowercased()

        return determineWebsiteCategory(lowercased)
    }

    // MARK: - App Category Detectors

    /// Determines the category of an application based on its bundle identifier
    private static func determineAppCategory(_ bundleId: String) -> String? {
        if isDevelopmentApp(bundleId) {
            return "development"
        }
        if isCommunicationApp(bundleId) {
            return "communication"
        }
        if isWebBrowser(bundleId) {
            return "web"
        }
        if isWritingApp(bundleId) {
            return "writing"
        }
        if isDataApp(bundleId) {
            return "data"
        }
        if isEntertainmentApp(bundleId) {
            return "entertainment"
        }
        if isDesignApp(bundleId) {
            return "design"
        }
        if isProductivityApp(bundleId) {
            return "productivity"
        }
        if isSystemApp(bundleId) {
            return "system"
        }
        return "other"
    }

    /// Detects development applications
    private static func isDevelopmentApp(_ bundleId: String) -> Bool {
        let devPatterns = [
            "xcode", "vscode", "code", "intellij", "pycharm", "webstorm", "phpstorm",
            "sublime", "atom", "vim", "emacs", "terminal", "iterm", "git", "github",
            "sourcetree", "tower", "fork", "postman", "insomnia", "docker",
            "simulator", "instruments", "dash", "kaleidoscope", "beyond", "compare"
        ]
        return devPatterns.contains { bundleId.contains($0) }
    }

    /// Detects communication applications
    private static func isCommunicationApp(_ bundleId: String) -> Bool {
        let commPatterns = [
            "slack", "teams", "zoom", "skype", "discord", "telegram", "whatsapp",
            "signal", "facetime", "messages", "mail", "outlook", "thunderbird",
            "spark", "airmail", "canary", "mimestream", "webex", "gotomeeting"
        ]
        return commPatterns.contains { bundleId.contains($0) }
    }

    /// Detects web browsers
    private static func isWebBrowser(_ bundleId: String) -> Bool {
        let browserPatterns = [
            "safari", "chrome", "firefox", "edge", "opera", "brave", "arc",
            "vivaldi", "tor", "webkit", "browser"
        ]
        return browserPatterns.contains { bundleId.contains($0) }
    }

    /// Detects writing and document applications
    private static func isWritingApp(_ bundleId: String) -> Bool {
        let writingPatterns = [
            "word", "pages", "docs", "writer", "scrivener", "ulysses", "bear",
            "notion", "obsidian", "typora", "markdown", "drafts", "iawriter",
            "byword", "writeroom", "focused", "textedit"
        ]
        return writingPatterns.contains { bundleId.contains($0) }
    }

    /// Detects data and spreadsheet applications
    private static func isDataApp(_ bundleId: String) -> Bool {
        let dataPatterns = [
            "excel", "numbers", "sheets", "calc", "tableau", "power", "bi",
            "database", "sequel", "mysql", "postgres", "mongodb", "redis",
            "datagrip", "navicat", "querious", "core", "data"
        ]
        return dataPatterns.contains { bundleId.contains($0) }
    }

    /// Detects entertainment applications
    private static func isEntertainmentApp(_ bundleId: String) -> Bool {
        let entertainmentPatterns = [
            "spotify", "music", "netflix", "youtube", "twitch", "steam", "epic",
            "games", "tv", "video", "vlc", "plex", "kodi", "quicktime",
            "photos", "preview", "adobe", "lightroom", "photoshop"
        ]
        return entertainmentPatterns.contains { bundleId.contains($0) }
    }

    /// Detects design and creative applications
    private static func isDesignApp(_ bundleId: String) -> Bool {
        let designPatterns = [
            "sketch", "figma", "adobe", "photoshop", "illustrator", "indesign",
            "after", "effects", "premiere", "final", "cut", "logic", "pro",
            "garageband", "keynote", "powerpoint", "canva", "affinity",
            "pixelmator", "procreate", "blender", "cinema", "maya"
        ]
        return designPatterns.contains { bundleId.contains($0) }
    }

    /// Detects productivity applications
    private static func isProductivityApp(_ bundleId: String) -> Bool {
        let productivityPatterns = [
            "calendar", "reminder", "todo", "task", "project", "trello", "asana",
            "monday", "clickup", "notion", "evernote", "onenote", "notes",
            "finder", "file", "manager", "dropbox", "drive", "icloud",
            "1password", "keychain", "bitwarden", "lastpass"
        ]
        return productivityPatterns.contains { bundleId.contains($0) }
    }

    /// Detects system and utility applications
    private static func isSystemApp(_ bundleId: String) -> Bool {
        let systemPatterns = [
            "activity", "monitor", "console", "system", "preferences", "settings",
            "cleaner", "disk", "utility", "maintenance", "backup", "time", "machine",
            "migration", "boot", "camp", "parallels", "vmware", "virtualbox"
        ]
        return systemPatterns.contains { bundleId.contains($0) }
    }

    // MARK: - Website Category Detectors

    /// Cleans and normalizes domain for categorization
    private static func cleanDomain(_ domain: String) -> String {
        var cleaned = domain.lowercased()

        // Remove common prefixes
        let prefixes = ["https://", "http://", "www.", "m."]
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }

        // Remove path and query parameters
        if let slashIndex = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slashIndex])
        }

        return cleaned
    }

    /// Determines the category of a website based on its domain
    private static func determineWebsiteCategory(_ domain: String) -> String? {
        if isDevelopmentSite(domain) {
            return "development"
        }
        if isCommunicationSite(domain) {
            return "communication"
        }
        if isSearchSite(domain) {
            return "search"
        }
        if isEntertainmentSite(domain) {
            return "entertainment"
        }
        if isShoppingSite(domain) {
            return "shopping"
        }
        if isNewsSite(domain) {
            return "news"
        }
        if isSocialSite(domain) {
            return "social"
        }
        if isEmailSite(domain) {
            return "email"
        }
        if isEducationalSite(domain) {
            return "education"
        }
        if isFinanceSite(domain) {
            return "finance"
        }
        return "web"
    }

    /// Detects development and technical websites
    private static func isDevelopmentSite(_ domain: String) -> Bool {
        let devSites = [
            "github", "gitlab", "bitbucket", "stackoverflow", "stackexchange",
            "docs.", "developer.", "api.", "npmjs", "pypi", "maven", "nuget",
            "docker", "kubernetes", "aws", "azure", "gcp", "heroku", "vercel",
            "netlify", "codepen", "jsfiddle", "repl", "codesandbox"
        ]
        return devSites.contains { domain.contains($0) }
    }

    /// Detects communication websites
    private static func isCommunicationSite(_ domain: String) -> Bool {
        let commSites = [
            "slack", "teams", "discord", "telegram", "whatsapp", "signal",
            "zoom", "meet", "webex", "gotomeeting", "skype", "facetime"
        ]
        return commSites.contains { domain.contains($0) }
    }

    /// Detects search engines
    private static func isSearchSite(_ domain: String) -> Bool {
        let searchSites = [
            "google", "bing", "yahoo", "duckduckgo", "baidu", "yandex",
            "search", "ask", "aol", "startpage", "searx"
        ]
        return searchSites.contains { domain.contains($0) }
    }

    /// Detects entertainment websites
    private static func isEntertainmentSite(_ domain: String) -> Bool {
        let entertainmentSites = [
            "youtube", "netflix", "hulu", "disney", "amazon", "prime", "video",
            "twitch", "spotify", "apple", "music", "soundcloud", "pandora",
            "steam", "epic", "games", "ign", "gamespot", "polygon"
        ]
        return entertainmentSites.contains { domain.contains($0) }
    }

    /// Detects shopping websites
    private static func isShoppingSite(_ domain: String) -> Bool {
        let shoppingSites = [
            "amazon", "ebay", "etsy", "shopify", "walmart", "target", "bestbuy",
            "shop", "store", "buy", "cart", "checkout", "alibaba", "aliexpress",
            "mercado", "craigslist", "marketplace"
        ]
        return shoppingSites.contains { domain.contains($0) }
    }

    /// Detects news and media websites
    private static func isNewsSite(_ domain: String) -> Bool {
        let newsSites = [
            "cnn", "bbc", "reuters", "ap", "news", "nytimes", "wsj", "guardian",
            "fox", "msnbc", "npr", "pbs", "abc", "cbs", "nbc", "bloomberg",
            "techcrunch", "verge", "wired", "ars", "engadget", "gizmodo"
        ]
        return newsSites.contains { domain.contains($0) }
    }

    /// Detects social media websites
    private static func isSocialSite(_ domain: String) -> Bool {
        let socialSites = [
            "facebook", "twitter", "instagram", "linkedin", "tiktok", "snapchat",
            "reddit", "pinterest", "tumblr", "mastodon", "threads", "bluesky",
            "social", "community", "forum"
        ]
        return socialSites.contains { domain.contains($0) }
    }

    /// Detects email service websites
    private static func isEmailSite(_ domain: String) -> Bool {
        let emailSites = [
            "gmail", "outlook", "yahoo", "mail", "protonmail", "tutanota",
            "fastmail", "icloud", "aol", "thunderbird"
        ]
        return emailSites.contains { domain.contains($0) }
    }

    /// Detects educational websites
    private static func isEducationalSite(_ domain: String) -> Bool {
        let educationSites = [
            "edu", "coursera", "udemy", "khan", "edx", "mit", "stanford",
            "harvard", "university", "college", "school", "learn", "tutorial",
            "wikipedia", "wiki", "academic", "research"
        ]
        return educationSites.contains { domain.contains($0) }
    }

    /// Detects finance and banking websites
    private static func isFinanceSite(_ domain: String) -> Bool {
        let financeSites = [
            "bank", "chase", "wells", "fargo", "citi", "bofa", "paypal", "venmo",
            "stripe", "square", "mint", "quicken", "turbotax", "credit", "loan",
            "mortgage", "invest", "trading", "crypto", "bitcoin", "coinbase"
        ]
        return financeSites.contains { domain.contains($0) }
    }
}
