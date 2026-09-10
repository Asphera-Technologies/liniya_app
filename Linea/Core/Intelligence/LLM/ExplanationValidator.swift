//
//  ExplanationValidator.swift
//  Linea
//
//  A gate between a language model and the user. The rule-based text is
//  trusted by construction; anything a model writes must pass here first.
//
//  What it enforces is exactly what a model tends to get wrong: inventing a
//  number that was never in the data, claiming something is «меньше обычного»
//  when there is no baseline, drifting into English, drifting into medical
//  advice, or writing an essay where two sentences were asked for.
//

import Foundation

nonisolated enum ValidationResult: Sendable, Equatable {
    case valid
    case invalid(reason: String)

    var isValid: Bool { self == .valid }
}

nonisolated struct ExplanationValidator: Sendable {
    var maxBodySentences: Int
    var maxHeadlineSentences: Int
    var maxLength: Int
    var minimumCyrillicShare: Double

    init(
        maxBodySentences: Int = 3,
        maxHeadlineSentences: Int = 2,
        maxLength: Int = 400,
        minimumCyrillicShare: Double = 0.7
    ) {
        self.maxBodySentences = maxBodySentences
        self.maxHeadlineSentences = maxHeadlineSentences
        self.maxLength = maxLength
        self.minimumCyrillicShare = minimumCyrillicShare
    }

    /// Roots that mean the text has wandered into medicine.
    static let forbiddenRoots = ["диагноз", "болезн", "лекарств", "таблет", "принимай"]

    /// Every number the facts entitle the text to mention, as it would be written.
    func allowedNumbers(facts: [Fact], time: TimeContext) -> Set<String> {
        var allowed = Set<String>()

        func add(_ text: String) { allowed.formUnion(Self.numericTokens(in: text)) }
        func addMinutes(_ minutes: Int) { add(RussianText.duration(minutes: minutes)) }
        func addSeconds(_ seconds: TimeInterval) {
            add(RussianText.hoursMinutes(seconds: abs(seconds)))
            addMinutes(Int((abs(seconds) / 60).rounded()))
        }

        for fact in facts {
            switch fact {
            case .sleepDuration(let seconds), .sleepBaseline(let seconds), .sleepShortAbsolute(let seconds):
                addSeconds(seconds)
            case .sleepVsUsual(let delta, _):
                addSeconds(delta)
            case .sleepEfficiency(let ratio):
                add("\(Int((ratio * 100).rounded()))")
            case .coldStart(let days, let needed):
                add("\(days)"); add("\(needed)")
            case .topTaskCount(let count):
                add("\(count)")
            case .hardWorkDeadline(let date), .workoutPlanned(let date):
                add(RussianText.clock(date, time: time))
            case .taskPlanned(_, _, let start, let end), .mealWindow(_, let start, let end):
                add(RussianText.clock(start, time: time))
                add(RussianText.clock(end, time: time))
            case .behindSchedule(_, _, let lagMinutes):
                addMinutes(lagMinutes)
            case .nextCommitment(_, let at, let minutesLeft):
                add(RussianText.clock(at, time: time))
                addMinutes(minutesLeft)
            case .endOfWorkday(let minutesLeft):
                addMinutes(minutesLeft)
            case .dietRestrictions(let count):
                add("\(count)")
            case .energy(let value, _):
                add("\(Int((value * 100).rounded()))")
            case .hrvVsUsual, .restingHeartRateVsUsual, .recovery, .loadAdvice, .highLoadYesterday,
                 .dataMissing, .providerUnavailable, .taskDeferred, .dayRating, .calibrationChanged:
                continue
            }
        }
        return allowed
    }

    func validate(_ explanation: Explanation, facts: [Fact], taskTitles: [String], time: TimeContext) -> ValidationResult {
        let text = ([explanation.headline, explanation.body] + explanation.reasons).joined(separator: " ")

        if text.count > maxLength {
            return .invalid(reason: "текст длиннее \(maxLength) символов")
        }
        if Self.sentenceCount(explanation.body) > maxBodySentences {
            return .invalid(reason: "больше \(maxBodySentences) предложений в теле")
        }
        if Self.sentenceCount(explanation.headline) > maxHeadlineSentences {
            return .invalid(reason: "больше \(maxHeadlineSentences) предложений в заголовке")
        }

        let lowercased = text.lowercased()
        if let root = Self.forbiddenRoots.first(where: { lowercased.contains($0) }) {
            return .invalid(reason: "медицинская формулировка: \(root)")
        }

        if lowercased.contains("обычн"), !Self.hasComparison(facts) {
            return .invalid(reason: "«обычно» без личной нормы")
        }

        let share = Self.cyrillicShare(text)
        if share < minimumCyrillicShare {
            return .invalid(reason: "мало кириллицы: \(Int(share * 100))%")
        }

        let allowed = allowedNumbers(facts: facts, time: time)
        for token in Self.numericTokens(in: text) where !allowed.contains(token) {
            return .invalid(reason: "число вне фактов: \(token)")
        }

        let known = Set(taskTitles)
        for quoted in Self.quotedFragments(in: text) where !known.contains(quoted) {
            return .invalid(reason: "неизвестное название: \(quoted)")
        }

        return .valid
    }

    // MARK: Parsing helpers

    /// Runs of digits and colons: «6:03» stays one token, «1 ч 20 мин» becomes two.
    static func numericTokens(in text: String) -> Set<String> {
        var tokens = Set<String>()
        var current = ""
        for character in text {
            if character.isNumber || (character == ":" && !current.isEmpty) {
                current.append(character)
            } else if !current.isEmpty {
                tokens.insert(current.trimmingCharacters(in: CharacterSet(charactersIn: ":")))
                current = ""
            }
        }
        if !current.isEmpty { tokens.insert(current.trimmingCharacters(in: CharacterSet(charactersIn: ":"))) }
        return tokens.filter { !$0.isEmpty }
    }

    static func quotedFragments(in text: String) -> [String] {
        var fragments: [String] = []
        var current: String?
        for character in text {
            if character == "«" {
                current = ""
            } else if character == "»" {
                if let value = current { fragments.append(value) }
                current = nil
            } else if current != nil {
                current?.append(character)
            }
        }
        return fragments
    }

    static func sentenceCount(_ text: String) -> Int {
        text.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    static func cyrillicShare(_ text: String) -> Double {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return 1 }
        let cyrillic = letters.filter { $0.unicodeScalars.allSatisfy { scalar in (0x0400...0x04FF).contains(scalar.value) } }
        return Double(cyrillic.count) / Double(letters.count)
    }

    /// Facts that entitle the text to the word «обычно».
    static func hasComparison(_ facts: [Fact]) -> Bool {
        facts.contains { fact in
            switch fact {
            case .sleepVsUsual(_, let level), .recovery(let level):
                return level != .unknown
            case .hrvVsUsual, .restingHeartRateVsUsual, .sleepBaseline:
                return true
            default:
                return false
            }
        }
    }
}
