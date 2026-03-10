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
    var hoverActivationDelay: TimeInterval = 0.35

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var hoverStartDate = Date()
    @State private var containerWidth: CGFloat = .zero
    @State private var textWidth: CGFloat = .zero

    private var shouldMarquee: Bool {
        !reduceMotion && isHovered && textWidth > containerWidth + 4
    }

    var body: some View {
        Text(" ")
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                viewportContent
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
        .onChange(of: text) { _, _ in
            hoverStartDate = Date()
        }
    }

    @ViewBuilder
    private var viewportContent: some View {
        if shouldMarquee {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let distance = max(textWidth + gap, 1)
                let elapsed = max(0, context.date.timeIntervalSince(hoverStartDate) - hoverActivationDelay)
                let offset = CGFloat((elapsed * speed).truncatingRemainder(dividingBy: distance))

                HStack(spacing: gap) {
                    label
                        .fixedSize(horizontal: true, vertical: false)
                    label
                        .fixedSize(horizontal: true, vertical: false)
                }
                .offset(x: -offset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            }
        } else {
            label
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.primary)
    }
}
