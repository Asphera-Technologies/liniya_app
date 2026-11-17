import Foundation

nonisolated enum VoiceTaskWindow {
    static func isEventCommand(_ text: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter }
        let commands: Set<Substring> = ["запиши", "записать", "занеси", "внеси", "добавь", "создай"]
        guard let index = words.firstIndex(where: { commands.contains($0) }), index <= 2,
              let object = words.dropFirst(index + 1).first(where: { $0 != "мне" }) else { return false }
        if object == "событие" { return true }
        if object == "задачу" || object == "задачку" { return false }
        return ["запиши", "записать", "занеси", "внеси"].contains(words[index])
    }
}
