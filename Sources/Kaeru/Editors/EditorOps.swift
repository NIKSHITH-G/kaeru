import AppKit

/// Tools that need a moment of user input first: trim, crop and merge.
/// They run as "instant" operations so the editor window appears before any progress HUD,
/// then hand the actual encoding to the JobCenter.
enum EditorOps {
    static func trimOp(isVideo: Bool) -> FileOperation {
        FileOperation(id: isVideo ? "video.trim" : "audio.trim", title: "Trim", symbol: "timeline.selection",
                      isInstant: true) { urls, progress in
            let url = urls[0]
            guard let range = try await trimRange(url) else { return OpResult() }
            let job = FileOperation.perFile("trim.job", "Trim", "timeline.selection") { url, progress in
                let recipe = MediaOps.sameFormatRecipe(for: url, isVideo: isVideo)
                let out = Output.file(for: url, ext: recipe.ext, suffix: "trimmed")
                let cut = ["-ss", String(format: "%.3f", range.lowerBound), "-to", String(format: "%.3f", range.upperBound)]
                try await MediaOps.ffmpeg(url, out, attempts: recipe.attempts.map { cut + $0 },
                                          duration: range.upperBound - range.lowerBound, progress: progress)
                return [out]
            }
            return try await handOff(job, url, progress)
        }
    }

    static let cropImageOp = FileOperation(id: "image.crop", title: "Crop", symbol: "crop", isInstant: true) { urls, progress in
        let url = urls[0]
        let (image, metadata) = try ImageOps.load(url)
        guard let rect = await cropRect(for: image, url) else { return OpResult() }
        let job = FileOperation.perFile("crop.job", "Crop", "crop") { url, _ in
            guard let cropped = image.cropping(to: rect) else { throw fail("Couldn't crop \(url.lastPathComponent)") }
            let out = Output.file(for: url, ext: ImageOps.writableExt(url), suffix: "cropped")
            try await ImageOps.write(cropped, to: out, quality: 0.92, metadata: metadata)
            return [out]
        }
        return try await handOff(job, url, progress)
    }

    static let cropVideoOp = FileOperation(id: "video.crop", title: "Crop", symbol: "crop", isInstant: true) { urls, progress in
        let url = urls[0]
        let frameURL = Output.temp(ext: "jpg")
        defer { try? FileManager.default.removeItem(at: frameURL) }
        try await MediaOps.ffmpeg(url, frameURL, attempts: [["-vf", "thumbnail", "-frames:v", "1", "-q:v", "2"]]) { _ in }
        let (frame, _) = try ImageOps.load(frameURL)
        guard let rect = await cropRect(for: frame, url) else { return OpResult() }
        // H.264 needs even dimensions.
        let w = Int(rect.width) / 2 * 2, h = Int(rect.height) / 2 * 2
        let crop = "crop=\(w):\(h):\(Int(rect.minX)):\(Int(rect.minY))"
        let job = FileOperation.perFile("crop.job", "Crop", "crop") { url, progress in
            let out = Output.file(for: url, ext: "mp4", suffix: "cropped")
            try await MediaOps.ffmpeg(url, out, attempts: [
                ["-vf", crop] + MediaOps.hwH264 + MediaOps.aac + ["-sn", "-movflags", "+faststart"],
                ["-vf", crop] + MediaOps.swH264 + MediaOps.aac + ["-sn", "-movflags", "+faststart"],
            ], progress: progress)
            return [out]
        }
        return try await handOff(job, url, progress)
    }

    /// Joins clips end to end. Videos are scaled and padded to the first clip's size; silent
    /// clips get a silent track so every segment has audio.
    static func mergeOp(isVideo: Bool) -> FileOperation {
        FileOperation(id: isVideo ? "video.merge" : "audio.merge", title: "Merge", symbol: "arrow.triangle.merge") { urls, progress in
            var inputs: [String] = urls.flatMap { ["-i", $0.path] }
            var filter = "", segments = ""
            var total = 0.0
            let audioFormat = "aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo"
            let out: URL
            var codec: [String]

            if isVideo {
                guard let size = await MediaOps.probe(urls[0]).size else { throw fail("\(urls[0].lastPathComponent) has no video") }
                let w = Int(size.width) / 2 * 2, h = Int(size.height) / 2 * 2
                var extra = urls.count
                for (i, url) in urls.enumerated() {
                    let info = await MediaOps.probe(url)
                    let length = await MediaOps.duration(of: url) ?? 0
                    total += length
                    filter += "[\(i):v]scale=\(w):\(h):force_original_aspect_ratio=decrease,pad=\(w):\(h):(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p[v\(i)];"
                    if info.hasAudio {
                        filter += "[\(i):a]\(audioFormat)[a\(i)];"
                    } else {
                        inputs += ["-f", "lavfi", "-t", String(format: "%.3f", length), "-i", "anullsrc=r=48000:cl=stereo"]
                        filter += "[\(extra):a]\(audioFormat)[a\(i)];"
                        extra += 1
                    }
                    segments += "[v\(i)][a\(i)]"
                }
                filter += "\(segments)concat=n=\(urls.count):v=1:a=1[v][a]"
                codec = ["-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-crf", "20", "-preset", "medium",
                         "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
                out = Output.file(named: "Merged.mp4", near: urls[0])
            } else {
                for (i, url) in urls.enumerated() {
                    total += await MediaOps.duration(of: url) ?? 0
                    filter += "[\(i):a]\(audioFormat)[a\(i)];"
                    segments += "[a\(i)]"
                }
                filter += "\(segments)concat=n=\(urls.count):v=0:a=1[a]"
                let recipe = MediaOps.sameFormatRecipe(for: urls[0], isVideo: false)
                codec = ["-map", "[a]"] + recipe.attempts[0]
                out = Output.file(named: "Merged.\(recipe.ext)", near: urls[0])
            }
            try await MediaOps.run(inputs + ["-filter_complex", filter] + codec, output: out, total: total, progress: progress)
            return OpResult(outputs: [out], message: "\(urls.count) clips merged")
        }
    }

    // MARK: Helpers

    /// KAERU_TRIM="start-end" and KAERU_CROP="x,y,w,h" stand in for the editor windows in headless tests.
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static func trimRange(_ url: URL) async throws -> ClosedRange<Double>? {
        if let spec = environment["KAERU_TRIM"] {
            let parts = spec.split(separator: "-").compactMap { Double($0) }
            return parts.count == 2 ? parts[0]...parts[1] : nil
        }
        return try await TrimWindow.ask(url)
    }

    private static func cropRect(for image: CGImage, _ url: URL) async -> CGRect? {
        if let spec = environment["KAERU_CROP"] {
            let v = spec.split(separator: ",").compactMap { Double($0) }
            return v.count == 4 ? CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) : nil
        }
        return await CropWindow.ask(image: image, title: url.lastPathComponent)
    }

    /// In the app the encode becomes a background job with the usual HUD; headless runs wait for it.
    private static func handOff(_ job: FileOperation, _ url: URL, _ progress: @escaping ProgressHandler) async throws -> OpResult {
        if environment["KAERU_TRIM"] != nil || environment["KAERU_CROP"] != nil {
            return try await job.run([url], progress)
        }
        await MainActor.run { JobCenter.shared.run(job, on: [url]) }
        return OpResult()
    }
}
