# Implementation sources

Checked 2026-10-09. These sources support candidate tooling/data planning; none verifies performance on this project's phone.

- llama.cpp XCFramework official documentation: https://github.com/ggml-org/llama.cpp/blob/master/docs/xcframework.md — documents iOS/Swift integration. Select and pin an actual compatible release/checksum; the documentation's example release is not automatically the right build.
- llama.cpp official SwiftUI example: https://github.com/ggml-org/llama.cpp/blob/master/examples/llama.swiftui/README.md — integration reference, not a finished Life Off Desk app.
- Qwen publisher Qwen3-0.6B GGUF card: https://huggingface.co/Qwen/Qwen3-0.6B-GGUF — candidate model; its listing shows Q8_0 around 639 MB and Apache-2.0 metadata. iPhone speed/memory/intent quality remain unmeasured. It supports non-thinking mode; use the appropriate template/settings, bounded output and device testing.
- Apple Core Location background handling: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background — check exact API availability and background configuration for the phone's installed iOS.
- Apple efficient location usage: https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently — guide to energy-aware location collection.
- OpenStreetMap attribution/license reference: https://www.openstreetmap.org/copyright — check actual dataset and distribution obligations before bundling map/place data.

Proposed first runtime/model experiment: pinned llama.cpp iOS integration + a small Qwen3-0.6B compatible GGUF artifact. This is an engineering candidate rather than a compatibility/performance guarantee. Other small models may be compared if the first candidate misses the device budget. Do not expand the model search until the early spike supplies evidence.
