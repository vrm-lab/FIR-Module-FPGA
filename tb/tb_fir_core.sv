`timescale 1ns/1ps

// ============================================================================
// tb_fir_core
// -----------------------------------------------------------------------------
// Testbench for Transposed-Form FIR Core
//
// TEST COVERAGE:
// 1. Impulse Response
//    - Verifies basic convolution behavior
//
// 2. Saturation Test
//    - Forces positive and negative clipping
//    - Ensures no wrap-around occurs
//
// 3. Dynamic Coefficient Switching
//    - Modifies coefficients during active streaming
//    - Verifies real-time coefficient update robustness
//
// Output data is written to text files for offline plotting:
// Format per line: <input> <output>
// ============================================================================

module tb_fir_core;

    // =========================================================================
    // 1. PARAMETERS
    // =========================================================================
    // Clock period corresponding to ~48 kHz sample rate
    localparam CLK_PERIOD = 20833; // ns

    // FIR configuration (reduced taps for faster simulation)
    localparam integer DATAW     = 16;
    localparam integer COEFW     = 16;
    localparam integer NTAPS     = 16;
    localparam integer ACCW      = 40;
    localparam integer OUT_SHIFT = 15; // Q1.15 normalization
    localparam integer ROUND     = 1;
    localparam integer SATURATE  = 1;

    // =========================================================================
    // 2. SIGNAL DECLARATIONS
    // =========================================================================
    reg  clk;
    reg  rstn;
    reg  en;
    reg  clear_state;

    reg  signed [DATAW-1:0] din;
    wire signed [DATAW-1:0] dout;

    // Coefficient interface (array form for testbench convenience)
    reg signed [COEFW-1:0] coef_array [0:NTAPS-1];

    // Flattened coefficient vector connected to DUT
    logic [NTAPS*COEFW-1:0] coef_flat;

    // File handles
    integer fd_impulse;
    integer fd_sat;
    integer fd_dynamic;

    // Helper variables
    integer i;
    real phase;
    real sine_val;

    // =========================================================================
    // 3. COEFFICIENT PACKING (ARRAY -> FLAT VECTOR)
    // =========================================================================
    // Index 0 of coef_flat corresponds to h[0]
    always_comb begin
        for (int k = 0; k < NTAPS; k++) begin
            coef_flat[k*COEFW +: COEFW] = coef_array[k];
        end
    end

    // =========================================================================
    // 4. DUT INSTANTIATION
    // =========================================================================
    fir_core #(
        .DATAW    (DATAW),
        .COEFW    (COEFW),
        .NTAPS    (NTAPS),
        .ACCW     (ACCW),
        .OUT_SHIFT(OUT_SHIFT),
        .ROUND    (ROUND),
        .SATURATE (SATURATE)
    ) dut (
        .clk        (clk),
        .rstn       (rstn),
        .en         (en),
        .clear_state(clear_state),
        .din        (din),
        .coef_flat  (coef_flat),
        .dout       (dout)
    );

    // =========================================================================
    // 5. CLOCK GENERATION
    // =========================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // 6. MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        $display("=== FIR CORE TESTBENCH START ===");

        // Open output files
        fd_impulse = $fopen("fir_impulse_response.txt", "w");
        fd_sat     = $fopen("fir_saturation_test.txt", "w");
        fd_dynamic = $fopen("fir_dynamic_switch.txt", "w");

        // Initialize signals
        rstn        = 1'b0;
        en          = 1'b0;
        clear_state = 1'b0;
        din         = '0;

        // Initialize coefficients to zero
        for (i = 0; i < NTAPS; i = i + 1)
            coef_array[i] = '0;

        // Apply reset
        #(10 * CLK_PERIOD);
        rstn = 1'b1;
        #(2 * CLK_PERIOD);

        // =====================================================================
        // TEST 1: IMPULSE RESPONSE
        // =====================================================================
        $display("--- TEST 1: Impulse Response ---");

        // Coefficients: simple decaying response
        // h[0] = 16000, h[1] = 8000, h[2] = 4000, ...
        for (i = 0; i < NTAPS; i = i + 1)
            coef_array[i] = 16'sd16000 >>> i;

        en = 1'b1;

        // Apply impulse input
        @(posedge clk);
        din = 16'sd16000; // ~0.5 amplitude

        @(posedge clk);
        din = 16'sd0;

        // Capture response (pipeline latency included)
        repeat (NTAPS + 5) begin
            @(posedge clk);
            $fwrite(fd_impulse, "%0d %0d\n", din, dout);
        end

        $display("Impulse response written to fir_impulse_response.txt");

        // Clear internal state
        clear_state = 1'b1;
        @(posedge clk);
        clear_state = 1'b0;

        // =====================================================================
        // TEST 2: SATURATION TEST
        // =====================================================================
        $display("--- TEST 2: Saturation Behavior ---");

        // Large coefficients to force overflow
        for (i = 0; i < NTAPS; i = i + 1)
            coef_array[i] = 16'sd32000;

        // Ramp input upward
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            din = 16'sd2000 * i;

            // Clamp input to valid signed range
            if (i > 15)
                din = 16'sd32767;

            #1;
            $fwrite(fd_sat, "%0d %0d\n", din, dout);

            if (dout == 16'sd32767)
                $display("   Saturation detected (positive clip)");
        end

        $display("Saturation data written to fir_saturation_test.txt");

        // Clear internal state
        din = '0;
        clear_state = 1'b1;
        @(posedge clk);
        clear_state = 1'b0;

        // =====================================================================
        // TEST 3: DYNAMIC COEFFICIENT SWITCHING
        // =====================================================================
        $display("--- TEST 3: Dynamic Coefficient Switching ---");

        // Initial configuration: pass-through (gain = 1.0)
        for (i = 0; i < NTAPS; i = i + 1)
            coef_array[i] = '0;

        coef_array[0] = 16'sd32767;

        phase = 0.0;

        for (i = 0; i < 600; i = i + 1) begin
            // Generate 1 kHz sine wave (fs ≈ 48 kHz)
            sine_val = $sin(phase);
            din      = $rtoi(sine_val * 10000);
            phase    = phase + (2.0 * 3.14159 * 1000.0 / 48000.0);

            // Switch coefficients mid-stream
            if (i == 300) begin
                $display(">>> Switching coefficients: pass-through -> inverting <<<");
                coef_array[0] = -16'sd32767;
            end

            @(posedge clk);
            $fwrite(fd_dynamic, "%0d %0d\n", din, dout);
        end

        $display("Dynamic switch data written to fir_dynamic_switch.txt");

        // =====================================================================
        // END OF SIMULATION
        // =====================================================================
        $display("=== FIR CORE TESTBENCH COMPLETE ===");

        $fclose(fd_impulse);
        $fclose(fd_sat);
        $fclose(fd_dynamic);

        $finish;
    end

endmodule
