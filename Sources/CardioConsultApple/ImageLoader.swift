import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum StudyInputLoader {
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "bmp", "tif", "tiff", "dcm", "dicom", "dcom"
    ]

    static func load(urls: [URL]) throws -> [LoadedStudyImage] {
        var output: [LoadedStudyImage] = []
        var errors: [String] = []

        for url in urls {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else {
                errors.append(CardioError.unsupportedFile(url.lastPathComponent).localizedDescription)
                continue
            }

            do {
                if ["dcm", "dicom", "dcom"].contains(ext) {
                    let data = try Data(contentsOf: url)
                    output.append(contentsOf: try DicomDecoder.decode(data: data, fileName: url.lastPathComponent))
                } else {
                    output.append(try loadRaster(url: url))
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        if output.isEmpty {
            throw CardioError.dicomDecodeFailed(errors.joined(separator: "\n"))
        }
        return output
    }

    private static func loadRaster(url: URL) throws -> LoadedStudyImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CardioError.imageDecodeFailed(url.lastPathComponent)
        }
        return LoadedStudyImage(
            fileName: url.lastPathComponent,
            frameIndex: 0,
            image: try RGBImage(cgImage: cgImage),
            sourceType: "raster",
            metadata: [:]
        )
    }
}

extension RGBImage {
    init(cgImage: CGImage) throws {
        let width = cgImage.width
        let height = cgImage.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CardioError.imageDecodeFailed("CGContext allocation failed")
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for index in 0..<(width * height) {
            rgb[index * 3] = rgba[index * 4]
            rgb[index * 3 + 1] = rgba[index * 4 + 1]
            rgb[index * 3 + 2] = rgba[index * 4 + 2]
        }
        self.init(width: width, height: height, pixels: rgb)
    }
}

private struct DicomElement {
    let group: Int
    let element: Int
    let vr: String
    let length: Int
    let valueOffset: Int
    let nextOffset: Int
}

private struct DicomMeta {
    var rows = 0
    var columns = 0
    var samplesPerPixel = 1
    var planarConfiguration = 0
    var numberOfFrames = 1
    var bitsAllocated = 8
    var bitsStored = 8
    var pixelRepresentation = 0
    var photometric = ""
    var windowCenter: Double?
    var windowWidth: Double?
    var rescaleSlope = 1.0
    var rescaleIntercept = 0.0
    var pixelOffset = -1
    var pixelLength = 0
    var patientId = ""
    var studyId = ""
    var studyDate = ""
    var studyDescription = ""
    var seriesDescription = ""

    var dictionary: [String: String] {
        [
            "PatientID": patientId,
            "StudyID": studyId,
            "StudyDate": studyDate,
            "StudyDescription": studyDescription,
            "SeriesDescription": seriesDescription,
            "PhotometricInterpretation": photometric
        ].filter { !$0.value.isEmpty }
    }
}

enum DicomDecoder {
    private static let longVR: Set<String> = ["OB", "OD", "OF", "OL", "OV", "OW", "SQ", "UC", "UR", "UT", "UN"]
    private static let validVR: Set<String> = [
        "AE", "AS", "AT", "CS", "DA", "DS", "DT", "FL", "FD", "IS", "LO", "LT", "OB", "OD", "OF",
        "OL", "OV", "OW", "PN", "SH", "SL", "SQ", "SS", "ST", "SV", "TM", "UC", "UI", "UL", "UN",
        "UR", "US", "UT", "UV"
    ]

