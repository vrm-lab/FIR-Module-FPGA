# Stereo FIR Filter (AXI-Stream) on FPGA

This repository provides a **reference design** of a stereo 16-bit
**Finite Impulse Response (FIR) filter**
implemented in **Verilog**, integrated with **AXI-Stream**, **AXI-Lite control**,
and **AXI DMA**, and validated using **RTL simulation** and a
**bare-metal Vitis application**.

Target platform: **AMD Kria KV260**  
Focus: **clean architecture, deterministic behavior, and hardware–software co-design**

---

## Features

- Stereo **FIR filter** (Q1.15 fixed-point)
- Parameterizable tap count (default: **129 taps**)
- Transposed-form architecture
- AXI-Stream data interface (32-bit interleaved stereo)
- AXI-Lite control and coefficient memory
- Deterministic **1-cycle processing latency**
- Runtime coefficient reconfiguration
- Bare-metal C reference application using AXI DMA
- Independent testbenches for DSP core and AXI wrapper

---

## Architecture Overview

+--------------------+
| ARM (Bare-metal) |
| - AXI DMA |
| - AXI-Lite Ctrl |
+----------+---------+
|
+----------v---------+
| Stereo FIR AXI IP |
| - AXI-Stream IN |
| - FIR Core (L/R) |
| - AXI-Stream OUT |
+--------------------+


- Left and Right channels are processed **synchronously**
- Each channel has an independent FIR core
- Filter coefficients are **shared** between channels
- Runtime coefficient updates are supported

---

## Data Format

- AXI-Stream width: **32-bit**
- Channel mapping:
  - `[31:16]` → Left channel (signed Q1.15)
  - `[15:0]`  → Right channel (signed Q1.15)

---

## Latency

- **Processing latency:** 1 clock cycle  
- Latency is fixed and deterministic
- Independent of the number of FIR taps

---

## AXI-Lite Register Map

| Offset | Register | Description |
|------:|---------|-------------|
| 0x00 | CTRL | bit0 = enable, bit1 = clear_state |
| 0x10 | COEF[0] | FIR coefficient tap 0 (Q1.15) |
| 0x14 | COEF[1] | FIR coefficient tap 1 (Q1.15) |
| ...  | ... | ... |
| 0x10 + 4·(N−1) | COEF[N−1] | FIR coefficient tap N−1 |

See `docs/address_map.md` for detailed documentation.

---

## Verification

RTL verification is performed using dedicated testbenches:

- `tb_fir_core.sv`  
  Verifies FIR DSP behavior:
  - Impulse response
  - Step and sine response
  - Saturation behavior
  - Dynamic coefficient switching

- `tb_fir_axis.sv`  
  Verifies system-level integration:
  - AXI-Lite register access
  - Runtime coefficient updates
  - AXI-Stream handshake and backpressure
  - Stereo interleaved data processing

Simulation outputs are stored in the `result/` directory.

---

## Software Reference (Bare-Metal)

A bare-metal Vitis application is included to demonstrate:

- FIR driver initialization
- AXI-Lite coefficient programming
- Runtime filter reconfiguration (hot-swap)
- AXI DMA stereo buffer transfer
- Basic register read-back verification

Linux / PetaLinux integration is intentionally **out of scope**.

---

## Build Flow (High-Level)

1. Package FIR RTL as custom AXI IP in Vivado
2. Integrate IP with AXI DMA in block design
3. Generate bitstream and export XSA
4. Build bare-metal application in Vitis
5. Run DMA-based validation

See `docs/build_overview.md` for details.

---

## Scope & Intent

This repository is intended as a **clean, minimal FIR reference design**.

Advanced features such as:
- Multiband FIR
- Polyphase / QMF structures
- Mid-side processing
- Adaptive or time-varying filters

are intentionally **out of scope**.

---

## Design Rationale (Summary)

- The default configuration uses **129 FIR taps** as a practical and
  representative example.
  - An odd tap count is commonly used for linear-phase FIR designs.
  - The FIR core itself is fully parameterizable and not limited to 129 taps.

- FIR coefficients are mapped through an **AXI-Lite memory interface**.
  - Each tap occupies one 32-bit AXI-Lite word.
  - The current address width safely supports up to **256 taps**.
  - Designs requiring more than 256 taps only need a wider AXI-Lite
    address bus; no architectural changes are required.

- This repository intentionally does **not** include coefficient generation
  tools (Python / MATLAB).
  - The focus is on **hardware architecture and AXI integration**.
  - FIR coefficient design is application-specific and better handled by
    external DSP tools.
  - Users are free to generate and load their own coefficients at runtime.

---

## Project Status

This repository is provided as a **reference implementation**.

- The design is considered **feature-complete and stable**
- No active development roadmap is planned
- Issues and pull requests are not expected

Future updates may occur only for major revisions.

---

## License

Licensed under the MIT License.  
Provided as-is, without warranty.
