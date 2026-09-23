//
//  LocalSpeechModel.swift
//  Linea
//
//  Модель распознавания русской речи, которая живёт на самом телефоне:
//  GigaAM-v3 от Сбера (лицензия MIT) с пунктуацией — сразу со знаками
//  препинания, заглавными буквами и числами цифрами. Работает через
//  sherpa-onnx на процессоре любого iPhone, голос никуда не уходит.
//
//  Проверено 23.09.2026 на живой русской речи: 39 секунд сбивчивого рассказа
//  распознаны без ошибок за две секунды, пять минут — за 17 секунд на двух
//  потоках процессора сервера.
//
//  Модель не кладётся в приложение (≈ 233 МБ), а скачивается один раз по
//  кнопке. Это официальная конвертация автора sherpa-onnx; версия закреплена
//  коммитом, каждый файл сверяется по SHA-256 — подменить модель по дороге
//  нельзя. К публикации модель лучше держать на своём сервере — адреса ниже
//  меняются в одном месте.
//

import Foundation
import CryptoKit
import Observation
import OSLog

/// Один файл модели: откуда качать, сколько весит и какой у него отпечаток.
nonisolated struct ModelFile: Sendable, Equatable {
    let name: String
    let url: URL
    let bytes: Int64
    let sha256: String
}

/// Какая модель и откуда. Отдельно от состояния скачивания, чтобы описание
/// читалось из фонового распознавания без перехода на главный поток.
nonisolated enum GigaAMModel {
    static let title = "GigaAM-v3"

    /// Официальная конвертация GigaAM-v3 с пунктуацией от автора sherpa-onnx;
    /// версия зафиксирована коммитом, чтобы файлы не поменялись под нами.
    static let base = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16/resolve/a6039be7cee829a9044a69ac0ebaf1c191217c97/"

    nonisolated enum FileName {
        static let encoder = "encoder.int8.onnx"
        static let decoder = "decoder.onnx"
        static let joiner = "joiner.onnx"
        static let tokens = "tokens.txt"
        static let vad = "silero_vad.onnx"
    }

    static let files: [ModelFile] = [
        ModelFile(name: FileName.tokens, url: URL(string: base + FileName.tokens)!, bytes: 13_354,
                  sha256: "39abae20e692998290c574e606f11a9edef2902a1995463fcff63d1490cf22b7"),
        ModelFile(name: FileName.decoder, url: URL(string: base + FileName.decoder)!, bytes: 4_600_132,
                  sha256: "38fc7475443ea2a26f63211ca350f73ac50fff824ab7a3876ee2bd610c53bbc4"),
        ModelFile(name: FileName.joiner, url: URL(string: base + FileName.joiner)!, bytes: 2_712_896,
                  sha256: "602ff7017a93311aad34df1437c8d7f49911353c13d6eae7a6ee7b041339465c"),
        // Детектор речи: находит, где в записи говорят, чтобы резать её по паузам.
        ModelFile(name: FileName.vad, url: URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx")!,
                  bytes: 643_854, sha256: "9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6"),
        ModelFile(name: FileName.encoder, url: URL(string: base + FileName.encoder)!, bytes: 224_570_820,
                  sha256: "369f35a71bf288d3b8e0391fabd8dba5f2314088d440bca474056b7b4b6e66bf"),
    ]

    static var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }

    /// «≈ 233 МБ».
    static var sizeText: String { "≈ \(Int((Double(totalBytes) / 1_000_000).rounded())) МБ" }
}

@Observable
@MainActor
final class LocalSpeechModel {

    enum State: Equatable {
        case notInstalled
        case downloading(progress: Double)
        case verifying
        case ready
        case failed(String)
    }

    private(set) var state: State = .notInstalled
    let folder: URL
    private var downloadTask: Task<Void, Never>?

    init(folder: URL = LocalSpeechModel.defaultFolder()) {
        self.folder = folder
        refresh()
    }

