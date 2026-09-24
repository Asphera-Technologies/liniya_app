//
//  GigaAMModel.swift
//  Linea
//
//  Модель распознавания русской речи, которая живёт в самом приложении:
//  GigaAM-v3 от Сбера (лицензия MIT) с пунктуацией — сразу со знаками
//  препинания, заглавными буквами и числами цифрами. Работает через
//  sherpa-onnx на процессоре любого iPhone, голос никуда не уходит.
//
//  Модель (≈ 233 МБ) приходит вместе с приложением: её кладёт в
//  `Linea.app/GigaAM/` фаза сборки «Speech model» (`Scripts/fetch-speech-model.sh`),
//  там же закреплены версия и отпечатки файлов. В git её нет — GitHub не
//  принимает файлы больше 100 МБ.
//
//  Проверено 23.09.2026 на живой русской речи: 39 секунд сбивчивого рассказа
//  распознаны без ошибок за две секунды, пять минут — за 17 секунд на двух
//  потоках процессора сервера.
//

import Foundation

nonisolated enum GigaAMModel {
    static let title = "GigaAM-v3"

    /// Папка модели внутри приложения — то же имя, что в скрипте сборки.
    static let bundleFolderName = "GigaAM"

    nonisolated enum FileName {
        static let encoder = "encoder.int8.onnx"
        static let decoder = "decoder.onnx"
        static let joiner = "joiner.onnx"
        static let tokens = "tokens.txt"
        /// Детектор речи: находит, где в записи говорят, чтобы резать её по паузам.
        static let vad = "silero_vad.onnx"
    }

    static let fileNames = [FileName.tokens, FileName.decoder, FileName.joiner, FileName.vad, FileName.encoder]

    /// Папка модели в приложении, если сборка её положила. Без неё голос
    /// распознаёт системная диктовка — так бывает только в сборке, где фаза
    /// «Speech model» не отработала.
    static var bundledFolder: URL? {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent(bundleFolderName, isDirectory: true) else { return nil }
        let isComplete = fileNames.allSatisfy { name in
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path(percentEncoded: false))
        }
        return isComplete ? folder : nil
    }

    /// До 24.09.2026 модель скачивалась по кнопке в Application Support.
    /// Теперь она в приложении, а старая копия — лишние 233 МБ на телефоне.
    static func removeLegacyDownload() {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        let legacy = support.appendingPathComponent("Models", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path(percentEncoded: false)) else { return }
        try? FileManager.default.removeItem(at: legacy)
    }
}