    static func decode(data: Data, fileName: String) throws -> [LoadedStudyImage] {
        let bytes = [UInt8](data)
        guard bytes.count > 16 else {
            throw CardioError.dicomDecodeFailed("\(fileName): empty DICOM")
        }

        var meta = DicomMeta()
        var offset = hasPreamble(bytes) ? 132 : 0
        var transferSyntax = ""

        if hasPreamble(bytes) {
            var pos = 132
            while let element = readElement(bytes, offset: pos, explicit: true) {
                if element.group != 0x0002 {
                    break
                }
                if element.group == 0x0002 && element.element == 0x0010 {
                    transferSyntax = readString(bytes, element)
                }
                pos = element.nextOffset
            }
            offset = pos
        }

        if !transferSyntax.isEmpty &&
            transferSyntax != "1.2.840.10008.1.2" &&
            transferSyntax != "1.2.840.10008.1.2.1" {
            throw CardioError.dicomDecodeFailed("\(fileName): compressed transfer syntax is not supported in this lightweight Apple build")
        }

        let explicit = transferSyntax == "1.2.840.10008.1.2" ? false : guessExplicit(bytes, offset: offset)
        try parseDataset(bytes, offset: offset, explicit: explicit, meta: &meta)

        guard meta.rows > 0, meta.columns > 0, meta.pixelOffset >= 0, meta.pixelLength > 0 else {
            throw CardioError.dicomDecodeFailed("\(fileName): missing supported pixel data")
        }

        let bytesPerSample = max(meta.bitsAllocated / 8, 1)
        let samples = max(meta.samplesPerPixel, 1)
        let frameBytes = meta.rows * meta.columns * samples * bytesPerSample
        guard frameBytes > 0 else {
            throw CardioError.dicomDecodeFailed("\(fileName): invalid dimensions")
        }

        let availableFrames = max(meta.pixelLength / frameBytes, 1)
        let frameCount = min(max(meta.numberOfFrames, 1), availableFrames)
        var images: [LoadedStudyImage] = []
        for frame in 0..<frameCount {
            let start = meta.pixelOffset + frame * frameBytes
            let image = samples >= 3
                ? rgbBitmap(bytes, start: start, meta: meta)
                : monochromeBitmap(bytes, start: start, meta: meta)
            images.append(
                LoadedStudyImage(
                    fileName: fileName,
                    frameIndex: frame,
                    image: image,
                    sourceType: "dicom",
                    metadata: meta.dictionary
                )
            )
        }
        return images
    }

    private static func parseDataset(_ bytes: [UInt8], offset: Int, explicit: Bool, meta: inout DicomMeta) throws {
        var pos = offset
        while let element = readElement(bytes, offset: pos, explicit: explicit) {
            if element.length == -1 {
                if element.group == 0x7FE0 && element.element == 0x0010 {
                    throw CardioError.dicomDecodeFailed("encapsulated compressed pixel data is not supported")
                }
                pos = max(findUndefinedEnd(bytes, start: element.valueOffset), element.nextOffset)
                continue
            }

            switch (element.group, element.element) {
            case (0x0008, 0x0020): meta.studyDate = readString(bytes, element)
            case (0x0008, 0x1030): meta.studyDescription = readString(bytes, element)
            case (0x0008, 0x103E): meta.seriesDescription = readString(bytes, element)
            case (0x0010, 0x0020): meta.patientId = readString(bytes, element)
            case (0x0020, 0x0010): meta.studyId = readString(bytes, element)
            case (0x0028, 0x0002): meta.samplesPerPixel = readUInt16Value(bytes, element)
            case (0x0028, 0x0004): meta.photometric = readString(bytes, element).uppercased()
            case (0x0028, 0x0006): meta.planarConfiguration = readUInt16Value(bytes, element)
            case (0x0028, 0x0008): meta.numberOfFrames = max(Int(readString(bytes, element)) ?? 1, 1)
            case (0x0028, 0x0010): meta.rows = readUInt16Value(bytes, element)
            case (0x0028, 0x0011): meta.columns = readUInt16Value(bytes, element)
            case (0x0028, 0x0100): meta.bitsAllocated = readUInt16Value(bytes, element)
            case (0x0028, 0x0101): meta.bitsStored = readUInt16Value(bytes, element)
            case (0x0028, 0x0103): meta.pixelRepresentation = readUInt16Value(bytes, element)
            case (0x0028, 0x1050): meta.windowCenter = firstNumber(readString(bytes, element))
            case (0x0028, 0x1051): meta.windowWidth = firstNumber(readString(bytes, element))
            case (0x0028, 0x1052): meta.rescaleIntercept = firstNumber(readString(bytes, element)) ?? 0
            case (0x0028, 0x1053): meta.rescaleSlope = firstNumber(readString(bytes, element)) ?? 1
            case (0x7FE0, 0x0010):
                meta.pixelOffset = element.valueOffset
                meta.pixelLength = element.length
                return
            default:
                break
            }
            pos = element.nextOffset
        }
    }

