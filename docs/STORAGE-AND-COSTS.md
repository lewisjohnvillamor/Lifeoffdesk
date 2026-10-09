# Life Off Desk — storage and operating costs

## Separate storage from runtime memory

Model download size is not peak RAM. Inference also allocates context/cache/runtime buffers. The map renderer, GPS history and photos share the phone's memory/storage budget. Test on iPhone 12 Pro Max before selecting a larger model.

| Component | Initial planning approach | Required measurement |
| --- | --- | --- |
| App and runtime | Small native app, one inference runtime | Installed app and binary bytes |
| Model | Start with a small compatible artifact; Qwen3-0.6B Q8 publisher listing is about 639 MB | Actual downloaded bytes, hash, load time, peak RAM |
| Starter map/catalog | One small neighborhood, 15–30 real places, simple vector context | Exact region/data bytes and coverage bounds |
| Exploration/history | Segmented accepted fixes, incremental snapshots; compact render cache | Bytes after several real walks; ensure growth is bounded |
| Photos (P1) | Save a reasonable display copy; avoid storing full duplicates unnecessarily | Per-photo bytes; user-controlled deletion |
| Downloads/updates | Validate checksums; atomic replacement may temporarily require both versions | Free space needed during provisioning/update |

Aim for a starter installation below 2 GB as a provisional engineering target. This is not a measured requirement or a promise for full Luzon. Do not reserve a multi-gigabyte Luzon pack until detail level and source data are chosen.

## Cost assumptions

On-device inference has no per-request cloud-model bill in the proposed architecture. Development still uses existing hardware, electricity and download bandwidth. Map/data distribution or hosted updates could add costs later. No server, subscription backend or analytics service is required for this slice.

Physical-device signing and App Store distribution are different tasks. Verify the current Apple account/distribution requirements when choosing how judges/testers receive the app; no account fee estimate has been validated in this package. The first build plan assumes local installation through Xcode.

Do not purchase a cloud inference subscription to satisfy phone-only Local AI. Record every new paid dependency before adding it. Monetization is an open product decision and should not delay the first evidence.
