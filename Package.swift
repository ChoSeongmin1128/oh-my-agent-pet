// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "OhMyAgentPet",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AgentPetCore", targets: ["AgentPetCore"]),
    .library(name: "AgentPetSprites", targets: ["AgentPetSprites"]),
    .library(name: "AgentPetEvents", targets: ["AgentPetEvents"]),
    .library(name: "AgentPetNavigation", targets: ["AgentPetNavigation"]),
    .library(name: "AgentPetProviders", targets: ["AgentPetProviders"]),
    .library(name: "AgentPetClaude", targets: ["AgentPetClaude"]),
    .library(name: "AgentPetCodex", targets: ["AgentPetCodex"]),
    .executable(name: "OhMyAgentPet", targets: ["OhMyAgentPetApp"]),
    .executable(name: "omapet", targets: ["OmapetCLI"]),
  ],
  targets: [
    .target(name: "AgentPetCore"),
    .target(name: "AgentPetSprites"),
    .target(name: "AgentPetEvents"),
    .target(
      name: "AgentPetNavigation",
      dependencies: ["AgentPetCore"]
    ),
    .target(
      name: "AgentPetProviders",
      dependencies: ["AgentPetCore"]
    ),
    .target(
      name: "AgentPetClaude",
      dependencies: ["AgentPetCore", "AgentPetEvents", "AgentPetProviders"]
    ),
    .target(
      name: "AgentPetCodex",
      dependencies: ["AgentPetCore", "AgentPetEvents", "AgentPetProviders"]
    ),
    .target(
      name: "AgentPetUI",
      dependencies: ["AgentPetCore", "AgentPetSprites"]
    ),
    .target(
      name: "OmapetSupport",
      dependencies: ["AgentPetClaude", "AgentPetCodex", "AgentPetCore", "AgentPetEvents"]
    ),
    .executableTarget(
      name: "OhMyAgentPetApp",
      dependencies: [
        "AgentPetClaude", "AgentPetCodex", "AgentPetCore", "AgentPetNavigation",
        "AgentPetProviders", "AgentPetSprites", "AgentPetUI",
      ]
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
      name: "AgentPetSpritesTests",
      dependencies: ["AgentPetSprites"]
    ),
    .testTarget(
      name: "AgentPetEventsTests",
      dependencies: ["AgentPetEvents"]
    ),
    .testTarget(
      name: "AgentPetNavigationTests",
      dependencies: ["AgentPetCore", "AgentPetNavigation"]
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
      name: "AgentPetCodexTests",
      dependencies: ["AgentPetCodex", "AgentPetCore", "AgentPetProviders"]
    ),
    .testTarget(
      name: "AgentPetUITests",
      dependencies: ["AgentPetCore", "AgentPetSprites", "AgentPetUI"]
    ),
    .testTarget(
      name: "OmapetSupportTests",
      dependencies: ["OmapetSupport"]
    ),
  ]
)
