import Foundation

public struct TaskIdentity: Codable, Hashable, Sendable {
  public let provider: ProviderIdentifier
  public let profileID: String
  public let dataRoot: String
  public let taskID: String
  public let executionID: String
  public let turnID: String

  public init(
    provider: ProviderIdentifier,
    profileID: String,
    dataRoot: String,
    taskID: String,
    executionID: String,
    turnID: String
  ) {
    self.provider = provider
    self.profileID = profileID
    self.dataRoot = dataRoot
    self.taskID = taskID
    self.executionID = executionID
    self.turnID = turnID
  }

  public var stableKey: String {
    [provider.rawValue, profileID, dataRoot, taskID, executionID, turnID]
      .joined(separator: "\u{1F}")
  }
}
