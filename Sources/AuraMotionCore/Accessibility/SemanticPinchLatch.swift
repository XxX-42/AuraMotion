/// Pins one already-confirmed semantic identity until contact ends. A missing
/// or invalidated identity can never be converted into a later action.
public struct SemanticPinchLatch<ID: Equatable> {
    public private(set) var isContactActive = false
    public private(set) var identity: ID?
    private var acted = false
    public init() {}
    public mutating func begin(_ confirmed: ID?) {
        guard !isContactActive else { return }
        isContactActive = true; identity = confirmed; acted = false
    }
    public mutating func invalidate() { identity = nil }
    public mutating func takeAction() -> ID? {
        guard isContactActive, !acted else { return nil }
        acted = true; return identity
    }
    public mutating func end() { isContactActive = false; identity = nil; acted = false }
}
