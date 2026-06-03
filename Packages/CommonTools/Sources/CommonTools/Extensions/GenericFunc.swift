import Foundation

func isolatedPerform<A: Actor, Result: Sendable>(
    _ actor: A,
    block: @Sendable (isolated A) throws -> Result
) async rethrows -> Result {
    try await block(actor)
}
