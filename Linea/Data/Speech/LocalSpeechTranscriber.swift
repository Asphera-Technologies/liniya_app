//
//  LocalSpeechTranscriber.swift
//  Linea
//
//  Распознавание итога дня моделью GigaAM-v3 прямо на телефоне, через
//  sherpa-onnx. Запись режется детектором речи Silero на фразы до 20 секунд
//  (модель берёт до 25 за раз), каждая распознаётся отдельно, текст
//  склеивается. Настройки те же, что проверены на живой речи 23.09.2026:
//  признаки 64, декодер transducer NeMo, жадный поиск, два потока.
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
    /// Фраза длиннее режется детектором: модель надёжно берёт до 25 секунд.
    static let maxSegmentSeconds: Float = 20

    static func transcribe(fileAt url: URL, modelFolder: URL) throws -> String {
        let samples = try AudioSamples.load(url)
        guard !samples.isEmpty else { return "" }
        for file in GigaAMModel.files {
            let path = modelFolder.appendingPathComponent(file.name).path(percentEncoded: false)
            // Обёртка sherpa-onnx падает, если модель не открылась, — проверяем заранее.
            guard FileManager.default.fileExists(atPath: path) else { throw OnDeviceSpeechError.unavailable }
        }

        return autoreleasepool {
            let recognizer = makeRecognizer(folder: modelFolder)
            let vad = makeDetector(folder: modelFolder)
            var parts: [String] = []

            func drain() {
                while !vad.isEmpty() {
                    let segment = vad.front()
                    let text = recognizer.decode(samples: segment.samples, sampleRate: sampleRate).text
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { parts.append(text) }
                    vad.pop()
                }
            }

            let window = 512
            var start = 0
            while start < samples.count {
                let end = min(start + window, samples.count)
                vad.acceptWaveform(samples: Array(samples[start..<end]))
                drain()
                start = end
            }
            vad.flush()
            drain()
            return parts.joined(separator: " ")
        }
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
                minSilenceDuration: 0.5,
                minSpeechDuration: 0.25,
                windowSize: 512,
                maxSpeechDuration: maxSegmentSeconds
            )
            var config = sherpaOnnxVadModelConfig(sileroVad: silero, sampleRate: Int32(sampleRate), numThreads: 1, provider: "cpu")
            return SherpaOnnxVoiceActivityDetectorWrapper(config: &config, buffer_size_in_seconds: 120)
        }
    }
}
