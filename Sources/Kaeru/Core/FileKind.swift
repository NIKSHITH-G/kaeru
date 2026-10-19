import Foundation
import UniformTypeIdentifiers

enum FileKind: Hashable {
    case image, svg, audio, video, pdf, document, ebook, pages, presentation, spreadsheet, json, plist, subtitle,
         archive, folder, other

    private static let table: [(FileKind, Set<String>)] = [
        (.image, ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "gif", "webp", "avif", "jp2", "ico",
                  "icns", "tga", "psd", "exr", "jxl", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "pef", "srw"]),
        (.svg, ["svg"]),
        (.audio, ["mp3", "m4a", "wav", "flac", "ogg", "oga", "opus", "aiff", "aif", "wma", "aac", "caf", "amr", "alac"]),
        (.video, ["mp4", "mov", "mkv", "webm", "avi", "wmv", "m4v", "flv", "mpg", "mpeg", "3gp", "ts", "mts", "m2ts", "ogv"]),
        (.pdf, ["pdf"]),
        (.document, ["docx", "doc", "odt", "rtf", "rtfd", "html", "htm", "txt", "text", "md", "markdown", "webarchive"]),
        (.ebook, ["epub"]),
        (.pages, ["pages"]),
        (.presentation, ["pptx", "ppt", "key"]),
        (.spreadsheet, ["csv", "tsv", "xlsx", "xls", "ods"]),
        (.json, ["json"]),
        (.plist, ["plist"]),
        (.subtitle, ["srt", "vtt"]),
        (.archive, ["zip", "tar", "gz", "tgz", "bz2", "tbz", "xz", "txz", "rar", "7z"]),
    ]

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            switch ext {
            case "rtfd": return .document
            case "pages": return .pages
            case "key": return .presentation
            default: return .folder
            }
        }
        if let match = table.first(where: { $0.1.contains(ext) }) { return match.0 }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .text) { return .document }
        return .other
    }

    /// Collapses spelling variants so "jpeg" and "jpg" count as the same format.
    static func normalizedExt(_ ext: String) -> String {
        let e = ext.lowercased()
        let aliases = ["jpeg": "jpg", "tif": "tiff", "htm": "html", "markdown": "md", "aif": "aiff",
                       "heif": "heic", "text": "txt", "oga": "ogg", "tgz": "gz"]
        return aliases[e] ?? e
    }
}
