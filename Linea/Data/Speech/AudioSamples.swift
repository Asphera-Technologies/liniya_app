//
//  AudioSamples.swift
//  Linea
//
//  Запись итога дня → отсчёты для модели распознавания: моно, 16 кГц,
//  Float32 в диапазоне −1…1. Наша запись уже 16 кГц моно, её достаточно
//  раскодировать из AAC; любой другой файл перекодируется конвертером.
//

import Foundation
import AVFoundation

nonisolated enum AudioSamplesError: Error, LocalizedError {
    case unsupportedFormat
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "Не получилось прочитать запись."
        case .conversionFailed: return "Не получилось подготовить запись к распознаванию."
        }
    }
}

nonisolated enum AudioSamples {
    static let sampleRate: Double = 16_000

    static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        if format.sampleRate == sampleRate && format.channelCount == 1 {
            return try readAll(file, format: format)
        }
        return try converted(file, from: format)
    }

    /// Файл уже в нужном формате: читаем целиком.
    private static func readAll(_ file: AVAudioFile, format: AVAudioFormat) throws -> [Float] {
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { return [] }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw AudioSamplesError.unsupportedFormat
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { throw AudioSamplesError.unsupportedFormat }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    /// Любой другой формат: частота и число каналов приводятся конвертером.
    private static func converted(_ file: AVAudioFile, from source: AVAudioFormat) throws -> [Float] {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw AudioSamplesError.unsupportedFormat
        }
        let chunk: AVAudioFrameCount = 16_384
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: chunk) else {
            throw AudioSamplesError.conversionFailed
        }
        let outputCapacity = AVAudioFrameCount(Double(chunk) * sampleRate / source.sampleRate) + 1_024
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * sampleRate / source.sampleRate) + 1)

        var finished = false
        while !finished {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outputCapacity) else {
                throw AudioSamplesError.conversionFailed
            }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if file.framePosition >= file.length {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input, frameCount: chunk)
                } catch {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = input.frameLength > 0 ? .haveData : .endOfStream
                return input.frameLength > 0 ? input : nil
            }
            if let conversionError { throw conversionError }
            if let channel = output.floatChannelData?[0], output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
            }
            switch status {
            case .endOfStream, .error: finished = true
            case .inputRanDry: finished = file.framePosition >= file.length && output.frameLength == 0
            case .haveData: continue
            @unknown default: finished = true
            }
        }
        return samples
    }
}
