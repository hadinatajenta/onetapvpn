import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: render-icon.swift <source> <output>")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
    fail("Cannot read \(sourceURL.path)")
}

let sourceWidth = sourceImage.width
let sourceHeight = sourceImage.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
let pixelCount = sourceWidth * sourceHeight
let sourcePixels = UnsafeMutablePointer<UInt8>.allocate(capacity: pixelCount * 4)
sourcePixels.initialize(repeating: 0, count: pixelCount * 4)
defer { sourcePixels.deallocate() }

guard let sourceContext = CGContext(
    data: sourcePixels,
    width: sourceWidth,
    height: sourceHeight,
    bitsPerComponent: 8,
    bytesPerRow: sourceWidth * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("Cannot create source context")
}

sourceContext.interpolationQuality = .high
sourceContext.draw(sourceImage, in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))

func pixelOffset(_ x: Int, _ y: Int) -> Int {
    (y * sourceWidth + x) * 4
}

func backgroundSample(originX: Int, originY: Int) -> (Int, Int, Int) {
    var red = 0
    var green = 0
    var blue = 0
    var count = 0
    for y in 0..<16 {
        for x in 0..<16 {
            let px = min(max(originX + x, 0), sourceWidth - 1)
            let py = min(max(originY + y, 0), sourceHeight - 1)
            let offset = pixelOffset(px, py)
            red += Int(sourcePixels[offset])
            green += Int(sourcePixels[offset + 1])
            blue += Int(sourcePixels[offset + 2])
            count += 1
        }
    }
    return (red / count, green / count, blue / count)
}

let corners = [
    backgroundSample(originX: 0, originY: 0),
    backgroundSample(originX: sourceWidth - 16, originY: 0),
    backgroundSample(originX: 0, originY: sourceHeight - 16),
    backgroundSample(originX: sourceWidth - 16, originY: sourceHeight - 16)
]
let backgroundRed = corners.map(\.0).reduce(0, +) / corners.count
let backgroundGreen = corners.map(\.1).reduce(0, +) / corners.count
let backgroundBlue = corners.map(\.2).reduce(0, +) / corners.count

func backgroundDistance(_ offset: Int) -> Int {
    let red = abs(Int(sourcePixels[offset]) - backgroundRed)
    let green = abs(Int(sourcePixels[offset + 1]) - backgroundGreen)
    let blue = abs(Int(sourcePixels[offset + 2]) - backgroundBlue)
    return max(red, max(green, blue))
}

var minX = sourceWidth
var minY = sourceHeight
var maxX = -1
var maxY = -1

for y in 0..<sourceHeight {
    for x in 0..<sourceWidth {
        let offset = pixelOffset(x, y)
        let red = Int(sourcePixels[offset])
        let green = Int(sourcePixels[offset + 1])
        let blue = Int(sourcePixels[offset + 2])
        if max(red, max(green, blue)) > 80 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
}

guard maxX >= minX, maxY >= minY else {
    fail("No icon content found in \(sourceURL.path)")
}

let margin = 3
let contentWidth = maxX - minX + 1
let contentHeight = maxY - minY + 1
let side = max(contentWidth, contentHeight) + margin * 2
let cropX = max(0, minX - margin - (side - contentWidth) / 2)
let cropY = max(0, minY - margin - (side - contentHeight) / 2)
let cropWidth = min(side, sourceWidth - cropX)
let cropHeight = min(side, sourceHeight - cropY)

let outputPixels = UnsafeMutablePointer<UInt8>.allocate(capacity: cropWidth * cropHeight * 4)
outputPixels.initialize(repeating: 0, count: cropWidth * cropHeight * 4)
defer { outputPixels.deallocate() }

for y in 0..<cropHeight {
    for x in 0..<cropWidth {
        let sourceOffset = pixelOffset(cropX + x, cropY + y)
        let distance = Double(backgroundDistance(sourceOffset))
        let alpha = min(max((distance - 10.0) / 50.0, 0.0), 1.0)
        let outputOffset = (y * cropWidth + x) * 4
        if alpha <= 0.0 {
            continue
        }
        let red = (Double(sourcePixels[sourceOffset]) - (1.0 - alpha) * Double(backgroundRed)) / alpha
        let green = (Double(sourcePixels[sourceOffset + 1]) - (1.0 - alpha) * Double(backgroundGreen)) / alpha
        let blue = (Double(sourcePixels[sourceOffset + 2]) - (1.0 - alpha) * Double(backgroundBlue)) / alpha
        outputPixels[outputOffset] = UInt8(clamping: Int((red * alpha).rounded()))
        outputPixels[outputOffset + 1] = UInt8(clamping: Int((green * alpha).rounded()))
        outputPixels[outputOffset + 2] = UInt8(clamping: Int((blue * alpha).rounded()))
        outputPixels[outputOffset + 3] = UInt8(clamping: Int((alpha * 255.0).rounded()))
    }
}

guard let provider = CGDataProvider(
    data: Data(bytes: outputPixels, count: cropWidth * cropHeight * 4) as CFData
) else {
    fail("Cannot create image data provider")
}

guard let outputImage = CGImage(
    width: cropWidth,
    height: cropHeight,
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    bytesPerRow: cropWidth * 4,
    space: colorSpace,
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    provider: provider,
    decode: nil,
    shouldInterpolate: true,
    intent: .defaultIntent
) else {
    fail("Cannot create output image")
}

guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    fail("Cannot create \(outputURL.path)")
}

CGImageDestinationAddImage(destination, outputImage, nil)

guard CGImageDestinationFinalize(destination) else {
    fail("Cannot write \(outputURL.path)")
}