    nonisolated static func defaultFolder() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Models/gigaam-v3-punct", isDirectory: true)
    }

    var isReady: Bool { state == .ready }

    var isBusy: Bool {
        switch state {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    /// Файлы на месте и нужного размера — модель готова. Полный отпечаток
    /// проверяется при скачивании, а на старте хватает размеров.
    func refresh() {
        guard !isBusy else { return }
        state = GigaAMModel.files.allSatisfy { Self.isComplete($0, in: folder) } ? .ready : .notInstalled
    }

    func download() {
        guard downloadTask == nil, !isReady else { return }
        state = .downloading(progress: 0)
        downloadTask = Task { [weak self] in await self?.runDownload() }
    }

    func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        state = .notInstalled
        refresh()
    }

    func delete() {
        downloadTask?.cancel()
        downloadTask = nil
        try? FileManager.default.removeItem(at: folder)
        state = .notInstalled
        LineaLog.checkIn.notice("Модель распознавания удалена")
    }

    // MARK: Скачивание

    private func runDownload() async {
        let folder = self.folder
        let total = Double(GigaAMModel.totalBytes)
        do {
            try Self.prepare(folder)
            var done: Int64 = 0
            for file in GigaAMModel.files {
                try Task.checkCancellation()
                if Self.isComplete(file, in: folder) {
                    // Повтор после обрыва: скачанное уже не качаем.
                    done += file.bytes
                    continue
                }
                let before = done
                // Замыкание живёт только до конца загрузки файла — цикла ссылок нет.
                let temporary = try await Self.fetch(file.url) { fraction in
                    let overall = (Double(before) + Double(file.bytes) * fraction) / total
                    Task { @MainActor in
                        guard case .downloading = self.state else { return }
                        self.state = .downloading(progress: overall)
                    }
                }
                state = .verifying
                let digest = try await Task.detached(priority: .userInitiated) { try Self.sha256(of: temporary) }.value
                guard digest == file.sha256 else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw ModelDownloadError.corrupted(file.name)
                }
                let target = folder.appendingPathComponent(file.name)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: temporary, to: target)
                done += file.bytes
                state = .downloading(progress: Double(done) / total)
            }
            state = .ready
            LineaLog.checkIn.notice("Модель распознавания скачана: \(GigaAMModel.sizeText, privacy: .public)")
        } catch {
            // Отмена приходит и как CancellationError, и как URLError(.cancelled).
            guard !Task.isCancelled else {
                refresh()
                return
            }
            LineaLog.checkIn.error("Модель распознавания не скачалась: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
        // После отмены ссылку уже сбросил cancel(), а новая загрузка могла начаться.
        if !Task.isCancelled { downloadTask = nil }
    }

    nonisolated private static func prepare(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Сотни мегабайт не место в резервной копии iCloud — модель всегда можно скачать снова.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = folder
        try folder.setResourceValues(values)
    }

    nonisolated private static func isComplete(_ file: ModelFile, in folder: URL) -> Bool {
        let url = folder.appendingPathComponent(file.name)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return Int64(size) == file.bytes
    }

    /// Качает файл и сообщает долю скачанного 0…1.
    nonisolated private static func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadProgressDelegate(onProgress: progress)
        let (location, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: location)
            throw ModelDownloadError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        // Системный временный файл может исчезнуть — сразу переносим в свой.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: location, to: kept)
        return kept
    }

    /// Отпечаток большого файла по кусочкам, без чтения 320 МБ в память.
    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum ModelDownloadError: Error, LocalizedError {
    case http(Int)
    case corrupted(String)

    var errorDescription: String? {
        switch self {
        case .http(let status): return "Сервер модели ответил ошибкой \(status). Попробуй позже."
        case .corrupted(let name): return "Файл \(name) скачался с ошибкой. Попробуй ещё раз."
        }
    }
}

/// Прогресс одной загрузки. Колбэки приходят на очереди URLSession, не на
/// главном потоке, поэтому класс неизолированный.
private nonisolated final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastReported = -1.0

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            let value = progress.fractionCompleted
            // Раз в процент, а не на каждый пакет.
            guard value - self.lastReported >= 0.01 || value >= 1 else { return }
            self.lastReported = value
            self.onProgress(value)
        }
    }
}