    private static func monochromeBitmap(_ bytes: [UInt8], start: Int, meta: DicomMeta) -> RGBImage {
        let count = meta.rows * meta.columns
        let bytesPerSample = max(meta.bitsAllocated / 8, 1)
        var values = [Double](repeating: 0, count: count)
        for i in 0..<count {
            values[i] = readSample(bytes, offset: start + i * bytesPerSample, meta: meta) * meta.rescaleSlope + meta.rescaleIntercept
        }

        let low: Double
        let high: Double
        if let center = meta.windowCenter, let width = meta.windowWidth, width > 1 {
            low = center - width / 2
            high = center + width / 2
        } else {
            low = percentile(values, 0.01)
            high = max(percentile(values, 0.99), low + 0.001)
        }

        var rgb = [UInt8](repeating: 0, count: count * 3)
        for i in 0..<count {
            var gray = UInt8(max(0, min(255, Int(((values[i] - low) / max(high - low, 0.001)) * 255))))
            if meta.photometric == "MONOCHROME1" {
                gray = 255 - gray
            }
            rgb[i * 3] = gray
            rgb[i * 3 + 1] = gray
            rgb[i * 3 + 2] = gray
        }
        return RGBImage(width: meta.columns, height: meta.rows, pixels: rgb)
    }

    private static func rgbBitmap(_ bytes: [UInt8], start: Int, meta: DicomMeta) -> RGBImage {
        let count = meta.rows * meta.columns
        let bytesPerSample = max(meta.bitsAllocated / 8, 1)
        var rgb = [UInt8](repeating: 0, count: count * 3)
        for i in 0..<count {
            let offsets: (Int, Int, Int)
            if meta.planarConfiguration == 1 {
                offsets = (
                    start + i * bytesPerSample,
                    start + (count + i) * bytesPerSample,
                    start + (count * 2 + i) * bytesPerSample
                )
            } else {
                let base = start + i * 3 * bytesPerSample
                offsets = (base, base + bytesPerSample, base + bytesPerSample * 2)
            }
            rgb[i * 3] = sampleToByte(bytes, offset: offsets.0, meta: meta)
            rgb[i * 3 + 1] = sampleToByte(bytes, offset: offsets.1, meta: meta)
            rgb[i * 3 + 2] = sampleToByte(bytes, offset: offsets.2, meta: meta)
        }
        return RGBImage(width: meta.columns, height: meta.rows, pixels: rgb)
    }

    private static func readElement(_ bytes: [UInt8], offset: Int, explicit: Bool) -> DicomElement? {
        guard offset + 8 <= bytes.count else { return nil }
        let group = u16(bytes, offset)
        let element = u16(bytes, offset + 2)
        guard group != 0 || element != 0 else { return nil }

        if explicit {
            let vr = ascii(bytes, offset + 4, 2)
            if !validVR.contains(vr) {
                return readElement(bytes, offset: offset, explicit: false)
            }
            if longVR.contains(vr) {
                guard offset + 12 <= bytes.count else { return nil }
                let length = i32(bytes, offset + 8)
                let valueOffset = offset + 12
                return DicomElement(group: group, element: element, vr: vr, length: length, valueOffset: valueOffset, nextOffset: safeNext(valueOffset, length, bytes.count))
            } else {
                let length = u16(bytes, offset + 6)
                let valueOffset = offset + 8
                return DicomElement(group: group, element: element, vr: vr, length: length, valueOffset: valueOffset, nextOffset: safeNext(valueOffset, length, bytes.count))
            }
        } else {
            let length = i32(bytes, offset + 4)
            let valueOffset = offset + 8
            return DicomElement(group: group, element: element, vr: "", length: length, valueOffset: valueOffset, nextOffset: safeNext(valueOffset, length, bytes.count))
        }
    }

