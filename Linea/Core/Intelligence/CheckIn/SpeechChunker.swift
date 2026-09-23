//
//  SpeechChunker.swift
//  Linea
//
//  Как нарезать пятиминутный рассказ для модели распознавания на телефоне.
//  GigaAM надёжно берёт до 25 секунд за раз, а детектор речи находит фразы
//  по паузам. Если отдавать модели каждую фразу отдельно, на стыках теряются
//  точки и появляются лишние слова: проверено 23.09.2026, «после обеда Да я
//  плохо соображаю». Поэтому соседние фразы склеиваются в куски не длиннее
//  предела — вместе с паузами между ними, чтобы модель слышала контекст.
//

import Foundation

nonisolated enum SpeechChunker {

    /// - Parameters:
    ///   - ranges: где детектор услышал речь, в отсчётах;
    ///   - total: длина записи в отсчётах;
    ///   - limit: самый длинный кусок для модели;
    ///   - padding: сколько тишины оставить по краям куска, чтобы не резать звук.
    static func chunks(speech ranges: [Range<Int>], total: Int, limit: Int, padding: Int) -> [Range<Int>] {
        guard limit > 0, total > 0 else { return [] }

        var merged: [Range<Int>] = []
        var current: Range<Int>?
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) where !range.isEmpty {
            if let open = current, range.upperBound - open.lowerBound <= limit {
                current = open.lowerBound..<max(open.upperBound, range.upperBound)
            } else {
                if let open = current { merged.append(open) }
                current = range
            }
        }
        if let open = current { merged.append(open) }

        var result: [Range<Int>] = []
        for range in merged {
            var start = max(0, range.lowerBound - padding)
            let end = min(total, range.upperBound + padding)
            // Сплошная речь длиннее предела — режем жёстко, модель не должна её получить целиком.
            while end - start > limit + 2 * padding {
                result.append(start..<(start + limit))
                start += limit
            }
            if start < end { result.append(start..<end) }
        }
        return result
    }
}
