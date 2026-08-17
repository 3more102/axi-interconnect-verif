// =============================================================================
// formal/axi4_ic_formal.v
// Unbounded property check for axi4_interconnect (SymbiYosys, abc pdr).
//
// Black-box harness, same philosophy as axi4_lite_ic_formal.v: assertions touch
// only the DUT's ports, so they state the interconnect's contract rather than
// mirroring its implementation, and rtl/ stays untouched.
//
// Scope note: this tier proves the ROUTING contract -- reset behavior, address
// decode, and ID-based response steering. Burst semantics (WLAST/RLAST position,
// WRAP address maths, narrow-transfer lanes, 4 KB rules) are covered by the
// simulation tier, where the protocol checker enforces PC08-PC11 on every beat
// of every run. Proving those here would require modelling a burst-accurate
// slave, which would put the interesting behaviour in the harness rather than
// in the DUT.
//
// ASSERTED:
//   P1  all DUT-driven VALIDs are low during reset
//   P2  decode: an address forwarded to m0 is always in S0's range and one
//       forwarded to m1 is always in S1's range
//   P7  ID routing: whenever a response is consumed from a slave port, it is
//       delivered in the same cycle to exactly the master named by the response
//       ID's top bit, carrying that master's original ID in the low bits and
//       the slave's payload unchanged
//
// P2 and P7 need no environment assumptions at all: they are properties of the
// DUT's own decode and mux logic, so they hold against arbitrary slave behavior.
// =============================================================================

