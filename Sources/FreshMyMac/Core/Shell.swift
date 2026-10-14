import Foundation

enum Shell {
    struct Output: Sendable {
        let status: Int32
        let output: String
    }

    /// GUI uygulamaları kabuk PATH'ini devralmaz; Homebrew yollarını ekliyoruz.
    private static let path = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Bir değeri kabuk komutunda güvenle kullanmak için tek tırnakla sarar.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func which(_ tool: String) -> String? {
        path.split(separator: ":")
            .map { "\($0)/\(tool)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ command: String) async -> Output {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(filePath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.environment = ProcessInfo.processInfo.environment.merging(["PATH": path]) { _, new in new }
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Output(status: -1, output: error.localizedDescription))
                return
            }
            // Çıktıyı süreç çalışırken oku; aksi halde dolan pipe tamponu süreci kilitler.
            DispatchQueue.global(qos: .userInitiated).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                continuation.resume(returning: Output(status: process.terminationStatus, output: text))
            }
        }
    }

    /// Komutları macOS'un standart yönetici şifresi penceresiyle çalıştırır.
    /// Birden fazla komut tek seferde verilirse şifre bir kez sorulur.
    static func runAsAdmin(_ command: String) async -> Output {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let quoted = script.replacingOccurrences(of: "'", with: "'\\''")
        return await run("/usr/bin/osascript -e '\(quoted)'")
    }
}
