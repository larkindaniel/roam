import Foundation
import MapKit

/// One-shot async wrapper around `MKLocalSearchCompleter`, restricted to localities so a query like
/// "Portland" returns each same-name city as its own labelled suggestion.
@MainActor
final class DestinationCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[MKLocalSearchCompletion], Error>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: [.locality])
        // Towns near you come first, as in Apple Maps.
        if let nearby = MapKitPlaceSearchProvider.nearbyRegion() { completer.region = nearby }
    }

    func completions(for query: String) async throws -> [MKLocalSearchCompletion] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.completer.queryFragment = query
            }
        } onCancel: {
            Task { @MainActor in
                self.completer.cancel()
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<[MKLocalSearchCompletion], Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        // Discover's search: how long the query was and how many places came back, never the words.
        Log.action("search.destinations", ["query_length": "\(completer.queryFragment.count)", "results": "\(results.count)"])
        Task { @MainActor in self.finish(.success(results)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Log.error("search.destinations", error)
        Task { @MainActor in self.finish(.failure(error)) }
    }
}
