import Foundation

/// Decides which operations appear on each wheel for a given selection of files.
enum Registry {
    static func operations(for urls: [URL], mode: WheelMode) -> [FileOperation] {
        guard !urls.isEmpty else { return [] }
        if mode == .actions { return FileActions.all }

        // With several files, only offer what applies to every one of them.
        let perFile = urls.map { operations(for: $0, mode: mode) }
        var result = perFile[0].filter { op in perFile.dropFirst().allSatisfy { list in list.contains { $0.id == op.id } } }

        if mode == .convert && result.isEmpty { result = [ArchiveOps.zipOp, ArchiveOps.tarOp] }
        if mode == .tools && urls.count > 1 {
            let kinds = Set(urls.map(FileKind.of))
            if kinds.isSubset(of: [.pdf, .image]) { result.insert(PDFOps.combineOp, at: 0) }
            if kinds == [.audio] { result.insert(EditorOps.mergeOp(isVideo: false), at: 0) }
            if kinds == [.video] { result.insert(EditorOps.mergeOp(isVideo: true), at: 0) }
            // Editors work on one file at a time.
            result.removeAll { $0.id.hasSuffix(".trim") || $0.id.hasSuffix(".crop") }
        }
        return result
    }

    private static func operations(for url: URL, mode: WheelMode) -> [FileOperation] {
        let kind = FileKind.of(url)
        let ext = FileKind.normalizedExt(url.pathExtension)
        let list: [FileOperation]
        switch mode {
        case .convert:
            switch kind {
            case .image: list = ImageOps.convertOps(svg: false)
            case .svg: list = ImageOps.convertOps(svg: true)
            case .audio: list = MediaOps.convertOps(isVideo: false)
            case .video: list = MediaOps.convertOps(isVideo: true)
            case .pdf: list = PDFOps.convertOps()
            case .document, .ebook: list = DocumentOps.convertOps()
            case .pages: list = PagesOps.convertOps()
            case .presentation: list = PresentationOps.convertOps()
            case .spreadsheet: list = DataOps.tableConvertOps()
            case .json: list = DataOps.jsonConvertOps()
            case .plist: list = DataOps.plistConvertOps()
            case .subtitle: list = DataOps.subtitleConvertOps()
            case .archive: list = [ArchiveOps.extractOp, ArchiveOps.zipOp]
            case .folder, .other: list = [ArchiveOps.zipOp, ArchiveOps.tarOp]
            }
        case .tools:
            switch kind {
            case .image: list = [EditorOps.cropImageOp] + ImageOps.toolOps()
            case .svg: list = ImageOps.toolOps()
            case .audio: list = [EditorOps.trimOp(isVideo: false)] + MediaOps.toolOps(isVideo: false)
            case .video: list = [EditorOps.trimOp(isVideo: true), EditorOps.cropVideoOp] + MediaOps.toolOps(isVideo: true)
            case .pdf: list = PDFOps.toolOps()
            case .document, .ebook: list = DocumentOps.toolOps()
            case .json: list = DataOps.jsonToolOps()
            default: list = []
            }
        case .actions:
            list = FileActions.all
        }
        return list.filter { $0.targetExt == nil || $0.targetExt != ext }
    }

    /// Every operation id, for the CLI and tests.
    static func find(_ id: String, for urls: [URL]) -> FileOperation? {
        WheelMode.allCases.lazy.compactMap { mode in operations(for: urls, mode: mode).first { $0.id == id } }.first
    }
}
