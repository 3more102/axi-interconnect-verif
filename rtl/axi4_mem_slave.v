//-----------------------------------------------------------------------------
// axi4_mem_slave.v — full AXI4 memory slave (SPEC.md section 4)
//
// - Backing store: 1024 x 32-bit words (full 4 KB window), word index =
//   addr[11:2], address bits [31:12] ignored (window aliasing).
// - Valid range: byte offset addr[11:0] < MEM_BYTES -> OKAY, else SLVERR
//   for that beat.
// - Burst types: FIXED (2'b00, constant address), INCR (2'b01,
//   address += 2^size per beat), WRAP (2'b10, wrap boundary =
//   align_down(start, (len+1)*2^size) + (len+1)*2^size). 2'b11 treated
//   as INCR.
// - Narrow transfers: word addressed by addr[11:2] is always accessed;
//   write lanes selected purely by WSTRB; reads return the full word.
// - Write flow: AWREADY high when idle; after AW capture WREADY high;
//   in-range beats written per WSTRB (even if overall BRESP is SLVERR),
//   out-of-range beats discarded; burst ends on WLAST regardless of
//   mistiming; BVALID rises the cycle after the WLAST beat; BRESP =
//   SLVERR if any beat was out of range; BID = captured AWID.
// - Read flow: ARREADY high when idle; RVALID held continuously through
//   the burst (payload stable while RREADY low); per-beat RRESP;
//   out-of-range beats return 32'h0; RLAST on beat ARLEN+1; RID =
//   captured ARID.
// - One outstanding write and one outstanding read, independent engines.
//
// Strict Verilog-2001. Synchronous active-low reset. No initial blocks,
// no delays.
//-----------------------------------------------------------------------------

