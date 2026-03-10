//
//  HoverMarqueeText.swift
//  AceClass
//
//  Created by Codex on 3/10/26.
//

import SwiftUI

private struct HoverMarqueeContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HoverMarqueeTextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HoverMarqueeContainerWidthReader: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: HoverMarqueeContainerWidthPreferenceKey.self, value: geometry.size.width)
        }
    }
}

private struct HoverMarqueeTextWidthReader: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(key: HoverMarqueeTextWidthPreferenceKey.self, value: geometry.size.width)
        }
    }
}

struct HoverMarqueeText: View {
    let text: String
    var font: Font = .body
    var gap: CGFloat = 28
    var speed: CGFloat = 42

    @State private var isHovered = false
    @State private var hoverStartDate = Date()
    @State private var containerWidth: CGFloat = .zero
    @State private var textWidth: CGFloat = .zero

    private var shouldMarquee: Bool {
        isHovered && textWidth > containerWidth + 4
    }

    var body: some View {
        ZStack(alignment: .leading) {
            label
                .lineLimit(1)
                .hidden()

            if shouldMarquee {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                    let distance = max(textWidth + gap, 1)
                    let elapsed = context.date.timeIntervalSince(hoverStartDate)
                    let offset = CGFloat((elapsed * speed).truncatingRemainder(dividingBy: distance))

                    HStack(spacing: gap) {
                        label
                            .fixedSize(horizontal: true, vertical: false)
                        label
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: -offset)
                }
            } else {
                label
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HoverMarqueeContainerWidthReader())
        .onPreferenceChange(HoverMarqueeContainerWidthPreferenceKey.self) { containerWidth = $0 }
        .background(
            label
                .fixedSize(horizontal: true, vertical: false)
                .hidden()
                .background(HoverMarqueeTextWidthReader())
                .onPreferenceChange(HoverMarqueeTextWidthPreferenceKey.self) { textWidth = $0 }
        )
        .contentShape(Rectangle())
        .clipped()
        .onHover { hovering in
            if hovering && !isHovered {
                hoverStartDate = Date()
            }
            isHovered = hovering
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.primary)
    }
}
