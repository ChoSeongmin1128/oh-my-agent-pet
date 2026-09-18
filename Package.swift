// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "OhMyAgentPet",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "AgentPetCore", targets: ["AgentPetCore"]),
    .library(name: "AgentPetInfrastructure", targets: ["AgentPetInfrastructure"]),
    .library(name: "AgentPetSprites", targets: ["AgentPetSprites"]),
    .library(name: "AgentPetLibrary", targets: ["AgentPetLibrary"]),
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
    .target(name: "AgentPetInfrastructure"),
    .target(name: "AgentPetSprites"),
    .target(
      name: "AgentPetLibrary",
      dependencies: ["AgentPetSprites"]
    ),
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
      dependencies: [
        "AgentPetCore", "AgentPetEvents", "AgentPetInfrastructure", "AgentPetProviders",
      ]
    ),
    .target(
      name: "AgentPetCodex",
      dependencies: [
        "AgentPetCore", "AgentPetEvents", "AgentPetInfrastructure", "AgentPetProviders",
      ]
    ),
    .target(
      name: "AgentPetUI",
      dependencies: ["AgentPetCore", "AgentPetLibrary", "AgentPetSprites"]
    ),
    .target(
      name: "OmapetSupport",
      dependencies: [
        "AgentPetClaude", "AgentPetCodex", "AgentPetCore", "AgentPetEvents", "AgentPetLibrary",
      ]
    ),
    .executableTarget(
      name: "OhMyAgentPetApp",
      dependencies: [
        "AgentPetClaude", "AgentPetCodex", "AgentPetCore", "AgentPetLibrary",
        "AgentPetNavigation", "AgentPetProviders", "AgentPetSprites", "AgentPetUI",
      ]
    ),
    .target(
      name: "AgentPetTestSupport",
      dependencies: ["AgentPetSprites"],
      path: "Tests/AgentPetTestSupport"
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
      name: "AgentPetInfrastructureTests",
      dependencies: ["AgentPetInfrastructure"]
    ),
    .testTarget(
      name: "AgentPetSpritesTests",
      dependencies: ["AgentPetSprites", "AgentPetTestSupport"]
    ),
    .testTarget(
      name: "AgentPetLibraryTests",
      dependencies: ["AgentPetLibrary", "AgentPetSprites", "AgentPetTestSupport"]
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
      dependencies: [
        "AgentPetCore", "AgentPetLibrary", "AgentPetSprites", "AgentPetTestSupport", "AgentPetUI",
      ]
    ),
    .testTarget(
      name: "OmapetSupportTests",
      dependencies: ["AgentPetTestSupport", "OmapetSupport"]
    ),
  ]
)
