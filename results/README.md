# Simulation Results

All files in this directory are generated from RTL simulation testbenches.
The results validate both DSP behavior and AXI-based integration of the
stereo FIR filter.

---

## Core FIR Verification

### Impulse Response
- Generated from `tb_fir_core`
- Output files:
  - `fir_impulse_response.txt`
  - `fir_impulse_response.png`
- Confirms:
  - Correct transposed-form FIR convolution
  - Proper coefficient ordering
  - Fixed-point scaling and rounding behavior

---

### Dynamic Coefficient Switching
- Generated from `tb_fir_core`
- Output files:
  - `fir_dynamic_switch.txt`
  - `fir_dynamic_switch.png`
- Demonstrates:
  - Runtime coefficient update without reset
  - Stable output during coefficient transition
  - No pipeline corruption or numerical instability

---

## High-Pass Filter (HPF) Validation

- Generated from `tb_fir_core_hpf`
- Output files:
  - `hpf_response_500Hz.txt / .png`
  - `hpf_response_12kHz.txt / .png`
- Confirms:
  - Low-frequency attenuation (500 Hz)
  - High-frequency pass-through (12 kHz)
  - Effective DC rejection (sum of coefficients ≈ 0)

Amplitude comparison is performed inside the testbench to ensure
frequency discrimination.

---

## AXI-Stream & AXI-Lite Integration

- Generated from `tb_fir_axis`
- Output files:
  - `axis_fir_output.txt`
  - `axis_fir_output.png`
- Verifies:
  - Correct AXI-Lite coefficient write/read
  - Proper enable and clear-state control
  - Stable AXI-Stream handshake (tvalid/tready)
  - Identical processing on Left and Right channels

Impulse and moving-average filter configurations are applied via
AXI-Lite during simulation.

---

## Notes

- All numerical values use signed fixed-point representation (Q1.15).
- Text files are intended for post-processing and plotting.
- PNG files are auto-generated using an external Python plotting script.
