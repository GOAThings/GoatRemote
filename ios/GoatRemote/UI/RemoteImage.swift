import ImageIO
import OSLog
import RemoteCore
import SwiftUI
import UIKit

/// Uma imagem da rede (banners do GoatLauncher, ícones da App Store, logótipos do GoatTV), guardada em memória. O
/// AsyncImage cancelava os pedidos dentro da grelha das apps e ficava sem imagem.
struct RemoteImage<Content: View>: View {
    let url: URL
    /// Os logótipos dos canais têm limites mais pequenos do que os banners.
    var limit = 4 << 20
    var maxPixelSize = 1024
    @ViewBuilder let content: (Image?) -> Content
    @State private var image: UIImage?

    var body: some View {
        content(image.map { Image(uiImage: $0) })
            .task(id: url) {
                if let cached = Self.cache.object(forKey: url as NSURL) {
                    image = cached
                    return
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let side = maxPixelSize
                do {
                    let (data, status) = try await BoundedHTTP.get(request, limit: limit)
                    let decoded = await Task.detached(priority: .userInitiated) { ImageCache.decode(data, maxPixelSize: side) }.value
                    guard status == 200, let loaded = decoded else {
                        imageLog.error("\(url.absoluteString, privacy: .public): \(status) \(data.count) bytes")
                        return
                    }
                    Self.cache.setObject(loaded, forKey: url as NSURL, cost: Int(loaded.size.width * loaded.size.height) * 4)
                    image = loaded
                } catch {
                    imageLog.error("\(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
    }

    private static var cache: NSCache<NSURL, UIImage> { ImageCache.shared }
}

private let imageLog = Logger(subsystem: "cc.slokker.goatremote", category: "images")

private enum ImageCache {
    nonisolated(unsafe) static let shared: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 32 << 20
        return cache
    }()

    /// Lê primeiro o tamanho e reduz o que for maior do que alguma vez se mostra.
    static func decode(_ data: Data, maxPixelSize: Int = 1024) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
    }
}
