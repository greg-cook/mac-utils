import Foundation

// Asks Anthropic for the current usage, the way Claude Code's own /usage does. It signs in with the
// access token Claude Code keeps in the login keychain, so it works whether you use the terminal,
// the desktop app or neither. It never refreshes the token itself: Claude Code rotates refresh
// tokens, and using one here would sign Claude Code out. An expired token just fails the fetch until
// Claude Code next runs.
enum Fetcher {
    enum Failure: Error, CustomStringConvertible {
        case noToken, http(Int), badResponse, network(String)

        var description: String {
            switch self {
            case .noToken: "no Claude Code login in the keychain"
            case .http(401), .http(403): "token expired, open Claude Code to renew it"
            case .http(429): "rate limited"
            case .http(let code): "HTTP \(code)"
            case .badResponse: "unexpected response"
            case .network(let message): message
            }
        }
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async -> Result<Usage, Failure> {
        guard let token = await accessToken() else { return .failure(.noToken) }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-usage", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(.http(status)) }
            guard let usage = Usage.decodeEndpoint(data) else { return .failure(.badResponse) }
            return .success(usage)
        } catch {
            return .failure(.network((error as? URLError)?.localizedDescription ?? "network error"))
        }
    }

    // The keychain item belongs to Claude Code. It is read through /usr/bin/security rather than
    // the Security framework so that "Always Allow" attaches to that stable system tool. This app
    // is signed ad hoc, so macOS would treat every rebuild as a new app and ask again.
    private static func accessToken() async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = root["claudeAiOauth"] as? [String: Any] else { return nil }
            return oauth["accessToken"] as? String
        }.value
    }
}
