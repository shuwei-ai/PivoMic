# Local accompaniment engine

ONNX Runtime 1.16.3 for OHOS arm64 is checked into `entry/libs/arm64-v8a`, so a
normal build does not download dependencies. `scripts/setup_separation_runtime.py`
can reproduce that binary from sherpa-onnx v1.13.7's pinned release archive and
verifies its SHA-256. Only the MIT-licensed runtime is linked; sherpa's source
separation implementation is not linked. ORT headers and license are in
`third_party/onnxruntime`.

The model is bundled at resources/rawfile/uvr-inst-main.onnx, copied locally on first use and verified by SeparationModelService. No runtime model download is performed. Inst_Main
source SHA-256: 628d621d64a06237949de109571cad488c977ab1b34f53d852428d44e492f198.
Original UVR tail MD5 after removing the added ONNX metadata:
1c56ec0224f1d559c42fd6fd2a67b154. Original configuration is **Instrumental**, FFT 5120,
256 time frames, 2048 bins, hop 1024, compensation 1.025. Converted model embeds
FFT 4096; do not use that value. Reference:
https://github.com/Anjok07/ultimatevocalremovergui/blob/master/models/MDX_Net_Models/model_data/model_data.json

The implementation uses centered periodic-Hann STFT, drops bins 0–2 before
inference and restores the omitted high bins as zeros. Bounded overlapping windows
are reconstructed with weighted overlap-add and written as 44.1 kHz stereo PCM16.
Optional sign-denoise/ensemble inference is not enabled. This is not a guarantee of
sample-identical UVR GUI output. The existing decoder is reused through a disk sink
and an explicit target sample rate; no renderer or microphone is opened.

`validate_mdx.cpp` is an optional standalone harness accepting model, stereo PCM16
44.1 kHz input, output WAV. Retail OHOS may prohibit unsigned executable launch;
use `SeparationDevice` ohosTest for signed-device validation instead.

## Device performance, 2026-09-05

ADY-AL10 / HUAWEI Pura 70, OpenHarmony 6.1.1.120, signed debug HAP,
26.102 s official stereo 44.1 kHz fixture, warm model on disk, foreground app.
Same model and 50% overlapping windows in every run:

| CPU intra-op threads | Arena / memory pattern | End-to-end time | Observed process peak RSS |
| --- | --- | --- | --- |
| 2 | disabled | 92.205 s | 944 MiB |
| 4 (selected) | disabled | 62.566 s | 967 MiB |
| 4 | enabled | 63.434 s | 1673 MiB |

Four threads reduce elapsed time by 32.1% (1.47x throughput). The two- and
four-thread PCM16 outputs have all 2,302,230 samples identical. Arena reuse was
rejected because it increased retained memory without reducing elapsed time.
These are single-run comparisons, not a multi-song quality benchmark or a
four-minute thermal stress test. The suggested RTF <= 1 and RSS <= 512 MiB
gates are not met by this model on this phone yet.

Earlier background test measurements were discarded: the OS restricted the
process to CPUs 2 and 3. SeparationDevice explicitly opens EntryAbility so that
its keep-screen-on policy applies; keep PivoMic foreground throughout testing.
The production lifecycle cancels generation when the app enters background.
