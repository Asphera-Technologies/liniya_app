//
//  SwipeActionsRow.swift
//  Linea
//
//  Свайп по строке, которая живёт не в `List`, а в обычной прокрутке экрана:
//  вправо — одно действие, влево — другое. Под строкой проступает панель с
//  подписью; дотянул до порога — лёгкий щелчок, отпустил — действие
//  выполнено, строка возвращается на место. Не дотянул — просто возвращается.
//
//  Почему не `.swipeActions`: они работают только в `List`, а «План» и
//  «Сегодня» — одна прокрутка со своими отступами (ADR-030). Жест — UIKit:
//  он начинается, только если палец пошёл вбок, а вертикальное движение
//  целиком отдаёт прокрутке экрана.
//

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Действие под строкой: подпись, значок и что сделать.
struct SwipeAction {
    enum Tone {
        /// Чёрная панель — главное действие («Готово»).
        case ink
        /// Серая панель — второе («Перенести»).
        case quiet
    }

    let title: String
    let systemImage: String
    var tone: Tone = .ink
    let perform: () -> Void
}

struct SwipeActionsRow<Content: View>: View {
    /// Свайп вправо.
    var leading: SwipeAction?
    /// Свайп влево.
    var trailing: SwipeAction?
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    /// Чья панель видна — держится, пока строка едет обратно.
    @State private var side: HorizontalEdge?
    @State private var isArmed = false
    @State private var performed = 0

    /// Дотянул до порога — отпущенный палец выполняет действие.
    static var threshold: CGFloat { 76 }
    /// Дальше строка идёт туже.
    private static let resistanceStart: CGFloat = 116

    var body: some View {
        content()
            .background(LineaColor.background)
            .offset(x: offset)
            .background { revealedPanel }
            .gesture(HorizontalPanGesture(onChanged: drag, onEnded: release))
            .sensoryFeedback(.impact(weight: .light), trigger: isArmed) { _, armed in armed }
            .sensoryFeedback(.impact(weight: .medium), trigger: performed)
    }

    // MARK: Панель

    @ViewBuilder
    private var revealedPanel: some View {
        if side == .leading, let leading {
            panel(leading, alignment: .leading)
        } else if side == .trailing, let trailing {
            panel(trailing, alignment: .trailing)
        }
    }

    private func panel(_ action: SwipeAction, alignment: Alignment) -> some View {
        let isInk = action.tone == .ink
        return RoundedRectangle(cornerRadius: LineaMetrics.controlRadius, style: .continuous)
            .fill(isInk ? LineaColor.ink : LineaColor.fill)
            .overlay(alignment: alignment) {
                Label(action.title, systemImage: action.systemImage)
                    .labelStyle(.titleAndIcon)
                    .font(LineaFont.control)
                    .foregroundStyle(isInk ? LineaColor.onInk : LineaColor.textPrimary)
                    .fixedSize()
                    .scaleEffect(isArmed ? 1 : 0.92)
                    .opacity(min(1, abs(offset) / Self.threshold))
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    // MARK: Жест

    private func drag(_ translation: CGFloat) {
        var x = translation
        if x > 0, leading == nil { x = 0 }
        if x < 0, trailing == nil { x = 0 }
        let magnitude = abs(x)
        if magnitude > Self.resistanceStart {
            x = (Self.resistanceStart + (magnitude - Self.resistanceStart) * 0.3) * (x > 0 ? 1 : -1)
        }
        if x != 0 { side = x > 0 ? .leading : .trailing }
        offset = x
        isArmed = abs(x) >= Self.threshold
    }

    /// `completed` — палец отпущен; `false` — жест прервала система.
    private func release(velocity: CGFloat, completed: Bool) {
        let action = offset > 0 ? leading : (offset < 0 ? trailing : nil)
        // Быстрый короткий смахивающий жест тоже считается.
        let flung = abs(velocity) > 900 && abs(offset) > 36 && (velocity > 0) == (offset > 0)
        let fires = completed && (isArmed || flung)
        isArmed = false
        withAnimation(.snappy(duration: 0.28)) {
            offset = 0
        } completion: {
            if offset == 0 { side = nil }
        }
        if fires, let action {
            performed += 1
            action.perform()
        }
    }
}

// MARK: - Горизонтальный жест

/// UIKit-жест для SwiftUI: сдвиг пальца по горизонтали.
struct HorizontalPanGesture: UIGestureRecognizerRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (_ velocity: CGFloat, _ completed: Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> HorizontalPanRecognizer {
        let recognizer = HorizontalPanRecognizer()
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended:
            onEnded(recognizer.velocity(in: recognizer.view).x, true)
        case .cancelled, .failed:
            onEnded(0, false)
        default:
            break
        }
    }
}

/// Панорама, которая начинается, только когда палец явно идёт вбок. Если он
/// пошёл вверх или вниз, жест сразу сдаётся, и экран прокручивается как обычно.
final class HorizontalPanRecognizer: UIPanGestureRecognizer {
    private var origin: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if origin == nil, let touch = touches.first {
            origin = touch.location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let origin, let touch = touches.first {
            let point = touch.location(in: view)
            let dx = abs(point.x - origin.x)
            let dy = abs(point.y - origin.y)
            // Пока сдвиг меньше 8 точек, направление не решаем.
            if max(dx, dy) >= 8, dx <= dy * 1.2 {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        origin = nil
    }

    /// Прокрутка экрана ждёт, пока жест решит, что палец идёт не вбок: иначе
    /// она могла бы перехватить начало свайпа. Решение — на первых 8 точках,
    /// так что вертикальная прокрутка не запаздывает.
    override func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer, otherGestureRecognizer.view is UIScrollView {
            return true
        }
        return super.shouldBeRequiredToFail(by: otherGestureRecognizer)
    }
}
