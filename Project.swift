import ProjectDescription

let sharedSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": "K5TW9AU245",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
]

let project = Project(
    name: "OnDeviceAppBuilder",
    organizationName: "buberlo",
    settings: .settings(base: sharedSettings),
    targets: [
        .target(
            name: "BuilderCore",
            destinations: [.iPhone, .iPad, .mac],
            product: .framework,
            bundleId: "dev.buberlo.ondeviceappbuilder.core",
            deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
            infoPlist: .default,
            sources: ["Modules/BuilderCore/Sources/**"],
            dependencies: []
        ),
        .target(
            name: "BuilderCoreTests",
            destinations: [.iPhone, .iPad, .mac],
            product: .unitTests,
            bundleId: "dev.buberlo.ondeviceappbuilder.core-tests",
            deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
            infoPlist: .default,
            sources: ["Modules/BuilderCore/Tests/**"],
            dependencies: [.target(name: "BuilderCore")]
        ),
        .target(
            name: "PhoneBuilder",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.buberlo.ondeviceappbuilder.ios",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Phone Builder",
                "NSLocalNetworkUsageDescription": "Phone Builder connects to your trusted Mac to create, test, sign, and install your projects.",
                "NSBonjourServices": ["_phonebuilder._tcp"],
                "UILaunchScreen": [:],
            ]),
            sources: ["Apps/PhoneBuilder/Sources/**"],
            resources: ["Apps/PhoneBuilder/Resources/**"],
            dependencies: [.target(name: "BuilderCore")],
            settings: .settings(base: [
                "TARGETED_DEVICE_FAMILY": "1,2",
            ])
        ),
        .target(
            name: "PhoneBuilderTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.buberlo.ondeviceappbuilder.ios-tests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Apps/PhoneBuilder/Tests/**"],
            dependencies: [.target(name: "PhoneBuilder")]
        ),
        .target(
            name: "PhoneBuilderUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "dev.buberlo.ondeviceappbuilder.ios-ui-tests",
            deploymentTargets: .iOS("26.0"),
            infoPlist: .default,
            sources: ["Apps/PhoneBuilder/UITests/**"],
            dependencies: [.target(name: "PhoneBuilder")]
        ),
        .target(
            name: "BuilderHost",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.buberlo.ondeviceappbuilder.host",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Builder Host",
                "LSUIElement": true,
                "NSLocalNetworkUsageDescription": "Builder Host accepts encrypted build requests from your paired iPhone or iPad.",
                "NSBonjourServices": ["_phonebuilder._tcp"],
            ]),
            sources: ["Apps/BuilderHost/Sources/**"],
            resources: ["Apps/BuilderHost/Resources/**"],
            dependencies: [.target(name: "BuilderCore")],
            settings: .settings(base: [
                "ENABLE_APP_SANDBOX": "NO",
                "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
            ])
        ),
        .target(
            name: "BuilderHostTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.buberlo.ondeviceappbuilder.host-tests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            sources: ["Apps/BuilderHost/Tests/**"],
            dependencies: [.target(name: "BuilderHost")]
        ),
    ]
)
