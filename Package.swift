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
      name: "AgentPetUI",
      dependencies: ["AgentPetCore"]
    ),
    .target(
      name: "OmapetSupport",
      dependencies: ["AgentPetCore"]
    ),
    .executableTarget(
      name: "OhMyAgentPetApp",
      dependencies: ["AgentPetCore", "AgentPetProviders", "AgentPetUI"]
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
      name: "OmapetSupportTests",
      dependencies: ["OmapetSupport"]
    ),
  ]
)
