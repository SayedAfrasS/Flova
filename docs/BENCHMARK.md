# Flova Transfer Benchmarks

Measured on: Realme RMX3853 (phone hotspot, 5 GHz) <-> Windows laptop over Wi-Fi.
Protocol: WebSocket, 4 MB segments, per-segment ack, adaptive worker pool (2-8),
SHA-256 per segment + whole-file (native hardware-accelerated on Android).

| Date | Phase | Mode | Avg | Peak | Notes |
|------|-------|------|-----|------|-------|
| 2026-09 | 8 | sequential, 1 worker, 4 MB chunks | 25 MB/s | ~25 MB/s | stop-and-wait per segment |
| 2026-09 | 9 | parallel, adaptive 2-8 workers | 40 MB/s | 51 MB/s | AIMD concurrency control |
| 2026-09 | 10 | parallel + native SHA-256 verification | 35 MB/s (3.6 GB sustained) | - | whole-file check 7 s for 3.6 GB (~514 MB/s hash) |

Reference points:
- 3.6 GB end-to-end ≈ 1 min 50 s including integrity verification.
- Link ceiling: 5 GHz hotspot practical payload ≈ 320-400 Mbps; Flova saturates it.
- Sustained transfers settle below short-burst peaks due to thermal throttling
  and flash write-cache saturation on the phone. Expected hardware behavior.

Observations:
- Average trails peak due to worker ramp-up (~4-6 s), TCP slow start, and transfer tail.
- Large sustained files show throttle-limited averages; small files are ramp-dominated.
- Pure Dart SHA-256 (~30-40 MB/s) made Phase 10 hash-bound; moving hashing to the
  Android MethodChannel (MessageDigest) restored link-bound throughput.
- Single TCP stream is a deliberate limit; multi-socket gains estimated < 20% for
  significantly higher complexity. Not pursued.