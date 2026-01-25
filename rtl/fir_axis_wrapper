`timescale 1ns / 1ps

// ============================================================================
// MODULE: fir_axis_wrapper
// -----------------------------------------------------------------------------
// AXI-Stream + AXI-Lite Wrapper for Parameterized FIR Core
//
// FEATURES:
// - Stereo processing (shared coefficient set)
// - Runtime coefficient update via AXI-Lite
// - Transposed-form FIR core integration
// - Fixed-point audio data path
//
// AXI-LITE MEMORY MAP:
// 0x00        : Control Register
//               [0] Enable
//               [1] Clear FIR state
//
// 0x10 - ...  : Coefficient Memory (word-addressed)
//               0x10 -> h[0]
//               0x14 -> h[1]
//               ...
//
// NOTES:
// - Coefficients are stored in internal RAM and flattened before being passed
//   to the FIR core.
// - Left and Right channels share the same coefficient set.
// ============================================================================

module fir_axis_wrapper #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 10, // Enough for ~256 taps
    parameter integer DATA_WIDTH         = 32,

    // FIR Configuration
    parameter integer FIR_COEFW          = 16,
    parameter integer FIR_NTAPS          = 129,
    parameter integer FIR_ACCW           = 64,
    parameter integer FIR_OUT_SHIFT      = 15
)(
    // ------------------------------------------------------------------------
    // Global Clock & Reset
    // ------------------------------------------------------------------------
    input  wire aclk,
    input  wire aresetn,

    // ------------------------------------------------------------------------
    // AXI4-Stream Slave (Audio Input)
    // ------------------------------------------------------------------------
    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master (Audio Output)
    // ------------------------------------------------------------------------
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,
    output reg                   m_axis_tlast,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave (Control & Coefficients)
    // ------------------------------------------------------------------------
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output wire                          s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output wire                          s_axi_wready,
    output wire [1:0]                    s_axi_bresp,
    output wire                          s_axi_bvalid,
    input  wire                          s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output wire                          s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output wire [1:0]                    s_axi_rresp,
    output wire                          s_axi_rvalid,
    input  wire                          s_axi_rready
);

    // =========================================================================
    // 1. AXI-LITE REGISTERS & COEFFICIENT MEMORY
    // =========================================================================
    reg [31:0] reg_ctrl;

    // Coefficient RAM
    // Inferred as distributed RAM or BRAM depending on synthesis settings
    reg signed [FIR_COEFW-1:0] coef_ram [0:FIR_NTAPS-1];

    // AXI-Lite handshake signals
    reg axi_awready, axi_wready, axi_bvalid;
    reg axi_arready, axi_rvalid;
    reg [1:0] axi_bresp;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;
    reg aw_en;

    // Output assignments
    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bresp   = axi_bresp;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_arready = axi_arready;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rvalid  = axi_rvalid;

    // Address decoding helpers
    // (addr - 0x10) / 4 -> coefficient index
    wire [C_S_AXI_ADDR_WIDTH-1:0] w_idx = (s_axi_awaddr - 'h10) >> 2;
    wire [C_S_AXI_ADDR_WIDTH-1:0] r_idx = (s_axi_araddr - 'h10) >> 2;

    // =========================================================================
    // 2. AXI-LITE WRITE LOGIC
    // =========================================================================
    integer i;
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'b00;
            aw_en       <= 1'b1;

            reg_ctrl <= 32'h1; // Default: enabled

            // Initialize coefficients (pass-through by default)
            for (i = 0; i < FIR_NTAPS; i = i + 1)
                coef_ram[i] <= '0;

            coef_ram[0] <= (1 << FIR_OUT_SHIFT);

        end else begin
            if (!axi_awready && s_axi_awvalid && aw_en) begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end

            if (!axi_wready && s_axi_wvalid)
                axi_wready <= 1'b1;
            else
                axi_wready <= 1'b0;

            if (axi_awready && s_axi_awvalid &&
                axi_wready  && s_axi_wvalid &&
                !axi_bvalid) begin

                axi_bvalid <= 1'b1;

                // Write decode
                if (s_axi_awaddr[7:0] == 8'h00) begin
                    reg_ctrl <= s_axi_wdata;
                end else if (s_axi_awaddr >= 'h10) begin
                    if (w_idx < FIR_NTAPS)
                        coef_ram[w_idx] <= s_axi_wdata[FIR_COEFW-1:0];
                end

            end else if (axi_bvalid && s_axi_bready) begin
                axi_bvalid <= 1'b0;
                aw_en <= 1'b1;
            end
        end
    end

    // =========================================================================
    // 3. AXI-LITE READ LOGIC
    // =========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= '0;

        end else begin
            if (!axi_arready && s_axi_arvalid)
                axi_arready <= 1'b1;
            else
                axi_arready <= 1'b0;

            if (axi_arready && s_axi_arvalid && !axi_rvalid) begin
                axi_rvalid <= 1'b1;

                // Read decode
                if (s_axi_araddr[7:0] == 8'h00) begin
                    axi_rdata <= reg_ctrl;
                end else if (s_axi_araddr >= 'h10) begin
                    if (r_idx < FIR_NTAPS)
                        axi_rdata <= {{16{coef_ram[r_idx][FIR_COEFW-1]}}, coef_ram[r_idx]};
                    else
                        axi_rdata <= '0;
                end

            end else if (axi_rvalid && s_axi_rready) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 4. COEFFICIENT PACKING (ARRAY -> FLAT VECTOR)
    // =========================================================================
    wire [FIR_NTAPS*FIR_COEFW-1:0] coef_flat_wire;

    genvar k;
    generate
        for (k = 0; k < FIR_NTAPS; k = k + 1) begin : PACK_COEF
            assign coef_flat_wire[k*FIR_COEFW +: FIR_COEFW] = coef_ram[k];
        end
    endgenerate

    // =========================================================================
    // 5. FIR CORE INTEGRATION (STEREO)
    // =========================================================================
    wire soft_en    = reg_ctrl[0];
    wire soft_clear = reg_ctrl[1];

    wire axis_hs = s_axis_tvalid && (m_axis_tready || !m_axis_tvalid);
    wire core_en = axis_hs && soft_en;

    assign s_axis_tready = (m_axis_tready || !m_axis_tvalid) && soft_en;

    // Stereo unpacking
    wire signed [15:0] L_in  = s_axis_tdata[31:16];
    wire signed [15:0] R_in  = s_axis_tdata[15:0];
    wire signed [15:0] L_out;
    wire signed [15:0] R_out;

    // Left channel
    fir_core #(
        .DATAW(16),
        .COEFW(FIR_COEFW),
        .NTAPS(FIR_NTAPS),
        .ACCW(FIR_ACCW),
        .OUT_SHIFT(FIR_OUT_SHIFT)
    ) core_L (
        .clk(aclk),
        .rstn(aresetn),
        .en(core_en),
        .clear_state(soft_clear),
        .din(L_in),
        .coef_flat(coef_flat_wire),
        .dout(L_out)
    );

    // Right channel
    fir_core #(
        .DATAW(16),
        .COEFW(FIR_COEFW),
        .NTAPS(FIR_NTAPS),
        .ACCW(FIR_ACCW),
        .OUT_SHIFT(FIR_OUT_SHIFT)
    ) core_R (
        .clk(aclk),
        .rstn(aresetn),
        .en(core_en),
        .clear_state(soft_clear),
        .din(R_in),
        .coef_flat(coef_flat_wire),
        .dout(R_out)
    );

    // =========================================================================
    // 6. AXI-STREAM OUTPUT LOGIC
    // =========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else if (m_axis_tready || !m_axis_tvalid) begin
            m_axis_tvalid <= s_axis_tvalid && soft_en;
            m_axis_tlast  <= s_axis_tlast;
        end
    end

    assign m_axis_tdata = {L_out, R_out};

endmodule
