//
//  Buttons.swift
//  Anchor
//
//  Created by Nathan Ellis on 04/02/2026.
//
import SwiftUI

struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(.primary)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
