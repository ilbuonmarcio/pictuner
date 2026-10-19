import Foundation

struct PreviewRequest: Equatable {
    let url: URL
    let adjustments: Adjustments
    let longEdge: Double
}

/// One render in flight and one replaceable pending value. Continuous input never postpones
/// starting a frame or discards every completed frame; changing photos invalidates the session.
@MainActor
final class PreviewCoordinator {
    typealias Render = (PreviewRequest) throws -> PreviewResult
    var onResult: ((PreviewRequest, Result<PreviewResult, Error>, Bool) -> Void)?
    private let queue = DispatchQueue(label: "pictuner.preview", qos: .userInitiated)
    private let render: Render
    private var pending: PreviewRequest?
    private var inFlight = false
    private var generation = UUID()

    init(render: @escaping Render) { self.render = render }

    func invalidate() {
        generation = UUID()
        pending = nil
    }

    func request(_ request: PreviewRequest) {
        pending = request
        startNext()
    }

    private func startNext() {
        guard !inFlight, let request = pending else { return }
        pending = nil
        inFlight = true
        let token = generation
        let render = render
        queue.async { [weak self] in
            let result = autoreleasepool { Result { try render(request) } }
            // NSSlider tracks the mouse in an event-tracking run loop. A normal main-queue
            // callback may wait for mouse-up; common modes also deliver frames during tracking.
            RunLoop.main.perform(inModes: [.common]) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.inFlight = false
                    if self.generation == token {
                        self.onResult?(request, result, self.pending == nil)
                    }
                    self.startNext()
                }
            }
        }
    }
}
