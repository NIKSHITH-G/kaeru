import AppKit
import Combine
import QuickLookThumbnailing

@MainActor
final class Job: ObservableObject, Identifiable {
    enum State {
        case running(Double?)
        case done(OpResult)
        case failed(String)
        case cancelled
    }

    let id: UUID
    let title: String
    let subtitle: String
    let started: Date
    @Published var state: State
    @Published var finished: Date?
    @Published var thumbnail: NSImage?
    fileprivate var task: Task<Void, Never>?

    init(title: String, subtitle: String) {
        id = UUID()
        self.title = title
        self.subtitle = subtitle
        started = Date()
        state = .running(nil)
    }

    fileprivate init(record: JobRecord) {
        id = record.id
        title = record.title
        subtitle = record.subtitle
        started = record.date
        finished = record.date
        state = record.error.map { .failed($0) }
            ?? .done(OpResult(outputs: record.outputs.map { URL(fileURLWithPath: $0) }, message: record.message))
    }

    var isRunning: Bool { if case .running = state { return true }; return false }
    var outputs: [URL] { if case .done(let r) = state { return r.outputs }; return [] }
    var existingOutputs: [URL] { outputs.filter { FileManager.default.fileExists(atPath: $0.path) } }

    func cancel() { task?.cancel() }

    func reveal() {
        if !existingOutputs.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(existingOutputs) }
    }

    func open() {
        if let first = existingOutputs.first { NSWorkspace.shared.open(first) }
    }

    fileprivate func loadThumbnail(of url: URL) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 72, height: 72),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            Task { @MainActor in self.thumbnail = image }
        }
    }

    fileprivate var record: JobRecord? {
        switch state {
        case .done(let r):
            return JobRecord(id: id, title: title, subtitle: subtitle, date: finished ?? started,
                             outputs: r.outputs.map(\.path), message: r.message, error: nil)
        case .failed(let message):
            return JobRecord(id: id, title: title, subtitle: subtitle, date: finished ?? started, outputs: [], message: nil, error: message)
        default: return nil
        }
    }
}

private struct JobRecord: Codable {
    let id: UUID
    let title: String
    let subtitle: String
    let date: Date
    let outputs: [String]
    let message: String?
    let error: String?
}

/// Runs operations in the background and keeps a history for the HUD and the History page.
@MainActor
final class JobCenter: ObservableObject {
    static let shared = JobCenter()
    private static let historyKey = "history"

    @Published private(set) var jobs: [Job] = []
    /// Fires when any job finishes; the onboarding tutorial listens for its first success.
    let finished = PassthroughSubject<Job, Never>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let records = try? JSONDecoder().decode([JobRecord].self, from: data) {
            jobs = records.map(Job.init(record:))
            jobs.forEach { job in job.existingOutputs.first.map(job.loadThumbnail) }
        }
    }

    func run(_ op: FileOperation, on urls: [URL]) {
        let names = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        let job = Job(title: op.title, subtitle: names)
        job.loadThumbnail(of: urls[0])
        jobs.insert(job, at: 0)
        if jobs.count > 100 { jobs.removeLast(jobs.count - 100) }
        HUD.shared.show()

        job.task = Task.detached(priority: .userInitiated) {
            let state: Job.State
            do {
                let result = try await op.run(urls) { p in
                    Task { @MainActor in if job.isRunning { job.state = .running(p) } }
                }
                state = .done(result)
            } catch is CancellationError {
                state = .cancelled
            } catch {
                state = Task.isCancelled ? .cancelled : .failed(error.localizedDescription)
            }
            await MainActor.run {
                job.state = state
                job.finished = Date()
                if case .cancelled = state {
                    // Don't leave half-written files behind or keep cancelled jobs in history.
                    self.jobs.removeAll { $0 === job }
                } else if let first = job.existingOutputs.first {
                    job.loadThumbnail(of: first)
                }
                self.save()
                self.finished.send(job)
                HUD.shared.scheduleHide()
            }
        }
    }

    func clearFinished() {
        jobs.removeAll { !$0.isRunning }
        save()
    }

    private func save() {
        let records = jobs.compactMap(\.record)
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: Self.historyKey) }
    }
}
