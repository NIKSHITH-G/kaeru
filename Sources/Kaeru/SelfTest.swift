import Foundation

/// Unit checks for the pure logic, run with `Kaeru --self-test`. A test runner of our own because
/// XCTest and Swift Testing aren't available with the Command Line Tools alone.
enum SelfTest {
    private static var failures = 0
    private static var count = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String, file: String = #fileID, line: Int = #line) {
        count += 1
        if !condition() {
            failures += 1
            print("✗ \(name)  (\(file):\(line))")
        }
    }

    /// Returns the process exit code.
    @MainActor
    static func run() -> Int32 {
        csv()
        xlsxColumns()
        json()
        markdown()
        subtitles()
        versions()
        kinds()
        registry()
        shelf()
        print(failures == 0 ? "✓ \(count) checks passed" : "\(failures) of \(count) checks failed")
        return failures == 0 ? 0 : 1
    }

    private static func csv() {
        let rows = DataOps.parseDelimited("a,b\n\"x, y\",\"say \"\"hi\"\"\"\n1,\n", separator: ",")
        expect(rows == [["a", "b"], ["x, y", "say \"hi\""], ["1", ""]], "CSV parses quotes, escaped quotes and empty cells")
        expect(DataOps.delimited([["a,b", "c"]], separator: ",") == "\"a,b\",c\n", "CSV quotes fields containing the separator")
        expect(DataOps.sniffSeparator("a;b;c\n1;2;3") == ";", "Separator sniffing picks semicolons")
        let multiline = DataOps.parseDelimited("\"line1\nline2\",x\n", separator: ",")
        expect(multiline == [["line1\nline2", "x"]], "CSV keeps newlines inside quotes")
    }

    private static func xlsxColumns() {
        expect(XLSX.column(0) == "A" && XLSX.column(25) == "Z" && XLSX.column(26) == "AA" && XLSX.column(701) == "ZZ",
               "Column letters")
        expect(XLSX.columnIndex("AB12") == 27, "Column index from cell reference")
        expect(XLSX.isNumber("3.5") && XLSX.isNumber("-12") && !XLSX.isNumber("007") && !XLSX.isNumber("1e5"),
               "Only plain decimals become numbers")
    }

    private static func json() {
        let minified = DataOps.reformatJSON("{ \"b\": 1, \"a\": [1, 2, {\"s\": \"x, y\"}] }", pretty: false)
        expect(minified == "{\"b\":1,\"a\":[1,2,{\"s\":\"x, y\"}]}", "Minify keeps key order and string contents")
        let pretty = DataOps.reformatJSON("{\"a\":{},\"b\":[]}", pretty: true)
        expect(pretty == "{\n  \"a\": {},\n  \"b\": []\n}\n", "Pretty print keeps empty containers compact")
        let table = try? DataOps.jsonTable(Data("[{\"n\":\"Ada\",\"x\":1},{\"n\":\"Bo\",\"y\":null}]".utf8))
        expect(table == [["n", "x", "y"], ["Ada", "1", ""], ["Bo", "", ""]], "JSON objects become a table")
    }

    private static func markdown() {
        let html = Markdown.body("# Title\n\nSome **bold** and *italic* and `code`.\n\n- a\n- b\n\n| H | I |\n| - | - |\n| 1 | 2 |")
        expect(html.contains("<h1>Title</h1>"), "Markdown heading")
        expect(html.contains("<strong>bold</strong>") && html.contains("<em>italic</em>") && html.contains("<code>code</code>"),
               "Markdown inline styles")
        expect(html.contains("<ul><li>a</li><li>b</li></ul>"), "Markdown lists")
        expect(html.contains("<th>H</th>") && html.contains("<td>2</td>"), "Markdown tables")
        expect(Markdown.inline("a < b & c") == "a &lt; b &amp; c", "Markdown escapes HTML")
        expect(Markdown.body("---").contains("<hr />"), "Markdown output is XHTML-safe for EPUB")
    }

    private static func subtitles() {
        let cues = DataOps.parseSubtitles("1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:03.5 --> 00:04.000 align:start\nBye")
        expect(cues.count == 2 && cues[1].start == "00:00:03.500" && cues[1].end == "00:00:04.000", "Subtitle times normalise")
        expect(DataOps.formatSubtitles(cues, as: "srt").contains("00:00:01,000 --> 00:00:02,500"), "SRT uses commas")
        expect(DataOps.formatSubtitles(cues, as: "vtt").hasPrefix("WEBVTT"), "VTT header")
    }

    @MainActor
    private static func versions() {
        expect(Updater.isVersion("0.10.0", newerThan: "0.9.2"), "Versions compare numerically")
        expect(!Updater.isVersion("1.0", newerThan: "1.0.0"), "Missing components count as zero")
        let release = try? Updater.parse(Data("""
        {"tag_name":"v1.2.3","html_url":"https://github.com/x/y/releases/v1.2.3","body":"Notes",
         "assets":[{"name":"Kaeru.dmg","browser_download_url":"https://example.com/Kaeru.dmg"}]}
        """.utf8))
        expect(release?.version == "1.2.3" && release?.dmg.lastPathComponent == "Kaeru.dmg", "Release JSON parses")
    }

    private static func kinds() {
        let cases: [(String, FileKind)] = [("a.HEIC", .image), ("a.mov", .video), ("a.flac", .audio), ("a.pdf", .pdf),
                                           ("a.docx", .document), ("a.epub", .ebook), ("a.pptx", .presentation),
                                           ("a.xls", .spreadsheet), ("a.srt", .subtitle), ("a.7z", .archive)]
        for (name, kind) in cases {
            expect(FileKind.of(URL(fileURLWithPath: "/nonexistent/\(name)")) == kind, "\(name) is \(kind)")
        }
        expect(FileKind.normalizedExt("JPEG") == "jpg" && FileKind.normalizedExt("tif") == "tiff", "Extension aliases")
    }

    @MainActor
    private static func shelf() {
        let model = ShelfModel()
        let a = URL(fileURLWithPath: "/tmp/a.png"), b = URL(fileURLWithPath: "/tmp/b.png")
        model.add([a, b, a])
        expect(model.items.count == 2, "Shelf ignores duplicates")
        let made = model.stagingDirectory.appendingPathComponent("a.jpg")
        expect(model.contains(made) && model.contains(a), "Shelf owns its staging folder and the files on it")
        model.add([made])
        expect(model.items.last?.staged == true && model.items.first?.staged == false, "Results are marked as made on the shelf")
        model.click(model.items[0], extend: false)
        model.click(model.items[1], extend: true)
        expect(model.dragItems(startingAt: model.items[0]).count == 2, "Dragging a selected item carries the selection")
        expect(model.dragItems(startingAt: model.items[2]).count == 1, "Dragging an unselected item carries just it")
        let routed = Output.$overrideDirectory.withValue(model.stagingDirectory) { Output.directory(for: a) }
        expect(routed == model.stagingDirectory, "Jobs from a shelf write into its staging folder")
        expect(Output.directory(for: a) != model.stagingDirectory, "Other jobs are unaffected")
        model.discardStaging()
    }

    @MainActor
    private static func registry() {
        let png = [URL(fileURLWithPath: "/tmp/x.png")]
        let convert = Registry.operations(for: png, mode: .convert)
        expect(!convert.contains { $0.targetExt == "png" }, "No PNG → PNG conversion offered")
        expect(Set(convert.map(\.id)).count == convert.count, "Operation ids are unique")
        let mixed = [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.png")]
        expect(Registry.operations(for: mixed, mode: .tools).first?.id == "pdf.combine", "PDF + image offers Combine first")
        let videos = [URL(fileURLWithPath: "/tmp/a.mp4"), URL(fileURLWithPath: "/tmp/b.mov")]
        let tools = Registry.operations(for: videos, mode: .tools)
        expect(tools.first?.id == "video.merge" && !tools.contains { $0.id == "video.trim" }, "Multi-video offers Merge, not Trim")
        expect(Registry.operations(for: png, mode: .actions).count == FileActions.all.count, "Actions apply to everything")
    }
}
