import Foundation

/// Observable state for the "download this area" prompt. Backed by OMMapDownloader,
/// which reports the region under the viewport and its download status/progress.
final class MapDownloadModel: NSObject, ObservableObject, OMMapDownloaderDelegate {
  @Published var countryId: String = ""
  @Published var name: String = ""
  @Published var status: OMDownloadStatus = .none
  @Published var sizeBytes: UInt64 = 0
  @Published var downloadedBytes: Int64 = 0
  @Published var totalBytes: Int64 = 0

  private let downloader = OMMapDownloader()

  override init() {
    super.init()
    downloader.delegate = self
  }

  func start() {
    downloader.start()
  }

  func download() {
    guard !countryId.isEmpty else { return }
    downloader.downloadCountry(countryId)
  }

  func cancel() {
    guard !countryId.isEmpty else { return }
    downloader.cancelCountry(countryId)
  }

  func retry() {
    guard !countryId.isEmpty else { return }
    downloader.retryCountry(countryId)
  }

  var progressFraction: Double {
    guard totalBytes > 0 else { return 0 }
    return min(1.0, Double(downloadedBytes) / Double(totalBytes))
  }

  // MARK: - OMMapDownloaderDelegate

  func mapAreaDidChange(forCountry countryId: String, name: String, status: OMDownloadStatus, sizeBytes: UInt64) {
    self.countryId = countryId
    self.name = name
    self.status = status
    self.sizeBytes = sizeBytes
    if status != .downloading && status != .inQueue {
      downloadedBytes = 0
      totalBytes = 0
    }
  }

  func mapDownloadProgress(forCountry countryId: String, downloaded: Int64, total: Int64) {
    guard countryId == self.countryId else { return }
    downloadedBytes = downloaded
    totalBytes = total
  }
}