    private static func safeNext(_ valueOffset: Int, _ length: Int, _ count: Int) -> Int {
        length == -1 ? valueOffset : min(valueOffset + max(length, 0), count)
    }

    private static func readString(_ bytes: [UInt8], _ element: DicomElement) -> String {
        guard element.length > 0, element.valueOffset < bytes.count else { return "" }
        let end = min(element.valueOffset + element.length, bytes.count)
        let slice = bytes[element.valueOffset..<end]
        return String(bytes: slice, encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0 ").union(.whitespacesAndNewlines)) ?? ""
    }

    private static func readUInt16Value(_ bytes: [UInt8], _ element: DicomElement) -> Int {
        if element.length >= 2, element.valueOffset + 2 <= bytes.count {
            return u16(bytes, element.valueOffset)
        }
        return Int(readString(bytes, element)) ?? 0
    }

    private static func readSample(_ bytes: [UInt8], offset: Int, meta: DicomMeta) -> Double {
        if meta.bitsAllocated <= 8 {
            return Double(offset < bytes.count ? bytes[offset] : 0)
        }
        var raw = u16(bytes, offset)
        if meta.pixelRepresentation == 1 && raw > 32767 {
            raw -= 65536
        }
        return Double(raw)
    }

    private static func sampleToByte(_ bytes: [UInt8], offset: Int, meta: DicomMeta) -> UInt8 {
        if meta.bitsAllocated <= 8 {
            return offset < bytes.count ? bytes[offset] : 0
        }
        let raw = max(u16(bytes, offset), 0)
        let maxValue = max((1 << min(max(meta.bitsStored, 8), 16)) - 1, 255)
        return UInt8(max(0, min(255, Int(Double(raw) / Double(maxValue) * 255))))
    }

    private static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(Double(sorted.count - 1) * p)))
        return sorted[index]
    }

    private static func firstNumber(_ raw: String) -> Double? {
        raw.split(separator: "\\").first.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private static func hasPreamble(_ bytes: [UInt8]) -> Bool {
        bytes.count > 132 && bytes[128] == 68 && bytes[129] == 73 && bytes[130] == 67 && bytes[131] == 77
    }

    private static func guessExplicit(_ bytes: [UInt8], offset: Int) -> Bool {
        guard offset + 6 <= bytes.count else { return true }
        return validVR.contains(ascii(bytes, offset + 4, 2))
    }

    private static func findUndefinedEnd(_ bytes: [UInt8], start: Int) -> Int {
        var pos = start
        while pos + 8 <= bytes.count {
            if u16(bytes, pos) == 0xFFFE && u16(bytes, pos + 2) == 0xE0DD {
                return pos + 8
            }
            pos += 2
        }
        return bytes.count
    }

    private static func ascii(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> String {
        guard offset >= 0, offset + length <= bytes.count else { return "" }
        return String(bytes: bytes[offset..<(offset + length)], encoding: .ascii) ?? ""
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int {
        guard offset + 1 < bytes.count else { return 0 }
        return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private static func i32(_ bytes: [UInt8], _ offset: Int) -> Int {
        guard offset + 3 < bytes.count else { return 0 }
        let value = Int32(bitPattern:
            UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
        )
        return Int(value)
    }
}

