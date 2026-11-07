#!/usr/bin/env swift
// Renders the site icon (a "|>" pipe on purple) to PNGs and the social card.
// The geometry matches priv/static/favicon.svg (a 100x100 grid), so keep both
// in sync if the design changes.
//
//   swift tools/icon/make_icons.swift
import AppKit
import SwiftUI

let purple = Color(red: 0x5C / 255, green: 0x3B / 255, blue: 0x8C / 255)
let purpleDeep = Color(red: 0x3D / 255, green: 0x21 / 255, blue: 0x66 / 255)

/// The "|>" glyph on the same 100x100 grid as the SVG.
struct PipeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.addRect(CGRect(x: rect.minX + 23 * s, y: rect.minY + 22 * s, width: 10 * s, height: 56 * s))
        path.addLines([p(45, 30), p(77, 46), p(77, 54), p(45, 70), p(45, 60), p(65, 50), p(45, 40)])
        path.closeSubpath()
        return path
    }
}

struct Icon: View {
    var size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [purple, purpleDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            PipeGlyph().fill(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 1200x630 card used by link previews (Open Graph / Twitter).
struct Card: View {
    var body: some View {
        HStack(spacing: 56) {
            Icon(size: 260)
            VStack(alignment: .leading, spacing: 18) {
                Text("Elixir by Example")
                    .font(.system(size: 76, weight: .bold))
                Text("Small, verified, runnable programs.\nElixir, OTP and distributed systems.")
                    .font(.system(size: 36))
                    .foregroundStyle(Color(white: 0.35))
            }
        }
        .padding(80)
        .frame(width: 1200, height: 630, alignment: .leading)
        .background(Color.white)
        .foregroundStyle(Color(white: 0.1))
    }
}

@MainActor func write<V: View>(_ view: V, to path: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { fatalError("failed to render \(path)") }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

MainActor.assumeIsolated {
    let out = "priv/static"
    write(Icon(size: 32), to: "\(out)/favicon-32.png")
    write(Icon(size: 180), to: "\(out)/apple-touch-icon.png")
    write(Card(), to: "\(out)/og.png")
}
