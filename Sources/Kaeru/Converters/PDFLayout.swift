import PDFKit

/// Rebuilds a page's rows from where each character sits. Spreadsheets printed to PDF store their
/// text one column at a time, so the PDF's own order runs down each column instead of across each
/// row; reading by position puts every row back together.
enum PDFLayout {
    private struct Glyph { let text: String; let rect: CGRect; let spaceBefore: Bool }
    private struct Cell { var text: String; let minX: CGFloat }

    /// The page as a grid of cells when it is mostly a table, otherwise nil.
    static func table(_ page: PDFPage) -> [[String]]? {
        guard looksTabular(page) else { return nil }
        let lines = rows(page)
        let tabular = lines.filter { $0.count >= 3 }
        guard lines.count >= 6, Double(tabular.count) >= Double(lines.count) * 0.6 else { return nil }

        // Column edges are the left sides that many rows share.
        var edges: [(x: CGFloat, hits: Int)] = []
        for x in tabular.flatMap({ $0.map(\.minX) }).sorted() {
            if let last = edges.last, x - last.x < 6 { edges[edges.count - 1].hits += 1 } else { edges.append((x, 1)) }
        }
        // Header cells count too, so columns that are mostly empty (a "Status" to fill in) survive.
        let header = lines.first { $0.count >= 3 }?.map(\.minX) ?? []
        let columns = edges.filter { edge in
            Double(edge.hits) >= Double(tabular.count) * 0.3 || header.contains { abs($0 - edge.x) < 6 }
        }.map(\.x)
        guard columns.count >= 2 else { return nil }

        var grid = lines.map { line in
            var row = Array(repeating: "", count: columns.count)
            for cell in line {
                let col = max(0, (columns.lastIndex { $0 <= cell.minX + 3 }) ?? 0)
                row[col] = row[col].isEmpty ? cell.text : row[col] + " " + cell.text
            }
            return row
        }
        return tidy(&grid)
    }

    /// Centred headers start right of their column's data, leaving header-only half columns.
    /// Folds each into its left neighbour, except trailing empty columns ("Status" to fill in).
    private static func tidy(_ grid: inout [[String]]) -> [[String]] {
        guard grid.count > 1 else { return grid }
        func headerOnly(_ c: Int) -> Bool { grid.dropFirst().allSatisfy { $0[c].isEmpty } }
        var c = grid[0].count - 1
        while c > 0 && headerOnly(c) { c -= 1 }  // the trailing empty columns stay as they are
        while c > 0 {
            if headerOnly(c) {
                let left = grid[0][c - 1]
                grid[0][c - 1] = left.isEmpty ? grid[0][c] : left + " " + grid[0][c]
                for r in grid.indices { grid[r].remove(at: c) }
            }
            c -= 1
        }
        return grid
    }

    /// A quick check with PDFKit's own line pieces: a table page has many lines made of several
    /// separate pieces side by side. Running text is one piece per line.
    private static func looksTabular(_ page: PDFPage) -> Bool {
        guard let all = page.selection(for: page.bounds(for: .mediaBox)) else { return false }
        let pieces = all.selectionsByLine().map { $0.bounds(for: page) }.sorted { $0.midY > $1.midY }
        var counts: [Int] = []
        var band: CGRect?
        for r in pieces {
            if let b = band, r.midY >= b.minY, r.midY <= b.maxY { counts[counts.count - 1] += 1 }
            else { counts.append(1); band = r }
        }
        return counts.count >= 6 && Double(counts.filter { $0 >= 3 }.count) >= Double(counts.count) * 0.6
    }

    /// Lines top to bottom, each split into cells wherever the gap is wider than a few spaces.
    private static func rows(_ page: PDFPage) -> [[Cell]] {
        guard let string = page.string else { return [] }
        let ns = string as NSString
        var glyphs: [Glyph] = []
        var afterSpace = false
        for i in 0..<ns.length {
            let c = ns.substring(with: NSRange(location: i, length: 1))
            guard !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { afterSpace = true; continue }
            defer { afterSpace = false }
            // characterBounds(at:) drifts out of step in some PDFs; a one-character selection doesn't.
            guard let r = page.selection(for: NSRange(location: i, length: 1))?.bounds(for: page) else { continue }
            if r.width > 0, r.height > 0 { glyphs.append(Glyph(text: c, rect: r, spaceBefore: afterSpace)) }
        }
        glyphs.sort { $0.rect.midY > $1.rect.midY }  // PDF y grows upwards, so top first

        var lines: [[Glyph]] = []
        for g in glyphs {
            // A glyph belongs to the line whose letters span its middle; commas and dots sit low.
            if let first = lines.last?.first, g.rect.midY >= first.rect.minY, g.rect.midY <= first.rect.maxY {
                lines[lines.count - 1].append(g)
            } else {
                lines.append([g])
            }
        }
        return lines.map { line in
            let sorted = line.sorted { $0.rect.minX < $1.rect.minX }
            let height = sorted.map(\.rect.height).sorted()[sorted.count / 2]
            var cells: [Cell] = []
            var previous: CGRect?
            for g in sorted {
                let gap = previous.map { g.rect.minX - $0.maxX } ?? .infinity
                if gap > height * 0.9 {
                    cells.append(Cell(text: g.text, minX: g.rect.minX))
                } else {
                    // The PDF's own spaces mark word breaks; narrow fonts leave almost no visible gap.
                    cells[cells.count - 1].text += (g.spaceBefore || gap > height * 0.25 ? " " : "") + g.text
                }
                previous = g.rect
            }
            return cells
        }
    }
}
