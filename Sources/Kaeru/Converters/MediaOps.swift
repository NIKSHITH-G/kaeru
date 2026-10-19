import Foundation

/// Audio and video through ffmpeg. Each target lists argument sets to try in order,
/// so fast paths (stream copy, hardware encoders) fall back to software encoding.
enum MediaOps {
    typealias Recipe = (ext: String, title: String, attempts: [[String]])

    private static let evenSize = ["-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2"]
    static let hwH264 = ["-c:v", "h264_videotoolbox", "-q:v", "65", "-pix_fmt", "yuv420p", "-tag:v", "avc1"]
    static let swH264 = ["-c:v", "libx264", "-crf", "20", "-preset", "medium", "-pix_fmt", "yuv420p"]
    static let aac = ["-c:a", "aac", "-b:a", "192k"]

    static let audio: [Recipe] = [
        ("mp3", "MP3", [["-vn", "-c:a", "libmp3lame", "-q:a", "2"]]),
        ("m4a", "M4A", [["-vn", "-c:a", "aac_at", "-b:a", "256k"], ["-vn", "-c:a", "aac", "-b:a", "256k"]]),
        ("wav", "WAV", [["-vn", "-c:a", "pcm_s16le"]]),
        ("flac", "FLAC", [["-vn", "-c:a", "flac"]]),
        ("ogg", "OGG", [["-vn", "-c:a", "libopus", "-b:a", "160k"]]),
        ("opus", "Opus", [["-vn", "-c:a", "libopus", "-b:a", "128k"]]),
        ("aiff", "AIFF", [["-vn", "-c:a", "pcm_s16be"]]),
        ("wma", "WMA", [["-vn", "-c:a", "wmav2", "-b:a", "192k"]]),
    ]

    static let video: [Recipe] = [
        ("mp4", "MP4", [evenSize + hwH264 + aac + ["-sn", "-movflags", "+faststart"],
                        evenSize + swH264 + aac + ["-sn", "-movflags", "+faststart"]]),
        ("mov", "MOV", [evenSize + hwH264 + aac + ["-sn"], evenSize + swH264 + aac + ["-sn"]]),
        ("mkv", "MKV", [["-map", "0", "-c", "copy"], swH264 + aac]),
        ("webm", "WebM", [["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-deadline", "good",
                           "-cpu-used", "4", "-c:a", "libopus", "-b:a", "128k", "-sn"]]),
        ("avi", "AVI", [["-c:v", "mpeg4", "-q:v", "3", "-c:a", "libmp3lame", "-q:a", "3", "-sn"]]),
        ("wmv", "WMV", [["-c:v", "wmv2", "-b:v", "3M", "-c:a", "wmav2", "-b:a", "192k", "-sn"]]),
        ("gif", "GIF", [["-vf", "fps=12,scale='min(640,iw)':-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4",
                         "-loop", "0", "-an"]]),
    ]

    static func convertOps(isVideo: Bool) -> [FileOperation] {
        let recipes = isVideo ? video + audio.filter { ["mp3", "m4a", "wav"].contains($0.ext) } : audio
        return recipes.map { r in
            .perFile("media.\(r.ext)", r.title, isVideo && !["mp3", "m4a", "wav"].contains(r.ext) ? "film" : "waveform",
                     ext: r.ext) { url, progress in
                let out = Output.file(for: url, ext: r.ext)
                try await ffmpeg(url, out, attempts: r.attempts, progress: progress)
                return [out]
            }
        }
    }

