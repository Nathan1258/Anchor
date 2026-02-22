//
//  GlassEffectViews.swift
//  Anchor
//
//  Created by Nathan Ellis
//

import SwiftUI

// Custom glass effect container that works on earlier macOS versions
struct CustomGlassContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content
    
    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    
    var body: some View {
        content
    }
}

// Custom glass effect modifier
struct GlassEffectModifier: ViewModifier {
    var tintColor: Color? = nil
    var cornerRadius: CGFloat = 12
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
            )
    }
}

// Custom button styles
struct CustomGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CustomGlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                    )
            )
            .foregroundStyle(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Extensions for easier use
extension View {
    func customGlassEffect(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        self.modifier(GlassEffectModifier(tintColor: tint, cornerRadius: cornerRadius))
    }
}

extension ButtonStyle where Self == CustomGlassButtonStyle {
    static var customGlass: CustomGlassButtonStyle {
        CustomGlassButtonStyle()
    }
}

extension ButtonStyle where Self == CustomGlassProminentButtonStyle {
    static var customGlassProminent: CustomGlassProminentButtonStyle {
        CustomGlassProminentButtonStyle()
    }
}
