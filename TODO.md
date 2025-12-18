# TODO - Example => Video-Editor Merge-Test



# TODO – Video Merging Integration-Tests

## Goal
Ensure reliable, deterministic video merging across all supported native platforms by validating
behavior under varying codecs, resolutions, durations, and audio configurations.

---

## General Test Matrix (All Platforms)

### Video Properties
- [ ] Same resolution / same codec / same framerate (baseline case)
- [ ] Different resolutions (e.g. 720p → 1080p)
- [ ] Different aspect ratios (16:9, 9:16, 1:1)
- [ ] Different frame rates (24 / 30 / 60 fps)
- [ ] Different bitrates (low / medium / high)
- [ ] Different durations (short + long clips)
- [ ] Mixed orientation (portrait + landscape)
- [ ] Clips with rotation metadata vs baked rotation

### Video Codecs
- [ ] H.264 (Baseline / Main / High)
- [ ] HEVC / H.265 (where supported)
- [ ] Verify fallback behavior for unsupported codecs

### Audio Properties
- [ ] Same audio codec (AAC → AAC)
- [ ] Different audio codecs (AAC → Opus / MP3)
- [ ] Different sample rates (44.1kHz / 48kHz)
- [ ] Different channel layouts (mono / stereo)
- [ ] One clip without audio
- [ ] All clips without audio
- [ ] Mismatched audio bitrates

### Timing & Sync
- [ ] Audio/video sync preserved after merge
- [ ] No audio gaps or overlaps at clip boundaries
- [ ] Accurate total duration
- [ ] Frame-accurate transition between clips

---


## Cross-Platform Validation

- [ ] Stress test long-running exports
- [ ] Large file merge (>1GB total duration)
- [ ] Compare duration and frame counts across platforms

---

## Tooling & Automation

- [ ] Create a reusable test video asset pack
- [ ] Automate merge tests in CI where possible
- [ ] Add logging for:
  - Codec selection
  - Re-encode vs passthrough decisions
  - Export timing and failures

---

## Nice-to-Have

- [ ] Performance benchmarks (time, CPU, memory)
- [ ] Progress reporting accuracy tests
