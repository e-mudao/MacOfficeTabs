import Foundation

public enum CandidateAssociationPolicy {
    /// Unchanged focus cannot establish a new association among multiple native
    /// menu candidates, even if AX exposes just one fullscreen window.
    public static func permits(previousFocus:UUID?,actualFocus:UUID,associated:UUID?,
                               soleCandidateBefore:Bool,soleCandidateAfter:Bool,
                               windowsBefore:[UUID],windowsAfter:[UUID]) -> Bool {
        if actualFocus != previousFocus || associated == actualFocus { return true }
        return soleCandidateBefore && soleCandidateAfter && windowsBefore == [actualFocus] && windowsAfter == [actualFocus]
    }
}
