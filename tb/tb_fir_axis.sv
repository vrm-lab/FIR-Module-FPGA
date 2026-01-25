`timescale 1ns / 1ps

// ============================================================================
// tb_fir_axis
// -----------------------------------------------------------------------------
// AXI-based Testbench for Stereo FIR AXI Wrapper
//
// VERIFICATION SCOPE:
// 1. AXI-Lite
//    - Write FIR coefficients into internal RAM
//    - Control enable / clear-state functionality
//
// 2. AXI-Stream
//    - Validate stereo data handshake (tvalid / tready)
//    - Verify correct data flow through the FIR pipeline
//
// 3. DSP Behavior
//    - Impulse response (pass-through configuration)
//    - Simple moving-average filter (2-tap low-pass)
//
// Output samples are printed to console and written to:
//   "axis_fir_output.txt"
// ============================================================================

module tb_fir_axis;

    // =========================================================================
    // 1. PARAMETERS
    // =========================================================================
    parameter integer DATA_WIDTH = 32; // Stereo {L[31:16], R[15:0]}

    // FIR configuration (reduced taps for faster simulation)
    parameter integer FIR_NTAPS  = 16;
    parameter integer ADDR_WIDTH = 10; // Matches C_S_AXI_ADDR_WIDTH

    // =========================================================================
    // 2. SIGNAL DECLARATIONS
    // =========================================================================
    reg aclk;
    reg aresetn;

    // -------------------------------------------------------------------------
    // AXI4-Stream Slave (Input Audio)
    // -------------------------------------------------------------------------
    reg  [DATA_WIDTH-1:0] s_axis_tdata;
    reg                   s_axis_tvalid;
    wire                  s_axis_tready;
    reg                   s_axis_tlast;

    // -------------------------------------------------------------------------
    // AXI4-Stream Master (Output Audio)
    // -------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;
    wire                  m_axis_tlast;

    // -------------------------------------------------------------------------
    // AXI4-Lite Slave (Control & Coefficients)
    // -------------------------------------------------------------------------
    reg  [ADDR_WIDTH-1:0] s_axi_awaddr;
    reg                   s_axi_awvalid;
    wire                  s_axi_awready;

    reg  [31:0]           s_axi_wdata;
    reg  [3:0]            s_axi_wstrb;
    reg                   s_axi_wvalid;
    wire                  s_axi_wready;

    wire [1:0]            s_axi_bresp;
    wire                  s_axi_bvalid;
    reg                   s_axi_bready;

    reg  [ADDR_WIDTH-1:0] s_axi_araddr;
    reg                   s_axi_arvalid;
    wire                  s_axi_arready;

    wire [31:0]           s_axi_rdata;
    wire [1:0]            s_axi_rresp;
    wire                  s_axi_rvalid;
    reg                   s_axi_rready;

    // -------------------------------------------------------------------------
    // Fixed-point constants (Q1.15)
    // -------------------------------------------------------------------------
    localparam signed [15:0] COEFF_ONE  = 16'd32767; // ~1.0
    localparam signed [15:0] COEFF_ZERO = 16'd0;

    // =========================================================================
    // 3. DUT INSTANTIATION
    // =========================================================================
    fir_axis_wrapper #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .FIR_NTAPS(FIR_NTAPS)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),

        // AXI-Stream
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),

        .m_axis_tdata (m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast),

        // AXI-Lite
        .s_axi_awaddr (s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata  (s_axi_wdata),
        .s_axi_wstrb  (s_axi_wstrb),
        .s_axi_wvalid (s_axi_wvalid),
        .s_axi_wready (s_axi_wready),
        .s_axi_bresp  (s_axi_bresp),
        .s_axi_bvalid (s_axi_bvalid),
        .s_axi_bready (s_axi_bready),
        .s_axi_araddr (s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready)
    );

    // =========================================================================
    // 4. CLOCK GENERATION
    // =========================================================================
    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk; // 100 MHz
    end

    // =========================================================================
    // 5. AXI HELPER TASKS
    // =========================================================================

    // AXI-Lite write transaction
    task axi_write(input [ADDR_WIDTH-1:0] addr, input [31:0] data);
        begin
            @(posedge aclk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;
            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;
            s_axi_wstrb   <= 4'hF;
            s_axi_bready  <= 1'b0;

            wait (s_axi_awready && s_axi_wready);

            @(posedge aclk);
            s_axi_awvalid <= 1'b0;
            s_axi_wvalid  <= 1'b0;

            s_axi_bready <= 1'b1;
            wait (s_axi_bvalid);
            @(posedge aclk);
            s_axi_bready <= 1'b0;
        end
    endtask

    // AXI-Stream stereo data send
    task send_stream_data(
        input signed [15:0] left_in,
        input signed [15:0] right_in,
        input               last_flag
    );
        begin
            wait (s_axis_tready);

            @(posedge aclk);
            s_axis_tdata  <= {left_in, right_in};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= last_flag;

            @(posedge aclk);
            while (!s_axis_tready) @(posedge aclk);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
        end
    endtask

    // =========================================================================
    // 6. MAIN TEST SEQUENCE
    // =========================================================================
    integer i;
    integer fd_axis;
    reg [ADDR_WIDTH-1:0] coeff_addr;

    initial begin
        // Initialization
        aresetn = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = '0;
        m_axis_tready = 1'b1;

        s_axi_awaddr = '0; s_axi_awvalid = 1'b0;
        s_axi_wdata  = '0; s_axi_wvalid  = 1'b0;
        s_axi_wstrb  = '0; s_axi_bready  = 1'b0;
        s_axi_araddr = '0; s_axi_arvalid = 1'b0;
        s_axi_rready = 1'b0;

        repeat (10) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5) @(posedge aclk);

        fd_axis = $fopen("axis_fir_output.txt", "w");
        $display("=== FIR AXIS TESTBENCH START ===");

        // ---------------------------------------------------------------------
        // TEST 1: IMPULSE RESPONSE (PASS-THROUGH)
        // ---------------------------------------------------------------------
        $display("--- TEST 1: Impulse Response (Pass-Through) ---");

        axi_write('h00, 32'h0000_0000); // Disable
        axi_write('h00, 32'h0000_0002); // Clear state
        axi_write('h00, 32'h0000_0000); // Stay disabled

        // h[0] = 1.0, h[1..] = 0
        axi_write('h10, {16'd0, COEFF_ONE});
        for (i = 1; i < FIR_NTAPS; i = i + 1) begin
            coeff_addr = 'h10 + (i * 4);
            axi_write(coeff_addr, {16'd0, COEFF_ZERO});
        end

        axi_write('h00, 32'h0000_0001); // Enable

        // Send impulse
        send_stream_data(16'd10000, -16'd10000, 1'b0);

        // Flush pipeline
        for (i = 0; i < 10; i = i + 1)
            send_stream_data(16'd0, 16'd0, (i == 9));

        // ---------------------------------------------------------------------
        // TEST 2: MOVING AVERAGE (2-TAP LOW-PASS)
        // ---------------------------------------------------------------------
        $display("--- TEST 2: Moving Average Filter (2-Tap) ---");

        axi_write('h10, {16'd0, 16'd16384}); // h[0] = 0.5
        axi_write('h14, {16'd0, 16'd16384}); // h[1] = 0.5

        send_stream_data(16'd10000, 16'd10000, 1'b0);

        for (i = 0; i < 10; i = i + 1)
            send_stream_data(16'd0, 16'd0, (i == 9));

        repeat (20) @(posedge aclk);

        $display("=== FIR AXIS TESTBENCH COMPLETE ===");
        $fclose(fd_axis);
        $finish;
    end

    // =========================================================================
    // 7. OUTPUT MONITOR
    // =========================================================================
    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            $display("Time %0t | AXIS OUT | L=%6d | R=%6d",
                     $time,
                     $signed(m_axis_tdata[31:16]),
                     $signed(m_axis_tdata[15:0]));

            $fwrite(fd_axis, "%0d %0d\n",
                     $signed(m_axis_tdata[31:16]),
                     $signed(m_axis_tdata[15:0]));
        end
    end

endmodule
