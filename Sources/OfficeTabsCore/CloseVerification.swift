import Foundation

/// An accepted native action is only a request. Observable effects decide the
/// result; the caller never retries automatically or answers the native prompt.
public struct CloseVerifier {
    public enum Result: Equatable { case waiting, nativePrompt, closed, unconfirmed }
    public let deadline: TimeInterval
    public init(deadline:TimeInterval) { self.deadline = deadline }
    public func evaluate(targetInvalid:Bool,nativePrompt:Bool,now:TimeInterval) -> Result {
        if nativePrompt { return .nativePrompt }
        if targetInvalid { return .closed }
        return now < deadline ? .waiting : .unconfirmed
    }
}
