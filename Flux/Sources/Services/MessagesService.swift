import AppKit
import Foundation

/// Provides lightweight Messages.app automation via AppleScript.
///
/// Important limitation: AppleScript can list chats/accounts and send messages,
/// but it does not provide full chat transcript/history access.
actor MessagesService {
    static let shared = MessagesService()

    private init() {}

    // MARK: - Public API

    func listAccounts() async -> String {
        let script = """
        on sanitize(v)
            set s to ""
            try
                set s to v as text
            end try

            set AppleScript's text item delimiters to return
            set parts1 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts1 as text

            set AppleScript's text item delimiters to linefeed
            set parts2 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts2 as text

            set AppleScript's text item delimiters to tab
            set parts3 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts3 as text

            set AppleScript's text item delimiters to ""
            return s
        end sanitize

        tell application "Messages"
            set rows to {}
            repeat with a in accounts
                set accountId to ""
                set accountDescription to ""
                set serviceName to ""
                set connectionStatus to ""
                set enabledValue to false

                try
                    set accountId to id of a as text
                end try
                try
                    set accountDescription to description of a as text
                end try
                try
                    set serviceName to (service type of a) as text
                end try
                try
                    set connectionStatus to (connection status of a) as text
                end try
                try
                    set enabledValue to enabled of a
                end try

                set enabledText to "false"
                if enabledValue then set enabledText to "true"

                set rowText to (my sanitize(accountId) & tab & my sanitize(accountDescription) & tab & my sanitize(serviceName) & tab & enabledText & tab & my sanitize(connectionStatus))
                set end of rows to rowText
            end repeat

            set AppleScript's text item delimiters to linefeed
            set outputText to rows as text
            set AppleScript's text item delimiters to ""
            return outputText
        end tell
        """

        let result = await executeAppleScript(script)
        switch result {
        case .failure(let failure):
            return errorResponse(for: failure)

        case .success(let output):
            let lines = splitLines(output)
            let accounts = lines.compactMap(parseAccountRow)
            return encodeJSON(AccountsResponse(ok: true, count: accounts.count, accounts: accounts, error: nil))
        }
    }

    func listChats(limit: Int = 10, service: String? = nil) async -> String {
        let safeLimit = min(max(limit, 1), 50)

        guard let filter = ChatServiceFilter.parse(service) else {
            return encodeJSON(ChatsResponse(ok: false, count: 0, chats: [], error: "Invalid service filter. Use one of: any, imessage, sms, rcs."))
        }

        let script = """
        set maxCount to \(safeLimit)
        set serviceFilter to "\(escapeAppleScriptString(filter.appleScriptValue))"

        on sanitize(v)
            set s to ""
            try
                set s to v as text
            end try

            set AppleScript's text item delimiters to return
            set parts1 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts1 as text

            set AppleScript's text item delimiters to linefeed
            set parts2 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts2 as text

            set AppleScript's text item delimiters to tab
            set parts3 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts3 as text

            set AppleScript's text item delimiters to ""
            return s
        end sanitize

        tell application "Messages"
            set rows to {}
            set addedCount to 0

            repeat with c in chats
                set includeChat to true
                set serviceName to ""
                try
                    set serviceName to (service type of account of c) as text
                end try

                if serviceFilter is not "any" then
                    if serviceName is not serviceFilter then set includeChat to false
                end if

                if includeChat then
                    set chatId to ""
                    set chatName to ""

                    try
                        set chatId to id of c as text
                    end try
                    try
                        set chatName to name of c as text
                    end try

                    set participantEntries to {}
                    try
                        set pList to participants of c
                        repeat with p in pList
                            set handleText to ""
                            set nameText to ""
                            try
                                set handleText to handle of p as text
                            end try
                            try
                                set nameText to name of p as text
                            end try
                            set end of participantEntries to (my sanitize(handleText) & "::" & my sanitize(nameText))
                        end repeat
                    end try

                    set AppleScript's text item delimiters to "||"
                    set participantsBlob to participantEntries as text
                    set AppleScript's text item delimiters to ""

                    set rowText to (my sanitize(chatId) & tab & my sanitize(chatName) & tab & my sanitize(serviceName) & tab & participantsBlob)
                    set end of rows to rowText

                    set addedCount to addedCount + 1
                    if addedCount is greater than or equal to maxCount then exit repeat
                end if
            end repeat

            set AppleScript's text item delimiters to linefeed
            set outputText to rows as text
            set AppleScript's text item delimiters to ""
            return outputText
        end tell
        """

        let result = await executeAppleScript(script)
        switch result {
        case .failure(let failure):
            return errorResponse(for: failure)

        case .success(let output):
            let rows = splitLines(output)
            let chats = rows.compactMap(parseChatRow)
            return encodeJSON(ChatsResponse(ok: true, count: chats.count, chats: chats, error: nil))
        }
    }

    func sendMessage(
        to: String?,
        chatId: String?,
        text: String?,
        filePath: String?,
        service: String? = nil
    ) async -> String {
        let recipient = (to ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let targetChatId = (chatId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let messageText = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !recipient.isEmpty || !targetChatId.isEmpty else {
            return encodeJSON(SendResponse(
                ok: false,
                recipient: nil,
                chatId: nil,
                service: nil,
                sentText: false,
                sentFile: false,
                destinationType: nil,
                error: "Provide either `to` (recipient handle) or `chatId`."
            ))
        }

        var resolvedAttachmentPath = ""
        if let rawPath = filePath?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
            let fileURL = resolvedPathURL(for: rawPath)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
            guard exists, !isDirectory.boolValue else {
                return encodeJSON(SendResponse(
                    ok: false,
                    recipient: recipient.isEmpty ? nil : recipient,
                    chatId: targetChatId.isEmpty ? nil : targetChatId,
                    service: nil,
                    sentText: false,
                    sentFile: false,
                    destinationType: nil,
                    error: "Attachment file not found: \(fileURL.path)"
                ))
            }
            resolvedAttachmentPath = fileURL.path
        }

        guard !messageText.isEmpty || !resolvedAttachmentPath.isEmpty else {
            return encodeJSON(SendResponse(
                ok: false,
                recipient: recipient.isEmpty ? nil : recipient,
                chatId: targetChatId.isEmpty ? nil : targetChatId,
                service: nil,
                sentText: false,
                sentFile: false,
                destinationType: nil,
                error: "Provide `text` and/or `filePath`."
            ))
        }

        guard let deliveryPreference = DeliveryServicePreference.parse(service) else {
            return encodeJSON(SendResponse(
                ok: false,
                recipient: recipient.isEmpty ? nil : recipient,
                chatId: targetChatId.isEmpty ? nil : targetChatId,
                service: nil,
                sentText: false,
                sentFile: false,
                destinationType: nil,
                error: "Invalid service. Use one of: auto, imessage, sms, rcs."
            ))
        }

        // `service` only applies when targeting a handle (`to`), not a chat ID.
        let effectiveService = targetChatId.isEmpty ? deliveryPreference.appleScriptValue : "auto"

        let script = """
        set recipientHandle to "\(escapeAppleScriptString(recipient))"
        set chatIdentifier to "\(escapeAppleScriptString(targetChatId))"
        set outgoingText to "\(escapeAppleScriptString(messageText))"
        set attachmentPath to "\(escapeAppleScriptString(resolvedAttachmentPath))"
        set servicePreference to "\(escapeAppleScriptString(effectiveService))"

        on sanitize(v)
            set s to ""
            try
                set s to v as text
            end try

            set AppleScript's text item delimiters to return
            set parts1 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts1 as text

            set AppleScript's text item delimiters to linefeed
            set parts2 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts2 as text

            set AppleScript's text item delimiters to tab
            set parts3 to every text item of s
            set AppleScript's text item delimiters to " "
            set s to parts3 as text

            set AppleScript's text item delimiters to ""
            return s
        end sanitize

        on first_enabled_account(accountList)
            repeat with a in accountList
                try
                    if (enabled of a) is true then return a
                end try
            end repeat
            return missing value
        end first_enabled_account

        on first_enabled_account_with_service(accountList, wantedService)
            repeat with a in accountList
                try
                    if (enabled of a) is true then
                        if ((service type of a) as text) is wantedService then return a
                    end if
                end try
            end repeat
            return missing value
        end first_enabled_account_with_service

        tell application "Messages"
            set targetAccount to missing value
            set destination to missing value
            set destinationType to "participant"

            if chatIdentifier is not "" then
                set destinationType to "chat"
                try
                    set destination to chat id chatIdentifier
                on error
                    error "Chat not found for id: " & chatIdentifier number 1001
                end try
            else
                set accountList to accounts

                if servicePreference is "auto" then
                    set targetAccount to my first_enabled_account_with_service(accountList, "iMessage")
                    if targetAccount is missing value then set targetAccount to my first_enabled_account_with_service(accountList, "RCS")
                    if targetAccount is missing value then set targetAccount to my first_enabled_account_with_service(accountList, "SMS")
                    if targetAccount is missing value then set targetAccount to my first_enabled_account(accountList)
                else
                    set targetAccount to my first_enabled_account_with_service(accountList, servicePreference)
                end if

                if targetAccount is missing value then
                    error "No enabled Messages account available for service: " & servicePreference number 1002
                end if

                set targetParticipant to missing value
                try
                    set targetParticipant to participant recipientHandle of targetAccount
                end try
                if targetParticipant is missing value then
                    try
                        set targetParticipant to buddy recipientHandle of targetAccount
                    end try
                end if
                if targetParticipant is missing value then
                    error "Recipient not found: " & recipientHandle number 1003
                end if

                set destination to targetParticipant
            end if

            if outgoingText is not "" then
                send outgoingText to destination
            end if

            if attachmentPath is not "" then
                set attachmentAlias to POSIX file attachmentPath
                send attachmentAlias to destination
            end if

            set chosenService to ""
            try
                if targetAccount is not missing value then
                    set chosenService to (service type of targetAccount) as text
                else
                    set chosenService to (service type of account of destination) as text
                end if
            end try

            return my sanitize(chosenService) & tab & destinationType
        end tell
        """

        let result = await executeAppleScript(script)
        switch result {
        case .failure(let failure):
            return errorResponse(for: failure)

        case .success(let output):
            let parts = output.components(separatedBy: "\t")
            let serviceName = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            let destinationType = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil

            return encodeJSON(SendResponse(
                ok: true,
                recipient: recipient.isEmpty ? nil : recipient,
                chatId: targetChatId.isEmpty ? nil : targetChatId,
                service: serviceName?.isEmpty == true ? nil : serviceName,
                sentText: !messageText.isEmpty,
                sentFile: !resolvedAttachmentPath.isEmpty,
                destinationType: destinationType?.isEmpty == true ? nil : destinationType,
                error: nil
            ))
        }
    }

    // MARK: - AppleScript execution

    private struct ScriptFailure: Error {
        let message: String
        let code: Int?
    }

    private func executeAppleScript(_ source: String) async -> Result<String, ScriptFailure> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let appleScript = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(ScriptFailure(message: "Failed to create AppleScript.", code: nil)))
                    return
                }

                var errorInfo: NSDictionary?
                let descriptor = appleScript.executeAndReturnError(&errorInfo)

                if let errorInfo {
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "AppleScript execution failed."
                    let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                    Log.tools.error("Messages AppleScript failed (code=\(code ?? 0)): \(message)")
                    continuation.resume(returning: .failure(ScriptFailure(message: message, code: code)))
                    return
                }

                let output = descriptor.stringValue ?? ""
                continuation.resume(returning: .success(output.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }

    // MARK: - Parsing / Encoding

    private func splitLines(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func parseAccountRow(_ row: String) -> MessageAccount? {
        let columns = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 5 else { return nil }

        return MessageAccount(
            id: columns[0],
            description: columns[1],
            service: columns[2],
            enabled: parseBool(columns[3]),
            connectionStatus: columns[4]
        )
    }

    private func parseChatRow(_ row: String) -> MessageChat? {
        let columns = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 4 else { return nil }

        let participantsBlob = columns[3]
        let participants: [MessageParticipant]
        if participantsBlob.isEmpty {
            participants = []
        } else {
            participants = participantsBlob
                .components(separatedBy: "||")
                .map { raw in
                    let pair = raw.components(separatedBy: "::")
                    if pair.count >= 2 {
                        return MessageParticipant(handle: pair[0], name: pair[1])
                    }
                    return MessageParticipant(handle: raw, name: "")
                }
        }

        return MessageChat(
            chatId: columns[0],
            name: columns[1],
            service: columns[2],
            participants: participants
        )
    }

    private func parseBool(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":\"Failed to encode JSON response.\"}"
        }
        return json
    }

    private func errorResponse(for failure: ScriptFailure) -> String {
        if isAutomationPermissionError(code: failure.code, message: failure.message) {
            return encodeJSON(GenericErrorResponse(
                ok: false,
                error: "Messages automation access denied. Open System Settings > Privacy & Security > Automation, enable Flux for Messages, then try again."
            ))
        }

        return encodeJSON(GenericErrorResponse(
            ok: false,
            error: failure.message
        ))
    }

    private func isAutomationPermissionError(code: Int?, message: String) -> Bool {
        if code == -1743 { return true }
        let lower = message.lowercased()
        return lower.contains("not authorized") || lower.contains("not permitted")
    }

    // MARK: - Utilities

    private func resolvedPathURL(for rawPath: String) -> URL {
        let expanded = (rawPath as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return cwd.appendingPathComponent(expanded).standardizedFileURL
    }

    private nonisolated func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}

// MARK: - Models

private enum ChatServiceFilter {
    case any
    case imessage
    case sms
    case rcs

    var appleScriptValue: String {
        switch self {
        case .any: return "any"
        case .imessage: return "iMessage"
        case .sms: return "SMS"
        case .rcs: return "RCS"
        }
    }

    static func parse(_ raw: String?) -> ChatServiceFilter? {
        guard let raw else { return .any }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "any", "auto": return .any
        case "imessage", "i-message", "i message": return .imessage
        case "sms": return .sms
        case "rcs": return .rcs
        default: return nil
        }
    }
}

