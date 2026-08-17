// ============================================================================
// axi4_lite_slave.v -- AXI4-Lite register-file slave
// Implements SPEC.md section 2 exactly.
//
// - 16 x 32-bit register file, register index = addr[5:2]; address bits
//   [31:6] and [1:0] are ignored (the 64-byte window aliases across the
//   4 KB region -- documented feature).
// - Index >= NUM_REGS -> SLVERR (2'b10); writes to an invalid index do not
//   modify state; reads of an invalid index return 32'h0000_0000.
// - Write: AW and W are accepted independently (either order, any gap).
//   Once both are captured, bvalid rises the following cycle and holds until
//   bready. One outstanding write: awready/wready stay low from capture
//   until the B handshake completes.
// - Read: arready high when idle; a captured AR produces rvalid the next
//   cycle, data/resp held until rready. One outstanding read.
// - Read and write engines are fully independent (concurrent R/W allowed).
// - Pure Verilog-2001, synchronous active-low reset, no initial blocks,
//   no delays.
// ============================================================================

module axi4_lite_slave #(
    parameter NUM_REGS = 12          // valid word indices 0..NUM_REGS-1 (max 16)
)(
    input  wire        aclk,
    input  wire        aresetn,
    // write address
    input  wire [31:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    // write data
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    // write response
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    // read address
    input  wire [31:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    // read data
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready
);

    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    // ------------------------------------------------------------------------
    // Register file
    // ------------------------------------------------------------------------
    reg [31:0] regs [0:15];

    // ------------------------------------------------------------------------
    // Write engine: independent AW / W capture, single outstanding write
    // ------------------------------------------------------------------------
    reg        aw_got;               // AW captured, held until B handshake
    reg [3:0]  aw_index;
    reg        w_got;                // W captured, held until B handshake
    reg [31:0] w_data;
    reg [3:0]  w_strb;
    reg        bvalid_r;
    reg [1:0]  bresp_r;

    wire aw_hs = s_axi_awvalid & s_axi_awready;
    wire w_hs  = s_axi_wvalid  & s_axi_wready;
    wire b_hs  = s_axi_bvalid  & s_axi_bready;

    assign s_axi_awready = ~aw_got;
    assign s_axi_wready  = ~w_got;
    assign s_axi_bresp   = bresp_r;
    assign s_axi_bvalid  = bvalid_r;

    // Commit fires on the clock edge where the second of {AW, W} completes
    // (or later if both completed the same edge); bvalid rises the next cycle.
    wire        commit   = ~bvalid_r & (aw_got | aw_hs) & (w_got | w_hs);
    wire [3:0]  wr_index = aw_hs ? s_axi_awaddr[5:2] : aw_index;
    wire [31:0] wr_data  = w_hs  ? s_axi_wdata       : w_data;
    wire [3:0]  wr_strb  = w_hs  ? s_axi_wstrb       : w_strb;
    wire        wr_ok    = (wr_index < NUM_REGS);

    integer i;

    always @(posedge aclk) begin
        if (!aresetn) begin
            aw_got   <= 1'b0;
            aw_index <= 4'd0;
            w_got    <= 1'b0;
            w_data   <= 32'd0;
            w_strb   <= 4'd0;
            bvalid_r <= 1'b0;
            bresp_r  <= RESP_OKAY;
            for (i = 0; i < 16; i = i + 1)
                regs[i] <= 32'd0;
        end else begin
            if (aw_hs) begin
                aw_got   <= 1'b1;
                aw_index <= s_axi_awaddr[5:2];
            end
            if (w_hs) begin
                w_got  <= 1'b1;
                w_data <= s_axi_wdata;
                w_strb <= s_axi_wstrb;
            end
            if (commit) begin
                bvalid_r <= 1'b1;
                if (wr_ok) begin
                    bresp_r <= RESP_OKAY;
                    if (wr_strb[0]) regs[wr_index][7:0]   <= wr_data[7:0];
                    if (wr_strb[1]) regs[wr_index][15:8]  <= wr_data[15:8];
                    if (wr_strb[2]) regs[wr_index][23:16] <= wr_data[23:16];
                    if (wr_strb[3]) regs[wr_index][31:24] <= wr_data[31:24];
                end else begin
                    bresp_r <= RESP_SLVERR;   // invalid index: no state change
                end
            end else if (b_hs) begin
                bvalid_r <= 1'b0;
                aw_got   <= 1'b0;
                w_got    <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Read engine: single outstanding read, independent of write engine
    // ------------------------------------------------------------------------
    reg        rvalid_r;
    reg [31:0] rdata_r;
    reg [1:0]  rresp_r;

    wire ar_hs = s_axi_arvalid & s_axi_arready;
    wire r_hs  = s_axi_rvalid  & s_axi_rready;

    wire [3:0] rd_index = s_axi_araddr[5:2];

    assign s_axi_arready = ~rvalid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = rresp_r;
    assign s_axi_rvalid  = rvalid_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            rvalid_r <= 1'b0;
            rdata_r  <= 32'd0;
            rresp_r  <= RESP_OKAY;
        end else begin
            if (ar_hs) begin
                rvalid_r <= 1'b1;
                if (rd_index < NUM_REGS) begin
                    rdata_r <= regs[rd_index];
                    rresp_r <= RESP_OKAY;
                end else begin
                    rdata_r <= 32'h0000_0000;
                    rresp_r <= RESP_SLVERR;
                end
            end else if (r_hs) begin
                rvalid_r <= 1'b0;
            end
        end
    end

endmodule