module axi4_mem_slave #(
    parameter ID_WIDTH  = 4,
    parameter MEM_BYTES = 3072       // bytes 0..MEM_BYTES-1 valid within 4KB window
)(
    input  wire                aclk,
    input  wire                aresetn,
    // write address
    input  wire [ID_WIDTH-1:0] s_axi_awid,
    input  wire [31:0]         s_axi_awaddr,
    input  wire [7:0]          s_axi_awlen,
    input  wire [2:0]          s_axi_awsize,
    input  wire [1:0]          s_axi_awburst,
    input  wire [2:0]          s_axi_awprot,
    input  wire                s_axi_awvalid,
    output wire                s_axi_awready,
    // write data
    input  wire [31:0]         s_axi_wdata,
    input  wire [3:0]          s_axi_wstrb,
    input  wire                s_axi_wlast,
    input  wire                s_axi_wvalid,
    output wire                s_axi_wready,
    // write response
    output wire [ID_WIDTH-1:0] s_axi_bid,
    output wire [1:0]          s_axi_bresp,
    output wire                s_axi_bvalid,
    input  wire                s_axi_bready,
    // read address
    input  wire [ID_WIDTH-1:0] s_axi_arid,
    input  wire [31:0]         s_axi_araddr,
    input  wire [7:0]          s_axi_arlen,
    input  wire [2:0]          s_axi_arsize,
    input  wire [1:0]          s_axi_arburst,
    input  wire [2:0]          s_axi_arprot,
    input  wire                s_axi_arvalid,
    output wire                s_axi_arready,
    // read data
    output wire [ID_WIDTH-1:0] s_axi_rid,
    output wire [31:0]         s_axi_rdata,
    output wire [1:0]          s_axi_rresp,
    output wire                s_axi_rlast,
    output wire                s_axi_rvalid,
    input  wire                s_axi_rready
);

    // ------------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------------
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;

    localparam BURST_FIXED = 2'b00;
    localparam BURST_WRAP  = 2'b10;

    // write engine states
    localparam W_IDLE = 2'd0;
    localparam W_DATA = 2'd1;
    localparam W_RESP = 2'd2;

    // read engine states
    localparam R_IDLE = 1'b0;
    localparam R_DATA = 1'b1;

    // ------------------------------------------------------------------
    // Backing store: full 4 KB window (word index = addr[11:2]).
    // Not initialized (tests write before read).
    // ------------------------------------------------------------------
    reg [31:0] mem [0:1023];

    // ------------------------------------------------------------------
    // Per-beat next-address function (shared by write and read engines).
    // FIXED: constant. INCR (01 and reserved 11): += 2^size.
    // WRAP: += 2^size, wrapping back to the lower boundary when the
    // upper boundary (lower + (len+1)*2^size) is reached.
    // ------------------------------------------------------------------
    function [31:0] next_beat_addr;
        input [31:0] cur;
        input [1:0]  burst;
        input [2:0]  size;
        input [31:0] wlo;    // wrap lower boundary
        input [31:0] wup;    // wrap upper boundary
        reg   [31:0] inc;
        begin
            inc = cur + (32'd1 << size);
            case (burst)
                BURST_FIXED: next_beat_addr = cur;
                BURST_WRAP:  next_beat_addr = (inc >= wup) ? wlo : inc;
                default:     next_beat_addr = inc;   // INCR (2'b01, 2'b11)
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    // Wrap-boundary precompute (combinational, sampled at AW/AR capture).
    // total bytes = (len+1) << size; boundary math is exact for the
    // legal WRAP lengths {1,3,7,15} with size-aligned start addresses.
    // ------------------------------------------------------------------
    wire [31:0] aw_total = ({24'd0, s_axi_awlen} + 32'd1) << s_axi_awsize;
    wire [31:0] aw_wlo   = s_axi_awaddr & ~(aw_total - 32'd1);
    wire [31:0] aw_wup   = aw_wlo + aw_total;

    wire [31:0] ar_total = ({24'd0, s_axi_arlen} + 32'd1) << s_axi_arsize;
    wire [31:0] ar_wlo   = s_axi_araddr & ~(ar_total - 32'd1);
    wire [31:0] ar_wup   = ar_wlo + ar_total;

    // ==================================================================
    // Write engine (independent, one outstanding write)
    // ==================================================================
    reg [1:0]          wr_state;
    reg [ID_WIDTH-1:0] wr_id;
    reg [31:0]         wr_addr;    // current beat address
    reg [1:0]          wr_burst;
    reg [2:0]          wr_size;
    reg [31:0]         wr_wlo;
    reg [31:0]         wr_wup;
    reg                wr_err;     // any prior beat out of range

    reg [ID_WIDTH-1:0] bid_r;
    reg [1:0]          bresp_r;
    reg                bvalid_r;

    wire        wr_in_range = (wr_addr[11:0] < MEM_BYTES);
    wire [9:0]  wr_word     = wr_addr[11:2];

    assign s_axi_awready = aresetn && (wr_state == W_IDLE);
    assign s_axi_wready  = (wr_state == W_DATA);
    assign s_axi_bid     = bid_r;
    assign s_axi_bresp   = bresp_r;
    assign s_axi_bvalid  = bvalid_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_state <= W_IDLE;
            wr_id    <= {ID_WIDTH{1'b0}};
            wr_addr  <= 32'd0;
            wr_burst <= 2'b00;
            wr_size  <= 3'b000;
            wr_wlo   <= 32'd0;
            wr_wup   <= 32'd0;
            wr_err   <= 1'b0;
            bid_r    <= {ID_WIDTH{1'b0}};
            bresp_r  <= RESP_OKAY;
            bvalid_r <= 1'b0;
        end else begin
            case (wr_state)
                W_IDLE: begin
                    if (s_axi_awvalid) begin       // awready is high here
                        wr_id    <= s_axi_awid;
                        wr_addr  <= s_axi_awaddr;
                        wr_burst <= s_axi_awburst;
                        wr_size  <= s_axi_awsize;
                        wr_wlo   <= aw_wlo;
                        wr_wup   <= aw_wup;
                        wr_err   <= 1'b0;
                        wr_state <= W_DATA;
                    end
                end
                W_DATA: begin
                    if (s_axi_wvalid) begin        // wready is high here
                        // memory update itself is in the block below
                        if (!wr_in_range)
                            wr_err <= 1'b1;
                        wr_addr <= next_beat_addr(wr_addr, wr_burst, wr_size,
                                                  wr_wlo, wr_wup);
                        if (s_axi_wlast) begin
                            // burst ends on WLAST regardless of AWLEN
                            bid_r    <= wr_id;
                            bresp_r  <= (wr_err || !wr_in_range) ? RESP_SLVERR
                                                                 : RESP_OKAY;
                            bvalid_r <= 1'b1;      // rises the next cycle
                            wr_state <= W_RESP;
                        end
                    end
                end
                W_RESP: begin
                    if (s_axi_bready) begin        // bvalid is high here
                        bvalid_r <= 1'b0;
                        wr_state <= W_IDLE;
                    end
                end
                default: begin
                    wr_state <= W_IDLE;
                    bvalid_r <= 1'b0;
                end
            endcase
        end
    end

    // Memory write: in-range beats written per WSTRB (even when the
    // overall burst response will be SLVERR); out-of-range discarded.
    always @(posedge aclk) begin
        if (aresetn && (wr_state == W_DATA) && s_axi_wvalid && wr_in_range) begin
            if (s_axi_wstrb[0]) mem[wr_word][7:0]   <= s_axi_wdata[7:0];
            if (s_axi_wstrb[1]) mem[wr_word][15:8]  <= s_axi_wdata[15:8];
            if (s_axi_wstrb[2]) mem[wr_word][23:16] <= s_axi_wdata[23:16];
            if (s_axi_wstrb[3]) mem[wr_word][31:24] <= s_axi_wdata[31:24];
        end
    end

    // ==================================================================
    // Read engine (independent, one outstanding read)
    // ==================================================================
    reg                rd_state;
    reg [ID_WIDTH-1:0] rid_r;
    reg [31:0]         rd_addr;    // address of the NEXT beat to present
    reg [1:0]          rd_burst;
    reg [2:0]          rd_size;
    reg [31:0]         rd_wlo;
    reg [31:0]         rd_wup;
    reg [7:0]          rd_len;     // captured ARLEN
    reg [7:0]          rd_cnt;     // index of the beat currently presented

    reg [31:0]         rdata_r;
    reg [1:0]          rresp_r;
    reg                rlast_r;
    reg                rvalid_r;

    wire ar_in_range      = (s_axi_araddr[11:0] < MEM_BYTES);
    wire rd_next_in_range = (rd_addr[11:0] < MEM_BYTES);

    assign s_axi_arready = aresetn && (rd_state == R_IDLE);
    assign s_axi_rid     = rid_r;
    assign s_axi_rdata   = rdata_r;
    assign s_axi_rresp   = rresp_r;
    assign s_axi_rlast   = rlast_r;
    assign s_axi_rvalid  = rvalid_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_state <= R_IDLE;
            rid_r    <= {ID_WIDTH{1'b0}};
            rd_addr  <= 32'd0;
            rd_burst <= 2'b00;
            rd_size  <= 3'b000;
            rd_wlo   <= 32'd0;
            rd_wup   <= 32'd0;
            rd_len   <= 8'd0;
            rd_cnt   <= 8'd0;
            rdata_r  <= 32'd0;
            rresp_r  <= RESP_OKAY;
            rlast_r  <= 1'b0;
            rvalid_r <= 1'b0;
        end else begin
            case (rd_state)
                R_IDLE: begin
                    if (s_axi_arvalid) begin       // arready is high here
                        rid_r    <= s_axi_arid;
                        rd_burst <= s_axi_arburst;
                        rd_size  <= s_axi_arsize;
                        rd_wlo   <= ar_wlo;
                        rd_wup   <= ar_wup;
                        rd_len   <= s_axi_arlen;
                        rd_cnt   <= 8'd0;
                        // present beat 0 next cycle; registered payload
                        // stays stable while RREADY is low
                        rdata_r  <= ar_in_range ? mem[s_axi_araddr[11:2]]
                                                : 32'h0000_0000;
                        rresp_r  <= ar_in_range ? RESP_OKAY : RESP_SLVERR;
                        rlast_r  <= (s_axi_arlen == 8'd0);
                        rvalid_r <= 1'b1;
                        // precompute address of beat 1
                        rd_addr  <= next_beat_addr(s_axi_araddr, s_axi_arburst,
                                                   s_axi_arsize, ar_wlo, ar_wup);
                        rd_state <= R_DATA;
                    end
                end
                R_DATA: begin
                    if (s_axi_rready) begin        // rvalid is high here
                        if (rlast_r) begin
                            rvalid_r <= 1'b0;
                            rlast_r  <= 1'b0;
                            rd_state <= R_IDLE;
                        end else begin
                            // advance to next beat; rvalid stays high
                            // continuously through the burst
                            rd_cnt  <= rd_cnt + 8'd1;
                            rdata_r <= rd_next_in_range ? mem[rd_addr[11:2]]
                                                        : 32'h0000_0000;
                            rresp_r <= rd_next_in_range ? RESP_OKAY
                                                        : RESP_SLVERR;
                            rlast_r <= ((rd_cnt + 8'd1) == rd_len);
                            rd_addr <= next_beat_addr(rd_addr, rd_burst,
                                                      rd_size, rd_wlo, rd_wup);
                        end
                    end
                end
                default: rd_state <= R_IDLE;
            endcase
        end
    end

endmodule
