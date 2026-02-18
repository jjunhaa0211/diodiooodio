// swift-tools-version: 6.2
// 첫 줄 주석은 이 패키지를 빌드할 최소 도구 버전을 지정합니다.

import PackageDescription

let package = Package(
    name: "odioodiodio",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "odioodiodio", targets: ["odioodiodio"]),
    ],
    targets: [
        .executableTarget(
            name: "odioodiodio"
        ),
    ]
)
