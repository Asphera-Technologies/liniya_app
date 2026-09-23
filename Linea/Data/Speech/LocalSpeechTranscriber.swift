//
//  LocalSpeechTranscriber.swift
//  Linea
//
//  Распознавание итога дня моделью GigaAM-v3 прямо на телефоне, через
//  sherpa-onnx. Детектор речи Silero находит, где говорят, фразы склеиваются
//  в куски до 20 секунд (модель берёт до 25 за раз), каждый кусок
//  распознаётся, текст складывается. Настройки те же, что проверены на живой
//  речи 23.09.2026: признаки 64, декодер transducer NeMo, жадный поиск, два
//  потока — пять минут речи за 17 секунд на сервере.
//

import Foundation
import SherpaOnnx

nonisolated struct LocalSpeechTranscriber: SpeechTranscribing {
    let modelFolder: URL

    init(modelFolder: URL) {
        self.modelFolder = modelFolder
    }

    var id: String { "local:gigaam-v3" }

    func transcribe(audioAt url: URL, localeIdentifier: String) async throws -> Transcript {
        let folder = modelFolder
        // Распознавание — работа процессора на десятки секунд: не на главном потоке.
        let text = try await Task.detached(priority: .userInitiated) {
            try GigaAMRecognizer.transcribe(fileAt: url, modelFolder: folder)
        }.value
        guard !text.isEmpty else { throw OnDeviceSpeechError.noSpeech }
        return Transcript(text: text, transcriberID: id)
    }
}

nonisolated enum GigaAMRecognizer {
    static let sampleRate = 16_000
    /// Два производительных ядра есть у любого iPhone с iOS 18.
    static let threads = 2
    /// Самый длинный кусок для модели: GigaAM надёжно берёт до 25 секунд.
    static let chunkLimit = 20 * sampleRate

    static func transcribe(fileAt url: URL, modelFolder: URL) throws -> String {
        let samples = try AudioSamples.load(url)
        guard !samples.isEmpty else { return "" }
        for file in GigaAMModel.files {
            let path = modelFolder.appendingPathComponent(file.name).path(percentEncoded: false)
            // Обёртка sherpa-onnx падает, если модель не открылась, — проверяем заранее.
            guard FileManager.default.fileExists(atPath: path) else { throw OnDeviceSpeechError.unavailable }
        }

        return autoreleasepool {
            let ranges = speechRanges(in: samples, detector: makeDetector(folder: modelFolder))
            // Фразы склеиваются в куски до 20 секунд вместе с паузами: модели нужен
            // контекст, иначе на стыках теряются точки и появляются лишние слова.
            let chunks = SpeechChunker.chunks(speech: ranges, total: samples.count, limit: chunkLimit, padding: sampleRate / 5)
            let recognizer = makeRecognizer(folder: modelFolder)
            return chunks
                .map { chunk in
                    recognizer.decode(samples: Array(samples[chunk]), sampleRate: sampleRate).text
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    /// Где в записи говорят. Детектору сначала дают полсекунды тишины:
    /// иначе речь с первой же секунды записи теряет первый слог.
    private static func speechRanges(in samples: [Float], detector: SherpaOnnxVoiceActivityDetectorWrapper) -> [Range<Int>] {
        let lead = sampleRate / 2
        var ranges: [Range<Int>] = []

        func drain() {
            while !detector.isEmpty() {
                let segment = detector.front()
                let start = max(0, segment.start - lead)
                let end = min(samples.count, start + segment.n)
                if start < end { ranges.append(start..<end) }
                detector.pop()
            }
        }

        detector.acceptWaveform(samples: [Float](repeating: 0, count: lead))
        let window = 512
        var offset = 0
        while offset < samples.count {
            let end = min(offset + window, samples.count)
            detector.acceptWaveform(samples: Array(samples[offset..<end]))
            drain()
            offset = end
        }
        detector.flush()
        drain()
        return ranges
    }

    /// Строки путей живут, пока создаётся распознаватель: sherpa-onnx берёт
    /// из них указатели и копирует их только внутри вызова.
    private static func makeRecognizer(folder: URL) -> SherpaOnnxOfflineRecognizer {
        let encoder = folder.appendingPathComponent(GigaAMModel.FileName.encoder).path(percentEncoded: false)
        let decoder = folder.appendingPathComponent(GigaAMModel.FileName.decoder).path(percentEncoded: false)
        let joiner = folder.appendingPathComponent(GigaAMModel.FileName.joiner).path(percentEncoded: false)
        let tokens = folder.appendingPathComponent(GigaAMModel.FileName.tokens).path(percentEncoded: false)
        return withExtendedLifetime([encoder, decoder, joiner, tokens]) {
            let transducer = sherpaOnnxOfflineTransducerModelConfig(encoder: encoder, decoder: decoder, joiner: joiner)
            let model = sherpaOnnxOfflineModelConfig(
                tokens: tokens,
                transducer: transducer,
                numThreads: threads,
                provider: "cpu",
                modelType: "nemo_transducer"
            )
            var config = sherpaOnnxOfflineRecognizerConfig(
                featConfig: sherpaOnnxFeatureConfig(sampleRate: sampleRate, featureDim: 64),
                modelConfig: model,
                decodingMethod: "greedy_search"
            )
            return SherpaOnnxOfflineRecognizer(config: &config)
        }
    }

    private static func makeDetector(folder: URL) -> SherpaOnnxVoiceActivityDetectorWrapper {
        let model = folder.appendingPathComponent(GigaAMModel.FileName.vad).path(percentEncoded: false)
        return withExtendedLifetime(model) {
            let silero = sherpaOnnxSileroVadModelConfig(
                model: model,
                threshold: 0.5,
                minSilenceDuration: 0.3,
                minSpeechDuration: 0.25,
                windowSize: 512,
                maxSpeechDuration: 20
            )
            var config = sherpaOnnxVadModelConfig(sileroVad: silero, sampleRate: Int32(sampleRate), numThreads: 1, provider: "cpu")
            return SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: 120)
        }
    }
}
