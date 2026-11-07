#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSpec {
	let size: CGFloat
	let opaque: Bool
	let backgroundColor: NSColor?
	let insetScale: CGFloat
	let cornerRadiusRatio: CGFloat
}

enum IconError: Error, CustomStringConvertible {
	case missingParent(String)
	case imageLoad(String)
	case pngEncode(String)
	case writeFailed(String)

	var description: String {
		switch self {
		case .missingParent(let path): return "Missing parent directory for \(path)"
		case .imageLoad(let path): return "Could not load source image at \(path)"
		case .pngEncode(let path): return "Could not encode PNG at \(path)"
		case .writeFailed(let path): return "Could not write \(path)"
		}
	}
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = repoRoot.appendingPathComponent("brand/jp-eyes.png")

let alphaOutputs: [(String, IconSpec)] = [
	("web/public/jpthecat-logo.png", IconSpec(size: 256, opaque: false, backgroundColor: nil, insetScale: 1.0, cornerRadiusRatio: 0.22)),
	("mac/Sources/JPtheCatApp/Resources/jp-menubar.png", IconSpec(size: 256, opaque: false, backgroundColor: nil, insetScale: 1.0, cornerRadiusRatio: 0.22)),
	("web/app/icon.png", IconSpec(size: 512, opaque: false, backgroundColor: nil, insetScale: 1.0, cornerRadiusRatio: 0.22)),
	("web/public/icon-512.png", IconSpec(size: 512, opaque: false, backgroundColor: nil, insetScale: 1.0, cornerRadiusRatio: 0.22)),
	("web/public/icon-192.png", IconSpec(size: 192, opaque: false, backgroundColor: nil, insetScale: 1.0, cornerRadiusRatio: 0.22)),
]

let opaqueOutputs: [(String, IconSpec)] = [
	("web/app/apple-icon.png", IconSpec(size: 180, opaque: true, backgroundColor: .white, insetScale: 1.06, cornerRadiusRatio: 0.22)),
	("web/public/icon-maskable-512.png", IconSpec(size: 512, opaque: true, backgroundColor: NSColor(calibratedRed: 0xFF / 255.0, green: 0xF6 / 255.0, blue: 0xE6 / 255.0, alpha: 1.0), insetScale: 0.78, cornerRadiusRatio: 0.0)),
]

let iconsetDir = repoRoot.appendingPathComponent("mac/AppIcon.iconset")

func ensureParentDirectory(for url: URL) throws {
	let parent = url.deletingLastPathComponent()
	var isDir: ObjCBool = false
	if FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue {
		return
	}
	throw IconError.missingParent(url.path)
}

func drawRoundedIcon(from source: NSImage, spec: IconSpec) -> NSBitmapImageRep? {
	let px = Int(spec.size.rounded())
	let bitmapInfo = spec.opaque
		? CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
		: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
	guard let cgContext = CGContext(
		data: nil,
		width: px,
		height: px,
		bitsPerComponent: 8,
		bytesPerRow: 0,
		space: CGColorSpaceCreateDeviceRGB(),
		bitmapInfo: bitmapInfo.rawValue
	) else {
		return nil
	}

	let rep = NSBitmapImageRep(cgImage: cgContext.makeImage() ?? CGImage.empty(px: px))
	rep.size = NSSize(width: spec.size, height: spec.size)
	NSGraphicsContext.saveGraphicsState()
	let context = NSGraphicsContext(cgContext: cgContext, flipped: false)
	NSGraphicsContext.current = context

	if spec.opaque, let bg = spec.backgroundColor {
		bg.setFill()
		NSBezierPath(rect: NSRect(origin: .zero, size: NSSize(width: spec.size, height: spec.size))).fill()
	}

	let drawRect: NSRect
	if spec.cornerRadiusRatio > 0 {
		let path = NSBezierPath(
			roundedRect: NSRect(origin: .zero, size: rep.size),
			xRadius: spec.size * spec.cornerRadiusRatio,
			yRadius: spec.size * spec.cornerRadiusRatio
		)
		path.addClip()
		let scaledSize = spec.size * spec.insetScale
		let inset = (spec.size - scaledSize) / 2.0
		drawRect = NSRect(x: inset, y: inset, width: scaledSize, height: scaledSize)
	} else {
		let scaledSize = spec.size * spec.insetScale
		let inset = (spec.size - scaledSize) / 2.0
		drawRect = NSRect(x: inset, y: inset, width: scaledSize, height: scaledSize)
	}

	source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)

	NSGraphicsContext.restoreGraphicsState()
	guard let image = cgContext.makeImage() else { return nil }
	return NSBitmapImageRep(cgImage: image)
}

extension CGImage {
	static func empty(px: Int) -> CGImage {
		let cs = CGColorSpaceCreateDeviceRGB()
		let ctx = CGContext(
			data: nil,
			width: px,
			height: px,
			bitsPerComponent: 8,
			bytesPerRow: 0,
			space: cs,
			bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
		)!
		return ctx.makeImage()!
	}
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
	try ensureParentDirectory(for: url)
	guard let data = rep.representation(using: .png, properties: [:]) else {
		throw IconError.pngEncode(url.path)
	}
	do {
		try data.write(to: url, options: .atomic)
	} catch {
		throw IconError.writeFailed(url.path)
	}
}

func generateIconset(from source: NSImage) throws {
	try? FileManager.default.removeItem(at: iconsetDir)
	try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

	let sizes: [(name: String, size: CGFloat)] = [
		("icon_16x16.png", 16),
		("icon_16x16@2x.png", 32),
		("icon_32x32.png", 32),
		("icon_32x32@2x.png", 64),
		("icon_128x128.png", 128),
		("icon_128x128@2x.png", 256),
		("icon_256x256.png", 256),
		("icon_256x256@2x.png", 512),
		("icon_512x512.png", 512),
		("icon_512x512@2x.png", 1024),
	]

	for (name, size) in sizes {
		let rep = drawRoundedIcon(
			from: source,
			spec: IconSpec(size: size, opaque: false, backgroundColor: nil, insetScale: 1.0, cornerRadiusRatio: 0.22)
		)
		guard let rep else { throw IconError.pngEncode(iconsetDir.appendingPathComponent(name).path) }
		try writePNG(rep, to: iconsetDir.appendingPathComponent(name))
	}
}

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
	fputs("\(IconError.imageLoad(sourceURL.path))\n", stderr)
	exit(1)
}

do {
	for (path, spec) in alphaOutputs + opaqueOutputs {
		let url = repoRoot.appendingPathComponent(path)
		guard let rep = drawRoundedIcon(from: sourceImage, spec: spec) else {
			throw IconError.pngEncode(url.path)
		}
		try writePNG(rep, to: url)
		print("wrote \(path)")
	}

	try generateIconset(from: sourceImage)
	print("wrote mac/AppIcon.iconset")
} catch {
	fputs("\(error)\n", stderr)
	exit(1)
}
