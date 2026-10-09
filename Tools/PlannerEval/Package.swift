// swift-tools-version:5.9
import PackageDescription

// Development diagnostic: runs the app's LlamaEngine and planner against the pinned model on
// a Mac or Linux machine. Results are NOT iPhone evidence. Build via scripts/run_planner_eval.sh.
let package = Package(
    name: "PlannerEval",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/LifeOffDeskCore")],
    targets: [
        .systemLibrary(name: "llama", path: "Sources/llama"),
        .executableTarget(name: "planner-eval",
                          dependencies: ["llama", .product(name: "LifeOffDeskCore", package: "LifeOffDeskCore")],
                          path: "Sources/PlannerEval"),
    ]
)
