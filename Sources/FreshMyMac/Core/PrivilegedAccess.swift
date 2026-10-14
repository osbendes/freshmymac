import Foundation

/// Root yetkisiyle çalışan, argümanları sabit tek bir komut.
struct PrivilegedCommand: Sendable, Hashable {
    let path: String
    let arguments: [String]
    /// Başarısız olsa da görevi başarısız saymaz (ör. boş ARP tablosunda `arp -d`).
    var ignoresFailure = false

    /// sudoers kuralında yazıldığı biçim; sudo argümanları birebir eşleştirir.
    var sudoersSpec: String { ([path] + arguments).joined(separator: " ") }

    var shellLine: String {
        let line = ([path] + arguments).map(Shell.quote).joined(separator: " ")
        return ignoresFailure ? "\(line) >/dev/null 2>&1; true" : line
    }
}

/// Yönetici komutlarını her seferinde şifre sormadan çalıştırmak için tek seferlik izin.
///
/// İzin, `/etc/sudoers.d/freshmymac` dosyasına yalnızca `TaskCatalog`'daki komutlara (tam argümanlarıyla)
/// şifresiz izin veren bir kural yazar. Başka hiçbir komut şifresiz çalışmaz. Kural kurulmadan önce
/// `visudo` ile doğrulanır; Ayarlar'dan kaldırılabilir.
enum PrivilegedAccess {
    static let sudoersPath = "/etc/sudoers.d/freshmymac"

    /// Son kontrolün sonucu. Motor ve görevler bunu okur; `refresh()` günceller.
    nonisolated(unsafe) private(set) static var isGranted = false

    /// Katalogdaki tüm yetkili komutlar.
    static var commands: [PrivilegedCommand] {
        var seen = Set<PrivilegedCommand>()
        return TaskCatalog.all.flatMap { task -> [PrivilegedCommand] in
            if case let .privileged(commands) = task.action { return commands }
            return []
        }
        .filter { seen.insert($0).inserted }
    }

    /// Tüm komutlar şifresiz çalışabiliyor mu? `sudo -n -l` şifre sormadan yalnızca kontrol eder.
    @discardableResult
    static func refresh() async -> Bool {
        var granted = !commands.isEmpty
        for command in commands {
            let line = (["/usr/bin/sudo", "-n", "-l"] + [command.path] + command.arguments).map(Shell.quote).joined(separator: " ")
            if await Shell.run(line).status != 0 {
                granted = false
                break
            }
        }
        isGranted = granted
        return granted
    }

    /// Yönetici şifresini bir kez sorup kuralı kurar.
    static func install() async -> CleanupResult {
        let user = NSUserName()
        guard user.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            return failure(L("Kullanıcı adı desteklenmiyor.", "This user name is not supported."))
        }
        let rule = """
        # FreshMyMac: önbellek temizliği için şifresiz izin / passwordless cache cleanup.
        # Yalnızca aşağıdaki komutlar, bu argümanlarla. Kaldırmak için: FreshMyMac › Ayarlar › İzinler.
        \(user) ALL=(root) NOPASSWD: \(commands.map(\.sudoersSpec).joined(separator: ", "))

        """
        let temp = FileManager.default.temporaryDirectory.appending(path: "freshmymac-sudoers-\(UUID().uuidString)")
        do {
            try rule.write(to: temp, atomically: true, encoding: .utf8)
        } catch {
            return failure(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        let tempPath = Shell.quote(temp.path(percentEncoded: false))
        // Doğrulamadan geçmeyen kural asla kurulmaz (bozuk bir sudoers dosyası sudo'yu kilitler).
        let script = "/usr/sbin/visudo -cf \(tempPath) && /usr/bin/install -m 0440 -o root -g wheel \(tempPath) \(Shell.quote(sudoersPath))"
        let result = CleanupEngine.result(from: await Shell.runAsAdmin(script))
        guard result.succeeded else { return result }
        return await refresh() ? result : failure(L("Kural kuruldu ama etkinleşmedi.", "The rule was installed but is not active."))
    }

    static func uninstall() async -> CleanupResult {
        let result = CleanupEngine.result(from: await Shell.runAsAdmin("/bin/rm -f \(Shell.quote(sudoersPath))"))
        await refresh()
        return result
    }

    /// İzin varsa şifresiz, yoksa tek bir şifre istemiyle çalıştırır.
    static func run(_ commands: [PrivilegedCommand]) async -> CleanupResult {
        guard !commands.isEmpty else { return CleanupResult() }
        if isGranted {
            for command in commands {
                let output = await Shell.run("/usr/bin/sudo -n " + ([command.path] + command.arguments).map(Shell.quote).joined(separator: " "))
                if output.status != 0 && !command.ignoresFailure {
                    return CleanupEngine.result(from: output)
                }
            }
            return CleanupResult()
        }
        return CleanupEngine.result(from: await Shell.runAsAdmin(commands.map(\.shellLine).joined(separator: "; ")))
    }

    private static func failure(_ message: String) -> CleanupResult {
        var result = CleanupResult()
        result.succeeded = false
        result.message = message
        return result
    }
}
