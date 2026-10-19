import Foundation
import ImageIO

/// Writes a PowerPoint deck with one full-bleed picture per slide (used for PDF → PPTX).
enum PPTX {
    private static let ns = """
    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
    xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
    """
    private static let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
    private static let emptyTree = """
    <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>\
    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
    """

    /// `slideSize` is in points; every image is stretched to fill its slide.
    static func write(images: [CGImage], slideSize: CGSize, to url: URL) async throws {
        guard !images.isEmpty else { throw fail("Nothing to put on slides") }
        let cx = Int(slideSize.width * 12700), cy = Int(slideSize.height * 12700)  // 1pt = 12700 EMU
        var files: [String: Data] = [:]
        func put(_ path: String, _ text: String) { files[path] = Data((xml + text).utf8) }

        var overrides = "", slideIds = "", presRels = ""
        for (i, image) in images.enumerated() {
            let n = i + 1
            files["ppt/media/image\(n).jpeg"] = try jpeg(image)
            put("ppt/slides/slide\(n).xml", """
            <p:sld \(ns)><p:cSld><p:spTree>\(emptyTree)\
            <p:pic><p:nvPicPr><p:cNvPr id="2" name="Page \(n)"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>\
            <p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>\
            <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>\
            </p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>
            """)
            put("ppt/slides/_rels/slide\(n).xml.rels", """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="\(rel)/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>\
            <Relationship Id="rId2" Type="\(rel)/image" Target="../media/image\(n).jpeg"/></Relationships>
            """)
            overrides += "<Override PartName=\"/ppt/slides/slide\(n).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>"
            slideIds += "<p:sldId id=\"\(255 + n)\" r:id=\"rId\(n + 2)\"/>"
            presRels += "<Relationship Id=\"rId\(n + 2)\" Type=\"\(rel)/slide\" Target=\"slides/slide\(n).xml\"/>"
        }

        put("[Content_Types].xml", """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/><Default Extension="jpeg" ContentType="image/jpeg"/>\
        <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>\
        <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>\
        <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>\
        <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>\(overrides)</Types>
        """)
        put("_rels/.rels", """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="\(rel)/officeDocument" Target="ppt/presentation.xml"/></Relationships>
        """)
        put("ppt/presentation.xml", """
        <p:presentation \(ns)><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>\
        <p:sldIdLst>\(slideIds)</p:sldIdLst><p:sldSz cx="\(cx)" cy="\(cy)"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>
        """)
        put("ppt/_rels/presentation.xml.rels", """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="\(rel)/slideMaster" Target="slideMasters/slideMaster1.xml"/>\
        <Relationship Id="rId2" Type="\(rel)/theme" Target="theme/theme1.xml"/>\(presRels)</Relationships>
        """)
        put("ppt/slideMasters/slideMaster1.xml", """
        <p:sldMaster \(ns)><p:cSld><p:spTree>\(emptyTree)</p:spTree></p:cSld>\
        <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>\
        <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>
        """)
        put("ppt/slideMasters/_rels/slideMaster1.xml.rels", """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="\(rel)/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>\
        <Relationship Id="rId2" Type="\(rel)/theme" Target="../theme/theme1.xml"/></Relationships>
        """)
        put("ppt/slideLayouts/slideLayout1.xml", """
        <p:sldLayout \(ns) type="blank" preserve="1"><p:cSld name="Blank"><p:spTree>\(emptyTree)</p:spTree></p:cSld>\
        <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>
        """)
        put("ppt/slideLayouts/_rels/slideLayout1.xml.rels", """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="\(rel)/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>
        """)
        put("ppt/theme/theme1.xml", theme)
        try await ZipPackage.write(files, to: url)
    }

    private static func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw fail("Couldn't encode slide image")
        }
        CGImageDestinationAddImage(dest, ImageOps.flatten(image), [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw fail("Couldn't encode slide image") }
        return data as Data
    }

    private static var theme: String {
        let colors = [("dk1", "000000"), ("lt1", "FFFFFF"), ("dk2", "1F2937"), ("lt2", "E5E7EB"), ("accent1", "4F46E5"),
                      ("accent2", "0EA5E9"), ("accent3", "10B981"), ("accent4", "F59E0B"), ("accent5", "EF4444"),
                      ("accent6", "8B5CF6"), ("hlink", "2563EB"), ("folHlink", "7C3AED")]
            .map { "<a:\($0.0)><a:srgbClr val=\"\($0.1)\"/></a:\($0.0)>" }.joined()
        let font = "<a:latin typeface=\"Calibri\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/>"
        let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
        let line = "<a:ln w=\"6350\">\(fill)</a:ln>"
        let effect = "<a:effectStyle><a:effectLst/></a:effectStyle>"
        return """
        <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Kaeru"><a:themeElements>\
        <a:clrScheme name="Kaeru">\(colors)</a:clrScheme>\
        <a:fontScheme name="Kaeru"><a:majorFont>\(font)</a:majorFont><a:minorFont>\(font)</a:minorFont></a:fontScheme>\
        <a:fmtScheme name="Kaeru"><a:fillStyleLst>\(fill)\(fill)\(fill)</a:fillStyleLst>\
        <a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst><a:effectStyleLst>\(effect)\(effect)\(effect)</a:effectStyleLst>\
        <a:bgFillStyleLst>\(fill)\(fill)\(fill)</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>
        """
    }
}