module axi4_ic_formal #(
    parameter ID_WIDTH = 4
)(
    input wire                aclk,
    // ---- master-side stimulus (free) ----------------------------------------
    input wire [ID_WIDTH-1:0] s0_awid,
    input wire [31:0]         s0_awaddr,
    input wire [7:0]          s0_awlen,
    input wire [2:0]          s0_awsize,
    input wire [1:0]          s0_awburst,
    input wire [2:0]          s0_awprot,
    input wire                s0_awvalid,
    input wire [31:0]         s0_wdata,
    input wire [3:0]          s0_wstrb,
    input wire                s0_wlast,
    input wire                s0_wvalid,
    input wire                s0_bready,
    input wire [ID_WIDTH-1:0] s0_arid,
    input wire [31:0]         s0_araddr,
    input wire [7:0]          s0_arlen,
    input wire [2:0]          s0_arsize,
    input wire [1:0]          s0_arburst,
    input wire [2:0]          s0_arprot,
    input wire                s0_arvalid,
    input wire                s0_rready,
    input wire [ID_WIDTH-1:0] s1_awid,
    input wire [31:0]         s1_awaddr,
    input wire [7:0]          s1_awlen,
    input wire [2:0]          s1_awsize,
    input wire [1:0]          s1_awburst,
    input wire [2:0]          s1_awprot,
    input wire                s1_awvalid,
    input wire [31:0]         s1_wdata,
    input wire [3:0]          s1_wstrb,
    input wire                s1_wlast,
    input wire                s1_wvalid,
    input wire                s1_bready,
    input wire [ID_WIDTH-1:0] s1_arid,
    input wire [31:0]         s1_araddr,
    input wire [7:0]          s1_arlen,
    input wire [2:0]          s1_arsize,
    input wire [1:0]          s1_arburst,
    input wire [2:0]          s1_arprot,
    input wire                s1_arvalid,
    input wire                s1_rready,
    // ---- slave-side responses (free) ----------------------------------------
    input wire                m0_awready,
    input wire                m0_wready,
    input wire [ID_WIDTH:0]   m0_bid,
    input wire [1:0]          m0_bresp,
    input wire                m0_bvalid,
    input wire                m0_arready,
    input wire [ID_WIDTH:0]   m0_rid,
    input wire [31:0]         m0_rdata,
    input wire [1:0]          m0_rresp,
    input wire                m0_rlast,
    input wire                m0_rvalid,
    input wire                m1_awready,
    input wire                m1_wready,
    input wire [ID_WIDTH:0]   m1_bid,
    input wire [1:0]          m1_bresp,
    input wire                m1_bvalid,
    input wire                m1_arready,
    input wire [ID_WIDTH:0]   m1_rid,
    input wire [31:0]         m1_rdata,
    input wire [1:0]          m1_rresp,
    input wire                m1_rlast,
    input wire                m1_rvalid
);

    // ---- reset sequence -----------------------------------------------------
    reg [3:0] rstcnt = 4'd0;
    always @(posedge aclk)
        if (rstcnt != 4'd15)
            rstcnt <= rstcnt + 4'd1;

    wire aresetn = (rstcnt >= 4'd5);

    reg aresetn_q = 1'b0;
    always @(posedge aclk)
        aresetn_q <= aresetn;

    wire chk = aresetn && aresetn_q;

    // ---- DUT outputs --------------------------------------------------------
    wire                s0_awready, s0_wready, s0_bvalid, s0_arready, s0_rvalid;
    wire [ID_WIDTH-1:0] s0_bid, s0_rid;
    wire [1:0]          s0_bresp, s0_rresp;
    wire [31:0]         s0_rdata;
    wire                s0_rlast;
    wire                s1_awready, s1_wready, s1_bvalid, s1_arready, s1_rvalid;
    wire [ID_WIDTH-1:0] s1_bid, s1_rid;
    wire [1:0]          s1_bresp, s1_rresp;
    wire [31:0]         s1_rdata;
    wire                s1_rlast;

    wire [ID_WIDTH:0]   m0_awid, m0_arid;
    wire [31:0]         m0_awaddr, m0_wdata, m0_araddr;
    wire [7:0]          m0_awlen, m0_arlen;
    wire [2:0]          m0_awsize, m0_awprot, m0_arsize, m0_arprot;
    wire [1:0]          m0_awburst, m0_arburst;
    wire [3:0]          m0_wstrb;
    wire                m0_awvalid, m0_wvalid, m0_wlast, m0_bready;
    wire                m0_arvalid, m0_rready;
    wire [ID_WIDTH:0]   m1_awid, m1_arid;
    wire [31:0]         m1_awaddr, m1_wdata, m1_araddr;
    wire [7:0]          m1_awlen, m1_arlen;
    wire [2:0]          m1_awsize, m1_awprot, m1_arsize, m1_arprot;
    wire [1:0]          m1_awburst, m1_arburst;
    wire [3:0]          m1_wstrb;
    wire                m1_awvalid, m1_wvalid, m1_wlast, m1_bready;
    wire                m1_arvalid, m1_rready;

    axi4_interconnect #(.ID_WIDTH (ID_WIDTH)) dut (
        .aclk (aclk), .aresetn (aresetn),
        .s0_axi_awid (s0_awid), .s0_axi_awaddr (s0_awaddr),
        .s0_axi_awlen (s0_awlen), .s0_axi_awsize (s0_awsize),
        .s0_axi_awburst (s0_awburst), .s0_axi_awprot (s0_awprot),
        .s0_axi_awvalid (s0_awvalid), .s0_axi_awready (s0_awready),
        .s0_axi_wdata (s0_wdata), .s0_axi_wstrb (s0_wstrb),
        .s0_axi_wlast (s0_wlast), .s0_axi_wvalid (s0_wvalid),
        .s0_axi_wready (s0_wready),
        .s0_axi_bid (s0_bid), .s0_axi_bresp (s0_bresp),
        .s0_axi_bvalid (s0_bvalid), .s0_axi_bready (s0_bready),
        .s0_axi_arid (s0_arid), .s0_axi_araddr (s0_araddr),
        .s0_axi_arlen (s0_arlen), .s0_axi_arsize (s0_arsize),
        .s0_axi_arburst (s0_arburst), .s0_axi_arprot (s0_arprot),
        .s0_axi_arvalid (s0_arvalid), .s0_axi_arready (s0_arready),
        .s0_axi_rid (s0_rid), .s0_axi_rdata (s0_rdata),
        .s0_axi_rresp (s0_rresp), .s0_axi_rlast (s0_rlast),
        .s0_axi_rvalid (s0_rvalid), .s0_axi_rready (s0_rready),

        .s1_axi_awid (s1_awid), .s1_axi_awaddr (s1_awaddr),
        .s1_axi_awlen (s1_awlen), .s1_axi_awsize (s1_awsize),
        .s1_axi_awburst (s1_awburst), .s1_axi_awprot (s1_awprot),
        .s1_axi_awvalid (s1_awvalid), .s1_axi_awready (s1_awready),
        .s1_axi_wdata (s1_wdata), .s1_axi_wstrb (s1_wstrb),
        .s1_axi_wlast (s1_wlast), .s1_axi_wvalid (s1_wvalid),
        .s1_axi_wready (s1_wready),
        .s1_axi_bid (s1_bid), .s1_axi_bresp (s1_bresp),
        .s1_axi_bvalid (s1_bvalid), .s1_axi_bready (s1_bready),
        .s1_axi_arid (s1_arid), .s1_axi_araddr (s1_araddr),
        .s1_axi_arlen (s1_arlen), .s1_axi_arsize (s1_arsize),
        .s1_axi_arburst (s1_arburst), .s1_axi_arprot (s1_arprot),
        .s1_axi_arvalid (s1_arvalid), .s1_axi_arready (s1_arready),
        .s1_axi_rid (s1_rid), .s1_axi_rdata (s1_rdata),
        .s1_axi_rresp (s1_rresp), .s1_axi_rlast (s1_rlast),
        .s1_axi_rvalid (s1_rvalid), .s1_axi_rready (s1_rready),

        .m0_axi_awid (m0_awid), .m0_axi_awaddr (m0_awaddr),
        .m0_axi_awlen (m0_awlen), .m0_axi_awsize (m0_awsize),
        .m0_axi_awburst (m0_awburst), .m0_axi_awprot (m0_awprot),
        .m0_axi_awvalid (m0_awvalid), .m0_axi_awready (m0_awready),
        .m0_axi_wdata (m0_wdata), .m0_axi_wstrb (m0_wstrb),
        .m0_axi_wlast (m0_wlast), .m0_axi_wvalid (m0_wvalid),
        .m0_axi_wready (m0_wready),
        .m0_axi_bid (m0_bid), .m0_axi_bresp (m0_bresp),
        .m0_axi_bvalid (m0_bvalid), .m0_axi_bready (m0_bready),
        .m0_axi_arid (m0_arid), .m0_axi_araddr (m0_araddr),
        .m0_axi_arlen (m0_arlen), .m0_axi_arsize (m0_arsize),
        .m0_axi_arburst (m0_arburst), .m0_axi_arprot (m0_arprot),
        .m0_axi_arvalid (m0_arvalid), .m0_axi_arready (m0_arready),
        .m0_axi_rid (m0_rid), .m0_axi_rdata (m0_rdata),
        .m0_axi_rresp (m0_rresp), .m0_axi_rlast (m0_rlast),
        .m0_axi_rvalid (m0_rvalid), .m0_axi_rready (m0_rready),

        .m1_axi_awid (m1_awid), .m1_axi_awaddr (m1_awaddr),
        .m1_axi_awlen (m1_awlen), .m1_axi_awsize (m1_awsize),
        .m1_axi_awburst (m1_awburst), .m1_axi_awprot (m1_awprot),
        .m1_axi_awvalid (m1_awvalid), .m1_axi_awready (m1_awready),
        .m1_axi_wdata (m1_wdata), .m1_axi_wstrb (m1_wstrb),
        .m1_axi_wlast (m1_wlast), .m1_axi_wvalid (m1_wvalid),
        .m1_axi_wready (m1_wready),
        .m1_axi_bid (m1_bid), .m1_axi_bresp (m1_bresp),
        .m1_axi_bvalid (m1_bvalid), .m1_axi_bready (m1_bready),
        .m1_axi_arid (m1_arid), .m1_axi_araddr (m1_araddr),
        .m1_axi_arlen (m1_arlen), .m1_axi_arsize (m1_arsize),
        .m1_axi_arburst (m1_arburst), .m1_axi_arprot (m1_arprot),
        .m1_axi_arvalid (m1_arvalid), .m1_axi_arready (m1_arready),
        .m1_axi_rid (m1_rid), .m1_axi_rdata (m1_rdata),
        .m1_axi_rresp (m1_rresp), .m1_axi_rlast (m1_rlast),
        .m1_axi_rvalid (m1_rvalid), .m1_axi_rready (m1_rready)
    );

    // =========================================================================
    // Environment legality. P7 (idroute) needs none of this -- it is a pure mux
    // property -- but P1 and P2 reason about the DUT's captured state, and a
    // slave that invents responses for transactions it never accepted can drive
    // that state anywhere. These assumptions say only what real AXI requires,
    // plus the single-outstanding scope SPEC.md section 11 documents.
    // =========================================================================
// Only the `decode` property reasons about the DUT's captured per-master state
// and therefore needs the full burst-accurate environment below. `reset` needs
// nothing but the in-reset quiet rule, and `idroute` needs no assumptions at
// all -- it is a pure mux property. Giving each property the weakest premise
// that makes it meaningful keeps the two cheap proofs both stronger AND fast:
// the queue model roughly doubles the state space and stalls PDR.
`ifdef ENV_FULL
`define CHAN_HIST(NM, WIDTH, VAL, RDY, PL)                                     \
    reg             NM``_v_q = 1'b0;                                           \
    reg             NM``_r_q = 1'b0;                                           \
    reg [WIDTH-1:0] NM``_p_q = {WIDTH{1'b0}};                                  \
    always @(posedge aclk) begin                                               \
        NM``_v_q <= VAL;  NM``_r_q <= RDY;  NM``_p_q <= PL;                    \
    end

`define CHAN_ASSUME(NM, VAL, PL)                                               \
    always @(posedge aclk)                                                     \
        if (chk && NM``_v_q && !NM``_r_q) begin                                \
            assume (VAL);                                                      \
            assume ((PL) == NM``_p_q);                                         \
        end

    // master-side address/data channels hold VALID and payload until READY
    `CHAN_HIST(s0aw, 49, s0_awvalid, s0_awready,
               {s0_awid, s0_awaddr, s0_awlen, s0_awsize, s0_awburst, s0_awprot})
    `CHAN_ASSUME(s0aw, s0_awvalid,
               {s0_awid, s0_awaddr, s0_awlen, s0_awsize, s0_awburst, s0_awprot})
    `CHAN_HIST(s0w, 37, s0_wvalid, s0_wready, {s0_wdata, s0_wstrb, s0_wlast})
    `CHAN_ASSUME(s0w, s0_wvalid, {s0_wdata, s0_wstrb, s0_wlast})
    `CHAN_HIST(s0ar, 49, s0_arvalid, s0_arready,
               {s0_arid, s0_araddr, s0_arlen, s0_arsize, s0_arburst, s0_arprot})
    `CHAN_ASSUME(s0ar, s0_arvalid,
               {s0_arid, s0_araddr, s0_arlen, s0_arsize, s0_arburst, s0_arprot})
    `CHAN_HIST(s1aw, 49, s1_awvalid, s1_awready,
               {s1_awid, s1_awaddr, s1_awlen, s1_awsize, s1_awburst, s1_awprot})
    `CHAN_ASSUME(s1aw, s1_awvalid,
               {s1_awid, s1_awaddr, s1_awlen, s1_awsize, s1_awburst, s1_awprot})
    `CHAN_HIST(s1w, 37, s1_wvalid, s1_wready, {s1_wdata, s1_wstrb, s1_wlast})
    `CHAN_ASSUME(s1w, s1_wvalid, {s1_wdata, s1_wstrb, s1_wlast})
    `CHAN_HIST(s1ar, 49, s1_arvalid, s1_arready,
               {s1_arid, s1_araddr, s1_arlen, s1_arsize, s1_arburst, s1_arprot})
    `CHAN_ASSUME(s1ar, s1_arvalid,
               {s1_arid, s1_araddr, s1_arlen, s1_arsize, s1_arburst, s1_arprot})

    // slave-side response channels hold VALID and payload until READY
    `CHAN_HIST(m0b, ID_WIDTH+3, m0_bvalid, m0_bready, {m0_bid, m0_bresp})
    `CHAN_ASSUME(m0b, m0_bvalid, {m0_bid, m0_bresp})
    `CHAN_HIST(m0r, ID_WIDTH+36, m0_rvalid, m0_rready,
               {m0_rid, m0_rdata, m0_rresp, m0_rlast})
    `CHAN_ASSUME(m0r, m0_rvalid, {m0_rid, m0_rdata, m0_rresp, m0_rlast})
    `CHAN_HIST(m1b, ID_WIDTH+3, m1_bvalid, m1_bready, {m1_bid, m1_bresp})
    `CHAN_ASSUME(m1b, m1_bvalid, {m1_bid, m1_bresp})
    `CHAN_HIST(m1r, ID_WIDTH+36, m1_rvalid, m1_rready,
               {m1_rid, m1_rdata, m1_rresp, m1_rlast})
    `CHAN_ASSUME(m1r, m1_rvalid, {m1_rid, m1_rdata, m1_rresp, m1_rlast})

    // outstanding-transaction tracking on the slave ports
    // Up to two writes can be outstanding at one slave port (each master is
    // single-outstanding, and the AW/W grant is released at WLAST while the B is
    // still in flight). A real slave answers them IN ORDER and reflects each
    // ID, so the environment model is a depth-2 queue of the ID top bits plus a
    // count of writes whose WLAST has landed but whose B has not been sent.
    // Flat "an AW was seen / a WLAST was seen" flags are not enough: they let
    // one master's WLAST and another master's AW jointly authorise a B that
    // belongs to neither transaction.
    reg m0_rd_out = 1'b0, m1_rd_out = 1'b0;
    reg [2:0] m0_b_due = 3'd0, m1_b_due = 3'd0;
    // per-master W-phase tracking: a master sends W beats only for a burst
    // whose AW it has already issued, and WLAST lands on the last beat
    reg        s0_w_active = 1'b0, s1_w_active = 1'b0;
    reg [7:0]  s0_awlen_q  = 8'd0, s1_awlen_q  = 8'd0;
    reg [8:0]  s0_wbeat    = 9'd0, s1_wbeat    = 9'd0;

    // Depth-2 in-order queue of the ID top bits a slave port was handed. The DUT
    // steers B and R purely by the response ID's top bit, so a slave that
    // invented an ID would redirect a response to the wrong master port and
    // clear that master's in-flight tracking. Real AXI slaves reflect the ID
    // (SPEC.md F16), and axi4_mem_slave does; this states that as a premise.
`define IDQ(NM, PUSH, PUSHVAL, POP)                                            \
    reg       NM``_a = 1'b0, NM``_b = 1'b0;                                    \
    reg [2:0] NM``_n = 3'd0;                                                   \
    always @(posedge aclk) begin                                               \
        if (!aresetn) begin                                                    \
            NM``_a <= 1'b0; NM``_b <= 1'b0; NM``_n <= 3'd0;                    \
        end else begin                                                         \
            case ({PUSH, POP})                                                 \
                2'b10: begin                                                   \
                    if (NM``_n == 3'd0) NM``_a <= PUSHVAL;                     \
                    else                NM``_b <= PUSHVAL;                     \
                    NM``_n <= NM``_n + 3'd1;                                   \
                end                                                            \
                2'b01: begin                                                   \
                    NM``_a <= NM``_b;                                          \
                    NM``_n <= NM``_n - 3'd1;                                   \
                end                                                            \
                2'b11: begin                                                   \
                    if (NM``_n == 3'd1)      NM``_a <= PUSHVAL;                \
                    else if (NM``_n >= 3'd2) begin                             \
                        NM``_a <= NM``_b; NM``_b <= PUSHVAL;                   \
                    end                                                        \
                end                                                            \
                default: ;                                                     \
            endcase                                                            \
        end                                                                    \
    end

    `IDQ(m0wq, m0_awvalid && m0_awready, m0_awid[ID_WIDTH],
               m0_bvalid && m0_bready)
    `IDQ(m1wq, m1_awvalid && m1_awready, m1_awid[ID_WIDTH],
               m1_bvalid && m1_bready)
    `IDQ(m0rq, m0_arvalid && m0_arready, m0_arid[ID_WIDTH],
               m0_rvalid && m0_rready && m0_rlast)
    `IDQ(m1rq, m1_arvalid && m1_arready, m1_arid[ID_WIDTH],
               m1_rvalid && m1_rready && m1_rlast)

    always @(posedge aclk) begin
        if (!aresetn) begin
            m0_rd_out <= 1'b0; m0_b_due <= 3'd0;
            m1_rd_out <= 1'b0; m1_b_due <= 3'd0;
            s0_w_active <= 1'b0; s0_awlen_q <= 8'd0; s0_wbeat <= 9'd0;
            s1_w_active <= 1'b0; s1_awlen_q <= 8'd0; s1_wbeat <= 9'd0;
        end else begin
            // a write becomes answerable when its WLAST lands; the B clears it
            case ({m0_wvalid && m0_wready && m0_wlast, m0_bvalid && m0_bready})
                2'b10:   m0_b_due <= m0_b_due + 3'd1;
                2'b01:   m0_b_due <= m0_b_due - 3'd1;
                default: m0_b_due <= m0_b_due;
            endcase
            case ({m1_wvalid && m1_wready && m1_wlast, m1_bvalid && m1_bready})
                2'b10:   m1_b_due <= m1_b_due + 3'd1;
                2'b01:   m1_b_due <= m1_b_due - 3'd1;
                default: m1_b_due <= m1_b_due;
            endcase
            if (m0_arvalid && m0_arready)                    m0_rd_out <= 1'b1;
            else if (m0_rvalid && m0_rready && m0_rlast)     m0_rd_out <= 1'b0;
            if (m1_arvalid && m1_arready)                    m1_rd_out <= 1'b1;
            else if (m1_rvalid && m1_rready && m1_rlast)     m1_rd_out <= 1'b0;


            if (s0_awvalid && s0_awready) begin
                s0_w_active <= 1'b1; s0_awlen_q <= s0_awlen; s0_wbeat <= 9'd0;
            end else if (s0_wvalid && s0_wready) begin
                if (s0_wlast) s0_w_active <= 1'b0;
                else          s0_wbeat    <= s0_wbeat + 9'd1;
            end
            if (s1_awvalid && s1_awready) begin
                s1_w_active <= 1'b1; s1_awlen_q <= s1_awlen; s1_wbeat <= 9'd0;
            end else if (s1_wvalid && s1_wready) begin
                if (s1_wlast) s1_w_active <= 1'b0;
                else          s1_wbeat    <= s1_wbeat + 9'd1;
            end
        end
    end

`endif // ENV_FULL

    // A real slave holds its VALIDs low in reset just as the DUT must (PC12).
    // Without this the reset window is entirely unconstrained, and since the B
    // return path is a combinational mux off the slave's BVALID, a slave that
    // shouted during reset would propagate straight to the master port.
    always @(posedge aclk) begin
        if (!aresetn) begin
            assume (!m0_bvalid); assume (!m0_rvalid);
            assume (!m1_bvalid); assume (!m1_rvalid);
            assume (!s0_awvalid); assume (!s0_wvalid); assume (!s0_arvalid);
            assume (!s1_awvalid); assume (!s1_wvalid); assume (!s1_arvalid);
        end
    end

`ifdef ENV_FULL
    // Gated on `aresetn`, NOT on `chk`: the tracking registers below are cleared
    // by reset and are therefore already meaningful in the first cycle after
    // reset releases. Using `chk` here leaves a one-cycle hole at the reset
    // boundary in which a slave may answer a transaction that never happened.
    always @(posedge aclk) begin
        if (aresetn) begin
            // slaves answer only writes whose WLAST they have taken
            assume (!m0_bvalid || (m0_b_due != 3'd0));
            assume (!m1_bvalid || (m1_b_due != 3'd0));
            assume (!m0_rvalid || m0_rd_out);
            assume (!m1_rvalid || m1_rd_out);
            // and answer in order, reflecting the ID they were handed (F16)
            assume (!m0_bvalid || (m0wq_n != 3'd0 && m0_bid[ID_WIDTH] == m0wq_a));
            assume (!m1_bvalid || (m1wq_n != 3'd0 && m1_bid[ID_WIDTH] == m1wq_a));
            assume (!m0_rvalid || (m0rq_n != 3'd0 && m0_rid[ID_WIDTH] == m0rq_a));
            assume (!m1_rvalid || (m1rq_n != 3'd0 && m1_rid[ID_WIDTH] == m1rq_a));
            // the depth-2 queues are only a sound model if the DUT never has
            // more than two writes/reads outstanding at one slave port
            assert (m0wq_n <= 3'd2); assert (m1wq_n <= 3'd2);
            assert (m0rq_n <= 3'd2); assert (m1rq_n <= 3'd2);
            // masters send W beats only for a burst they have addressed, and
            // put WLAST on exactly the (AWLEN+1)-th beat
            assume (!s0_wvalid || s0_w_active);
            assume (!s1_wvalid || s1_w_active);
            if (s0_wvalid) assume (s0_wlast == (s0_wbeat == s0_awlen_q));
            if (s1_wvalid) assume (s1_wlast == (s1_wbeat == s1_awlen_q));
        end
    end
`endif // ENV_FULL

    // -------------------------------------------------------------------------
    // P1: nothing the DUT drives may be asserted during reset
    // -------------------------------------------------------------------------
`ifdef PROP_RESET
    always @(posedge aclk) begin
        if (!aresetn && rstcnt >= 4'd1) begin
            assert (!m0_awvalid); assert (!m0_wvalid); assert (!m0_arvalid);
            assert (!m1_awvalid); assert (!m1_wvalid); assert (!m1_arvalid);
            assert (!s0_bvalid);  assert (!s0_rvalid);
            assert (!s1_bvalid);  assert (!s1_rvalid);
        end
    end
`endif

    // -------------------------------------------------------------------------
    // P2: address decode -- no transaction can reach the wrong slave
    // -------------------------------------------------------------------------
`ifdef PROP_DECODE
    always @(posedge aclk) begin
        if (chk) begin
            if (m0_awvalid) assert (m0_awaddr[31:12] == 20'h00000);
            if (m0_arvalid) assert (m0_araddr[31:12] == 20'h00000);
            if (m1_awvalid) assert (m1_awaddr[31:12] == 20'h00001);
            if (m1_arvalid) assert (m1_araddr[31:12] == 20'h00001);
        end
    end
`endif

    // -------------------------------------------------------------------------
    // P7: ID routing. A response consumed from a slave port must land, in the
    // same cycle, on the master its ID's top bit names -- with the master's own
    // ID restored in the low bits and the payload passed through unaltered.
    // Needs no environment assumptions: it is a property of the DUT's mux.
    // -------------------------------------------------------------------------
`ifdef PROP_IDROUTE
    always @(posedge aclk) begin
        if (chk) begin
            // write responses out of slave port 0
            if (m0_bvalid && m0_bready) begin
                if (m0_bid[ID_WIDTH] == 1'b0) begin
                    assert (s0_bvalid && s0_bready);
                    assert (s0_bid   == m0_bid[ID_WIDTH-1:0]);
                    assert (s0_bresp == m0_bresp);
                end else begin
                    assert (s1_bvalid && s1_bready);
                    assert (s1_bid   == m0_bid[ID_WIDTH-1:0]);
                    assert (s1_bresp == m0_bresp);
                end
            end
            // write responses out of slave port 1
            if (m1_bvalid && m1_bready) begin
                if (m1_bid[ID_WIDTH] == 1'b0) begin
                    assert (s0_bvalid && s0_bready);
                    assert (s0_bid   == m1_bid[ID_WIDTH-1:0]);
                    assert (s0_bresp == m1_bresp);
                end else begin
                    assert (s1_bvalid && s1_bready);
                    assert (s1_bid   == m1_bid[ID_WIDTH-1:0]);
                    assert (s1_bresp == m1_bresp);
                end
            end
            // read beats out of slave port 0
            if (m0_rvalid && m0_rready) begin
                if (m0_rid[ID_WIDTH] == 1'b0) begin
                    assert (s0_rvalid && s0_rready);
                    assert (s0_rid   == m0_rid[ID_WIDTH-1:0]);
                    assert (s0_rdata == m0_rdata);
                    assert (s0_rresp == m0_rresp);
                    assert (s0_rlast == m0_rlast);
                end else begin
                    assert (s1_rvalid && s1_rready);
                    assert (s1_rid   == m0_rid[ID_WIDTH-1:0]);
                    assert (s1_rdata == m0_rdata);
                    assert (s1_rresp == m0_rresp);
                    assert (s1_rlast == m0_rlast);
                end
            end
            // read beats out of slave port 1
            if (m1_rvalid && m1_rready) begin
                if (m1_rid[ID_WIDTH] == 1'b0) begin
                    assert (s0_rvalid && s0_rready);
                    assert (s0_rid   == m1_rid[ID_WIDTH-1:0]);
                    assert (s0_rdata == m1_rdata);
                    assert (s0_rresp == m1_rresp);
                    assert (s0_rlast == m1_rlast);
                end else begin
                    assert (s1_rvalid && s1_rready);
                    assert (s1_rid   == m1_rid[ID_WIDTH-1:0]);
                    assert (s1_rdata == m1_rdata);
                    assert (s1_rresp == m1_rresp);
                    assert (s1_rlast == m1_rlast);
                end
            end
        end
    end
`endif

endmodule
