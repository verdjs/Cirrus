// CachedRemoteImage.swift
// Defines cached remote image for the Shared / Components surface.
//

import SwiftUI
import UIKit
import CloudXCore

/// Shared SwiftUI image view that bridges view-driven artwork identity to the actor-backed
/// remote image pipeline and only updates displayed artwork when the cache identity changes.
struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    var kind: ArtworkKind = .poster
    var priority: ArtworkPriority = .normal
    var maxPixelSize: CGFloat? = nil
    var contentMode: ContentMode = .fill
    var analyzeLuminance: Bool = false
    var onImageLoaded: (() -> Void)? = nil
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var displayKey: String?

    init(
        url: URL?,
        kind: ArtworkKind = .poster,
        priority: ArtworkPriority = .normal,
        maxPixelSize: CGFloat? = nil,
        contentMode: ContentMode = .fill,
        analyzeLuminance: Bool = false,
        onImageLoaded: (() -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.kind = kind
        self.priority = priority
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.analyzeLuminance = analyzeLuminance
        self.onImageLoaded = onImageLoaded
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .onAppear {
                        if displayKey == cacheIdentity {
                            onImageLoaded?()
                        }
                    }
            } else {
                placeholder()
            }
        }
        .task(id: cacheIdentity) {
            await loadImage()
        }
    }

    /// Includes URL, artwork role, and decode-size hint so differently sized uses of the same
    /// remote asset do not trample each other's cached display state.
    private var cacheIdentity: String {
        "\(url?.absoluteString ?? "nil")|\(kind.rawValue)|\(maxPixelSize.map { String(Int($0)) } ?? "full")"
    }

    /// Clears stale displayed artwork before awaiting a replacement so reused SwiftUI cells do
    /// not briefly show the wrong remote image.
    private func loadImage() async {
        guard let url else {
            await MainActor.run {
                clearImage()
            }
            return
        }
        let cacheKey = cacheIdentity
        if let cached = await RemoteImagePipeline.shared.cachedImage(for: cacheKey) {
            await MainActor.run {
                displayImage(cached, for: cacheKey)
            }
            return
        }

        await MainActor.run {
            clearImageIfDisplayingDifferentKey(cacheKey)
        }

        guard let loaded = await RemoteImagePipeline.shared.image(
            for: ArtworkRequest(url: url, kind: kind, priority: priority),
            cacheKey: cacheKey,
            maxPixelSize: maxPixelSize
        ) else {
            return
        }

        await MainActor.run {
            displayImage(loaded, for: cacheKey)
        }
    }

    @MainActor
    private func clearImage() {
        image = nil
        displayKey = nil
    }

    @MainActor
    private func clearImageIfDisplayingDifferentKey(_ cacheKey: String) {
        guard displayKey != cacheKey else { return }
        image = nil
    }

    @MainActor
    private func displayImage(_ image: UIImage, for cacheKey: String) {
        self.image = image
        displayKey = cacheKey
        onImageLoaded?()
        
        guard analyzeLuminance else { return }
        
        // Analyze image top luminance asynchronously and post notification
        let activeURL = url
        Task {
            let isLight = await image.calculateIsTopLight()
            NotificationCenter.default.post(
                name: .heroBackgroundLuminanceChanged,
                object: nil,
                userInfo: ["isLight": isLight, "url": activeURL as Any]
            )
        }
    }
}

extension Notification.Name {
    static let heroBackgroundLuminanceChanged = Notification.Name("heroBackgroundLuminanceChanged")
}

extension UIImage {
    /// Asynchronously calculates if the top 20% of the image is light or dark.
    func calculateIsTopLight() async -> Bool {
        // Run on a background actor/thread to keep the UI butter-smooth
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = self.cgImage else { return false }
            
            let width = cgImage.width
            let height = cgImage.height
            // We analyze the top 20% of the image
            let topSectionHeight = max(1, height / 5)
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            let rawDataSize = bytesPerRow * topSectionHeight
            
            var rawData = [UInt8](repeating: 0, count: rawDataSize)
            
            guard let context = CGContext(
                data: &rawData,
                width: width,
                height: topSectionHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                return false
            }
            
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: topSectionHeight))
            
            var totalLuminance: Double = 0.0
            
            // Sample pixels (every 4th pixel) to perform the check extremely fast
            let step = bytesPerPixel * 4
            var sampledPixels = 0
            
            for i in stride(from: 0, to: rawDataSize, by: step) {
                let r = Double(rawData[i]) / 255.0
                let g = Double(rawData[i+1]) / 255.0
                let b = Double(rawData[i+2]) / 255.0
                
                // Perceived luminance formula (ITU-R BT.601)
                let luminance = 0.299 * r + 0.587 * g + 0.114 * b
                totalLuminance += luminance
                sampledPixels += 1
            }
            
            guard sampledPixels > 0 else { return false }
            let averageLuminance = totalLuminance / Double(sampledPixels)
            
            // Threshold 0.5 indicates light background
            return averageLuminance > 0.5
        }.value
    }
}