private enum DeliveryServicePreference {
    case auto
    case imessage
    case sms
    case rcs

    var appleScriptValue: String {
        switch self {
        case .auto: return "auto"
        case .imessage: return "iMessage"
        case .sms: return "SMS"
        case .rcs: return "RCS"
        }
    }

    static func parse(_ raw: String?) -> DeliveryServicePreference? {
        guard let raw else { return .auto }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "auto", "any": return .auto
        case "imessage", "i-message", "i message": return .imessage
        case "sms": return .sms
        case "rcs": return .rcs
        default: return nil
        }
    }
}

private struct GenericErrorResponse: Codable {
    let ok: Bool
    let error: String
}

private struct AccountsResponse: Codable {
    let ok: Bool
    let count: Int
    let accounts: [MessageAccount]
    let error: String?
}

private struct MessageAccount: Codable {
    let id: String
    let description: String
    let service: String
    let enabled: Bool
    let connectionStatus: String
}

private struct ChatsResponse: Codable {
    let ok: Bool
    let count: Int
    let chats: [MessageChat]
    let error: String?
}

private struct MessageChat: Codable {
    let chatId: String
    let name: String
    let service: String
    let participants: [MessageParticipant]
}

private struct MessageParticipant: Codable {
    let handle: String
    let name: String
}

private struct SendResponse: Codable {
    let ok: Bool
    let recipient: String?
    let chatId: String?
    let service: String?
    let sentText: Bool
    let sentFile: Bool
    let destinationType: String?
    let error: String?
}
