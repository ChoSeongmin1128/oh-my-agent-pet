// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "OhMyAgentPet",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AgentPetCore", targets: ["AgentPetCore"]),
    .library(name: "AgentPetProviders", targets: ["AgentPetProviders"]),
    .library(name: "AgentPetClaude", targets: ["AgentPetClaude"]),
    .executable(name: "OhMyAgentPet", targets: ["OhMyAgentPetApp"]),
    .executable(name: "omapet", targets: ["OmapetCLI"]),
  ],
  targets: [
    .target(name: "AgentPetCore"),
    .target(
      name: "AgentPetProviders",
      dependencies: ["AgentPetCore"]
    ),
    .target(
      name: "AgentPetClaude",
      dependencies: ["AgentPetCore", "AgentPetProviders"]
    ),
    .target(
      name: "AgentPetUI",
      dependencies: ["AgentPetCore"]
    ),
    .target(
      name: "OmapetSupport",
      dependencies: ["AgentPetClaude", "AgentPetCore"]
    ),
    .executableTarget(
      name: "OhMyAgentPetApp",
      dependencies: ["AgentPetClaude", "AgentPetCore", "AgentPetProviders", "AgentPetUI"]
    ),
    .executableTarget(
      name: "OmapetCLI",
      dependencies: ["OmapetSupport"]
    ),
    .testTarget(
      name: "AgentPetCoreTests",
      dependencies: ["AgentPetCore"]
    ),
    .testTarget(
      name: "AgentPetProvidersTests",
      dependencies: ["AgentPetCore", "AgentPetProviders"]
    ),
    .testTarget(
      name: "AgentPetClaudeTests",
      dependencies: ["AgentPetClaude", "AgentPetCore", "AgentPetProviders"]
    ),
    .testTarget(
      name: "AgentPetUITests",
      dependencies: ["AgentPetCore", "AgentPetUI"]
    ),
    .testTarget(
      name: "OmapetSupportTests",
      dependencies: ["OmapetSupport"]
    ),
  ]
)
