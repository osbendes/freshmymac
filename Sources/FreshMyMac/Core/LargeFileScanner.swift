import Foundation

enum LargeFileScope: String, CaseIterable, Identifiable, Sendable {
    case downloads, desktop, documents, movies, music

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: L("İndirilenler", "Downloads")
        case .desktop: L("Masaüstü", "Desktop")
        case .documents: L("Belgeler", "Documents")
        case .movies: L("Filmler", "Movies")
        case .music: L("Müzik", "Music")
        }
    }

    var url: URL {
        let name = switch self {
        case .downloads: "Downloads"
        case .desktop: "Desktop"
        case .documents: "Documents"
        case .movies: "Movies"
        case .music: "Music"
        }
        return FileUtils.home.appending(path: name)
    }
}

enum LargeFileMode: String, CaseIterable, Identifiable, Sendable {
    case large, old
    var id: String { rawValue }

    var title: String {
        switch self {
        case .large: L("Büyük dosyalar", "Large files")
        case .old: L("Eski dosyalar", "Old files")
        }
    }
}

/// Büyük dosyalar ekranında gruplama için dosya türü.
enum FileKind: String, CaseIterable, Identifiable, Sendable {
    case video, archive, installer, image, audio, document, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: L("Videolar", "Videos")
        case .archive: L("Arşivler ve Disk Görüntüleri", "Archives & Disk Images")
        case .installer: L("Yükleyiciler ve Uygulamalar", "Installers & Apps")
        case .image: L("Görseller", "Images")
        case .audio: L("Ses", "Audio")
        case .document: L("Belgeler", "Documents")
        case .other: L("Diğer", "Other")
        }
    }

    var icon: String {
        switch self {
        case .video: "film"
        case .archive: "archivebox"
        case .installer: "shippingbox"
        case .image: "photo"
        case .audio: "music.note"
        case .document: "doc.richtext"
        case .other: "doc"
        }
    }

    private static let extensions: [FileKind: Set<String>] = [
        .video: ["mp4", "mov", "m4v", "mkv", "avi", "wmv", "webm", "mts", "m2ts", "braw", "r3d", "mxf"],
        .archive: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "dmg", "iso", "img", "sparseimage"],
        .installer: ["pkg", "mpkg", "app", "exe", "msi", "apk", "ipa", "xip"],
        .image: ["jpg", "jpeg", "png", "heic", "tif", "tiff", "psd", "psb", "raw", "cr2", "cr3", "nef", "arw", "dng", "gif", "webp"],
        .audio: ["mp3", "wav", "aif", "aiff", "flac", "m4a", "aac", "ogg"],
        .document: ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "key", "pages", "numbers", "indd", "ai"],
    ]

    init(url: URL) {
        let ext = url.pathExtension.lowercased()
        self = Self.extensions.first { $0.value.contains(ext) }?.key ?? .other
    }
}

struct LargeFileCriteria: Sendable {
    var scopes: Set<LargeFileScope>
    var mode: LargeFileMode
    var minSizeMB: Int
    var olderThanDays: Int
}

enum LargeFileScanner {
    static let resultLimit = 1000

    static func scan(_ criteria: LargeFileCriteria) -> [FoundFile] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .addedToDirectoryDateKey,
        ]
        let minSize = Int64(criteria.minSizeMB) * 1_000_000
        let cutoff = Date.now.addingTimeInterval(-Double(criteria.olderThanDays) * 86_400)
        var found: [FoundFile] = []

        for scope in criteria.scopes {
            let enumerator = FileManager.default.enumerator(
                at: scope.url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )
            while let url = enumerator?.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else { continue }
                let size = Int64(values.totalFileAllocatedSize ?? 0)
                // İndirilenler'de "eklenme tarihi", değiştirilme tarihinden daha anlamlıdır.
                let date = [values.contentModificationDate, values.addedToDirectoryDate].compactMap { $0 }.max()

                let matches = switch criteria.mode {
                case .large: size >= minSize
                case .old: size >= minSize && (date.map { $0 < cutoff } ?? false)
                }
                if matches { found.append(FoundFile(url: url, size: size, date: date)) }
            }
        }
        return Array(found.sorted { $0.size > $1.size }.prefix(resultLimit))
    }
}
