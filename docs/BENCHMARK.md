# Flova Transfer Benchmarks

Measured on: Realme RMX3853 (phone hotspot, 5 GHz) <-> Windows laptop over Wi-Fi.
Protocol: WebSocket, 4 MB segments, per-segment ack, adaptive worker pool (2-8).

| Date | Phase | Mode | Avg | Peak | Notes |
|------|-------|------|-----|------|-------|
| 2026-09 | 8 | sequential, 1 worker, 4 MB chunks | 25 MB/s | ~25 MB/s | stop-and-wait per segment |
| 2026-09 | 9 | parallel, adaptive 2-8 workers | 40 MB/s | 51 MB/s | AIMD concurrency control |

Reference points:
- 1 GB file at 40 MB/s average ≈ 25 s end-to-end.
- Link ceiling: 5 GHz hotspot practical payload ≈ 320-400 Mbps; Flova saturates it.

Observations:
- Average trails peak due to worker ramp-up (~4-6 s), TCP slow start, and transfer tail.
- Large files (>= 1 GB) show averages closest to peak; small files are ramp-dominated.
- Single TCP stream is a deliberate limit; multi-socket gains estimated < 20% for
  significantly higher complexity. Not pursued.