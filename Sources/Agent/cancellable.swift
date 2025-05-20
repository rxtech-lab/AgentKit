public actor Cancellable {
    private let cancelAction: () -> Void

    public init(cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction
    }

    public func cancel() {
        cancelAction()
    }
}