    static func toolOps(isVideo: Bool) -> [FileOperation] {
        if isVideo {
            return [
                .shrinking("video.compress", "Compress", "arrow.down.right.and.arrow.up.left") { url, p in
                    let out = Output.file(for: url, ext: "mp4", suffix: "compressed")
                    try await ffmpeg(url, out, attempts: [evenSize + ["-c:v", "libx264", "-crf", "28", "-preset", "slow",
                        "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-sn", "-movflags", "+faststart"]], progress: p)
                    return [out]
                },
                videoTool("video.720p", "720p", "rectangle.arrowtriangle.2.inward", suffix: "720p",
                          ["-vf", "scale=-2:'min(720,ih)'"] + hwH264 + aac, fallback: ["-vf", "scale=-2:'min(720,ih)'"] + swH264 + aac),
                videoTool("video.mute", "Mute", "speaker.slash", suffix: "muted", sameExt: true,
                          ["-c:v", "copy", "-an"], fallback: swH264 + ["-an"]),
                videoTool("video.rotate", "Rotate Right", "rotate.right", suffix: "rotated",
                          ["-vf", "transpose=1"] + hwH264 + aac, fallback: ["-vf", "transpose=1"] + swH264 + aac),
                videoTool("video.speed", "2× Speed", "hare", suffix: "2x",
                          ["-vf", "setpts=0.5*PTS", "-af", "atempo=2.0"] + hwH264 + aac,
                          fallback: ["-vf", "setpts=0.5*PTS", "-af", "atempo=2.0"] + swH264 + aac),
                .perFile("video.snapshot", "Snapshot", "camera") { url, p in
                    let out = Output.file(for: url, ext: "jpg", suffix: "frame")
                    try await ffmpeg(url, out, attempts: [["-vf", "thumbnail", "-frames:v", "1", "-q:v", "2"]], progress: p)
                    return [out]
                },
            ]
        }
        return [
            .shrinking("audio.compress", "Compress", "arrow.down.right.and.arrow.up.left") { url, p in
                let out = Output.file(for: url, ext: "mp3", suffix: "compressed")
                try await ffmpeg(url, out, attempts: [["-vn", "-c:a", "libmp3lame", "-b:a", "128k"]], progress: p)
                return [out]
            },
            audioTool("audio.normalize", "Normalize", "dial.medium", suffix: "normalized", ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]),
            audioTool("audio.mono", "Mono", "speaker.wave.1", suffix: "mono", ["-ac", "1"]),
            audioTool("audio.silence", "Cut Silence", "scissors", suffix: "trimmed",
                      ["-af", "silenceremove=start_periods=1:start_threshold=-50dB:stop_periods=-1:stop_threshold=-50dB:stop_duration=1"]),
        ]
    }

    private static func videoTool(_ id: String, _ title: String, _ symbol: String, suffix: String, sameExt: Bool = false,
                                  _ args: [String], fallback: [String]) -> FileOperation {
        .perFile(id, title, symbol) { url, progress in
            let ext = sameExt ? url.pathExtension.lowercased() : "mp4"
            let out = Output.file(for: url, ext: ext, suffix: suffix)
            try await ffmpeg(url, out, attempts: [args, fallback], progress: progress)
            return [out]
        }
    }

    /// Re-encodes audio in its own format when we know how, otherwise as M4A.
    private static func audioTool(_ id: String, _ title: String, _ symbol: String, suffix: String, _ args: [String]) -> FileOperation {
        .perFile(id, title, symbol) { url, progress in
            let ext = FileKind.normalizedExt(url.pathExtension)
            let recipe = audio.first { $0.ext == ext } ?? audio[1]
            let out = Output.file(for: url, ext: recipe.ext, suffix: suffix)
            try await ffmpeg(url, out, attempts: recipe.attempts.map { args + $0 }, progress: progress)
            return [out]
        }
    }

    static func duration(of url: URL) async -> Double? {
        guard let probe = try? Tools.ffprobe(),
              let out = try? await Shell.run(probe, ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", url.path])
        else { return nil }
        return Double(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Converts one input, trying each argument set in turn. `duration` overrides the probed length
    /// for progress (e.g. when trimming).
    static func ffmpeg(_ input: URL, _ output: URL, attempts: [[String]], duration: Double? = nil,
                       progress: @escaping ProgressHandler) async throws {
        let total: Double?
        if let duration { total = duration } else { total = await self.duration(of: input) }
        var lastError: Error = fail("Nothing to do")
        for args in attempts {
            do {
                try await run(["-i", input.path] + args, output: output, total: total, progress: progress)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Runs ffmpeg with arbitrary inputs and arguments, reporting progress against `total` seconds.
    static func run(_ args: [String], output: URL, total: Double?, progress: @escaping ProgressHandler) async throws {
        let bin = try Tools.ffmpeg()
        let full = ["-hide_banner", "-nostdin", "-y", "-loglevel", "error", "-progress", "pipe:1", "-nostats"]
            + args + [output.path]
        do {
            try await Shell.run(bin, full) { line in
                guard let total, total > 0 else { return }
                for key in ["out_time_us=", "out_time_ms="] where line.hasPrefix(key) {
                    if let us = Double(line.dropFirst(key.count)) { progress(min(0.99, us / 1_000_000 / total)) }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    /// Whether the file has an audio stream, and its first video stream's size.
    static func probe(_ url: URL) async -> (hasAudio: Bool, size: CGSize?) {
        guard let ffprobe = try? Tools.ffprobe(),
              let out = try? await Shell.run(ffprobe, ["-v", "error", "-show_entries", "stream=codec_type,width,height",
                                                       "-of", "csv=p=0", url.path]) else { return (false, nil) }
        var hasAudio = false, size: CGSize?
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: ",").map(String.init)
            if parts.first == "audio" { hasAudio = true }
            if parts.first == "video", size == nil, parts.count >= 3, let w = Double(parts[1]), let h = Double(parts[2]) {
                size = CGSize(width: w, height: h)
            }
        }
        return (hasAudio, size)
    }

    /// The recipe used to re-encode into the file's own format (falls back to MP4 / M4A).
    static func sameFormatRecipe(for url: URL, isVideo: Bool) -> Recipe {
        let ext = FileKind.normalizedExt(url.pathExtension)
        if isVideo {
            let recipe = video.first { $0.ext == ext && $0.ext != "gif" } ?? video[0]
            // Stream copy can't cut or filter precisely, so drop copy-only attempts.
            return (recipe.ext, recipe.title, recipe.attempts.filter { !$0.contains("copy") })
        }
        return audio.first { $0.ext == ext } ?? audio[1]
    }
}
