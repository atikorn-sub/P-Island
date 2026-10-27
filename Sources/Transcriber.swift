import AppKit
import AVFoundation
import Speech
import UniformTypeIdentifiers

/// Turns speech in an audio or video file into a .txt file, using Apple's speech recognition.
/// Long files are cut into short pieces, because server-side recognition stops after about a minute.
enum Transcriber {
    static var languages: [(name: String, id: String)] { [(tr("ภาษาไทย", "Thai"), "th-TH"), ("English", "en-US")] }

    static func canTranscribe(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audio) || type.conforms(to: .movie)
    }

    /// Completion gets the transcript file, or a message explaining what went wrong.
    static func transcribe(_ source: URL, language: String, completion: @escaping (Result<URL, TranscriptionError>) -> Void) {
        authorize { granted in
            guard granted else { return completion(.failure(.init(tr("ต้องอนุญาต Speech Recognition ก่อน", "Allow Speech Recognition first")))) }
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else {
                return completion(.failure(.init(tr("ยังถอดเสียงภาษานี้ไม่ได้ตอนนี้", "This language can't be transcribed right now"))))
            }
            let asset = AVURLAsset(url: source)
            Task {
                let duration = (try? await asset.load(.duration).seconds) ?? 0
                guard duration > 0 else { return completion(.failure(.init(tr("อ่านไฟล์เสียงไม่ได้", "Couldn't read the audio")))) }
                let job = Job(asset: asset, duration: duration, recognizer: recognizer, source: source, completion: completion)
                await MainActor.run { job.next() }
            }
        }
    }

    struct TranscriptionError: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private static func authorize(_ done: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: done(true)
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { done(status == .authorized) }
            }
        default: done(false)
        }
    }

    /// Works through the file one 50-second piece at a time.
    private final class Job {
        static let pieceLength: Double = 50

        let asset: AVURLAsset
        let duration: Double
        let recognizer: SFSpeechRecognizer
        let source: URL
        let completion: (Result<URL, TranscriptionError>) -> Void
        var start: Double = 0
        var parts: [String] = []
        var keepAlive: Job?

        init(asset: AVURLAsset, duration: Double, recognizer: SFSpeechRecognizer, source: URL,
             completion: @escaping (Result<URL, TranscriptionError>) -> Void) {
            self.asset = asset
            self.duration = duration
            self.recognizer = recognizer
            self.source = source
            self.completion = completion
            keepAlive = self
        }

        func next() {
            guard start < duration else { return finish() }
            let piece = FileManager.default.temporaryDirectory
                .appendingPathComponent("PIsland-piece-\(UUID().uuidString).m4a")
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                return fail(tr("ตัดไฟล์เสียงไม่ได้", "Couldn't split the audio"))
            }
            export.outputURL = piece
            export.outputFileType = .m4a
            export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                           duration: CMTime(seconds: min(Self.pieceLength, duration - start), preferredTimescale: 600))
            export.exportAsynchronously { [self] in
                DispatchQueue.main.async {
                    guard export.status == .completed else { return self.fail(tr("ตัดไฟล์เสียงไม่ได้", "Couldn't split the audio")) }
                    self.recognize(piece)
                }
            }
        }

        private func recognize(_ piece: URL) {
            let request = SFSpeechURLRecognitionRequest(url: piece)
            request.shouldReportPartialResults = false
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            recognizer.recognitionTask(with: request) { [self] result, error in
                guard error != nil || result?.isFinal == true else { return }
                try? FileManager.default.removeItem(at: piece)
                // A silent piece reports "no speech"; that's fine, just move on.
                if let text = result?.bestTranscription.formattedString, !text.isEmpty { parts.append(text) }
                start += Self.pieceLength
                next()
            }
        }

        private func finish() {
            let text = parts.joined(separator: "\n\n")
            guard !text.isEmpty else { return fail(tr("ไม่พบเสียงพูดในไฟล์นี้", "No speech found in this file")) }
            var dir = source.deletingLastPathComponent()
            if !FileManager.default.isWritableFile(atPath: dir.path) {
                dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            }
            let base = source.deletingPathExtension().lastPathComponent + " (transcript)"
            var output = dir.appendingPathComponent(base).appendingPathExtension("txt")
            var n = 2
            while FileManager.default.fileExists(atPath: output.path) {
                output = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension("txt")
                n += 1
            }
            do {
                try text.write(to: output, atomically: true, encoding: .utf8)
                done(.success(output))
            } catch {
                fail(tr("บันทึกไฟล์ไม่ได้", "Couldn't save the file"))
            }
        }

        private func fail(_ message: String) {
            done(.failure(.init(message)))
        }

        private func done(_ result: Result<URL, TranscriptionError>) {
            completion(result)
            keepAlive = nil
        }
    }
}
