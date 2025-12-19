# TODO - FIX-Tests
- Android
 - [ ] Test: Merge video without audio (D) and video with audio (A)


# TODO – Video Merging Integration-Tests

## Goal
Ensure reliable, deterministic video merging across all supported native platforms by validating
behavior under varying codecs, resolutions, durations, and audio configurations.

---

## General Test Matrix (All Platforms)

### Video Properties
- [x] Same resolution / same codec / same framerate (baseline case)
- [x] Different resolutions (e.g. 720p → 1080p)
- [x] Different aspect ratios (16:9, 9:16, 1:1)
- [x] Different frame rates (24 / 30 / 60 fps)
- [ ] Different bitrates (low / medium / high)
- [x] Different durations (short + long clips)
- [x] Mixed orientation (portrait + landscape)
- [x] Clips with rotation metadata vs baked rotation

### Video Codecs
- [x] H.264 (Baseline / Main / High)
- [x] HEVC / H.265 (where supported)
- [x] Verify fallback behavior for unsupported codecs

### Audio Properties
- [x] Same audio codec (AAC → AAC)
- [ ] Different audio codecs (AAC → Opus / MP3)
- [x] Different sample rates (44.1kHz / 48kHz)
- [x] Different channel layouts (mono / stereo)
- [x] One clip without audio
- [x] All clips without audio
- [ ] Mismatched audio bitrates

### Timing & Sync
- [x] Audio/video sync preserved after merge
- [x] No audio gaps or overlaps at clip boundaries
- [x] Accurate total duration
- [x] Frame-accurate transition between clips

---

## Cross-Platform Validation

- [ ] Stress test long-running exports
- [ ] Large file merge (>1GB total duration)
- [x] Compare duration and frame counts across platforms


---

## Nice-to-Have

- [ ] Performance benchmarks (time, CPU, memory)
- [x] Progress reporting accuracy tests
