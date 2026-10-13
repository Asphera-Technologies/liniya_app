//
//  NoticeToast.swift
//  Linea
//
//  Короткое сообщение сверху на пару секунд — куда Linea перенесла задачу:
//  «Поставила на завтра, 10:00.» Спокойная капсула цвета чернил, без кнопок:
//  прочитал — и она ушла сама. VoiceOver её зачитывает.
//

import SwiftUI
import UIKit

struct NoticeToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(LineaFont.caption)
            .foregroundStyle(LineaColor.onInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule(style: .continuous).fill(LineaColor.ink))
            .padding(.horizontal, LineaMetrics.screenPadding)
            // Не мешает нажимать то, что под ним.
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("notice")
            .onAppear {
                UIAccessibility.post(notification: .announcement, argument: text)
            }
    }
}
