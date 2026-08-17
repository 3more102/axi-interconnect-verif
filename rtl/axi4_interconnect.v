// =============================================================================
// axi4_interconnect.v
// Full AXI4 2-master x (2-slave + internal DECERR default slave) crossbar.
// Implements SPEC.md section 5.
//
//   s0_axi_* / s1_axi_* : AXI4 slave ports (the two masters connect here),
//                         ID width = ID_WIDTH
//   m0_axi_* / m1_axi_* : AXI4 master ports (the two slaves connect here),
//                         ID width = ID_WIDTH+1
//
// Address decode (SPEC.md section 1), on addr[31:12]:
//   20'h00000 -> m0 port (S0 device)
//   20'h00001 -> m1 port (S1 device)
//   else      -> internal burst-capable DECERR default slave
//
// ID routing:
//   slave-side awid/arid = {master_index, master_id} (master_index: 1 bit,
//   0 for s0, 1 for s1). B routed back by bid[ID_WIDTH], R by rid[ID_WIDTH];
//   each master sees its original low ID_WIDTH bits.
//
// Write path:
//   Each master port accepts one AW into a holding register (this is its
//   single outstanding write; s*_axi_awready = ~write-in-flight, a purely
//   registered gate). Per destination, a registered round-robin arbiter
//   claims a grant for one captured AW; the grant is held from claim through
//   the destination WLAST handshake (AW and W of the winner are routed
//   together, no W interleaving; W is forwarded only after the destination
//   AW handshake). After WLAST the AW/W path re-arbitrates. B returns
//   independently, routed by BID MSB.
//
// Read path:
//   Same per-destination registered round-robin arbitration of captured ARs;
//   the grant is released once the destination AR handshake completes
//   (address-phase lock only). The R return mux of each MASTER port locks to
//   one source from the first R beat until RLAST (registered lock).
//
// One outstanding write and one outstanding read per master port.
// Round-robin fairness: after a master completes on a destination, the other
// master has priority next time both request that destination.
//
// All grant/lock state is registered. No master-port ready output is derived
// combinationally from any signal that depends on that same ready.
// Strict Verilog-2001: synchronous active-low reset, no initial, no delays.
// =============================================================================

module axi4_interconnect #(
    parameter ID_WIDTH = 4            // master-side ID width; slave-side is ID_WIDTH+1
)(
    input  wire                 aclk,
    input  wire                 aresetn,

    // -------------------------------------------------------------------------
    // s0_axi_* : AXI4 slave port 0 (master 0 connects here), ID width ID_WIDTH
    // -------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]  s0_axi_awid,
    input  wire [31:0]          s0_axi_awaddr,
    input  wire [7:0]           s0_axi_awlen,
    input  wire [2:0]           s0_axi_awsize,
    input  wire [1:0]           s0_axi_awburst,
    input  wire [2:0]           s0_axi_awprot,
    input  wire                 s0_axi_awvalid,
    output wire                 s0_axi_awready,
    input  wire [31:0]          s0_axi_wdata,
    input  wire [3:0]           s0_axi_wstrb,
    input  wire                 s0_axi_wlast,
    input  wire                 s0_axi_wvalid,
    output wire                 s0_axi_wready,
    output wire [ID_WIDTH-1:0]  s0_axi_bid,
    output wire [1:0]           s0_axi_bresp,
    output wire                 s0_axi_bvalid,
    input  wire                 s0_axi_bready,
    input  wire [ID_WIDTH-1:0]  s0_axi_arid,
    input  wire [31:0]          s0_axi_araddr,
    input  wire [7:0]           s0_axi_arlen,
    input  wire [2:0]           s0_axi_arsize,
    input  wire [1:0]           s0_axi_arburst,
    input  wire [2:0]           s0_axi_arprot,
    input  wire                 s0_axi_arvalid,
    output wire                 s0_axi_arready,
    output wire [ID_WIDTH-1:0]  s0_axi_rid,
    output wire [31:0]          s0_axi_rdata,
    output wire [1:0]           s0_axi_rresp,
    output wire                 s0_axi_rlast,
    output wire                 s0_axi_rvalid,
    input  wire                 s0_axi_rready,

    // -------------------------------------------------------------------------
    // s1_axi_* : AXI4 slave port 1 (master 1 connects here), ID width ID_WIDTH
    // -------------------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]  s1_axi_awid,
    input  wire [31:0]          s1_axi_awaddr,
    input  wire [7:0]           s1_axi_awlen,
    input  wire [2:0]           s1_axi_awsize,
    input  wire [1:0]           s1_axi_awburst,
    input  wire [2:0]           s1_axi_awprot,
    input  wire                 s1_axi_awvalid,
    output wire                 s1_axi_awready,
    input  wire [31:0]          s1_axi_wdata,
    input  wire [3:0]           s1_axi_wstrb,
    input  wire                 s1_axi_wlast,
    input  wire                 s1_axi_wvalid,
    output wire                 s1_axi_wready,
    output wire [ID_WIDTH-1:0]  s1_axi_bid,
    output wire [1:0]           s1_axi_bresp,
    output wire                 s1_axi_bvalid,
    input  wire                 s1_axi_bready,
    input  wire [ID_WIDTH-1:0]  s1_axi_arid,
    input  wire [31:0]          s1_axi_araddr,
    input  wire [7:0]           s1_axi_arlen,
    input  wire [2:0]           s1_axi_arsize,
    input  wire [1:0]           s1_axi_arburst,
    input  wire [2:0]           s1_axi_arprot,
    input  wire                 s1_axi_arvalid,
    output wire                 s1_axi_arready,
    output wire [ID_WIDTH-1:0]  s1_axi_rid,
    output wire [31:0]          s1_axi_rdata,
    output wire [1:0]           s1_axi_rresp,
    output wire                 s1_axi_rlast,
    output wire                 s1_axi_rvalid,
    input  wire                 s1_axi_rready,

    // -------------------------------------------------------------------------
    // m0_axi_* : AXI4 master port 0 (slave S0 connects here), ID width ID_WIDTH+1
    // -------------------------------------------------------------------------
    output wire [ID_WIDTH:0]    m0_axi_awid,
    output wire [31:0]          m0_axi_awaddr,
    output wire [7:0]           m0_axi_awlen,
    output wire [2:0]           m0_axi_awsize,
    output wire [1:0]           m0_axi_awburst,
    output wire [2:0]           m0_axi_awprot,
    output wire                 m0_axi_awvalid,
    input  wire                 m0_axi_awready,
    output wire [31:0]          m0_axi_wdata,
    output wire [3:0]           m0_axi_wstrb,
    output wire                 m0_axi_wlast,
    output wire                 m0_axi_wvalid,
    input  wire                 m0_axi_wready,
    input  wire [ID_WIDTH:0]    m0_axi_bid,
    input  wire [1:0]           m0_axi_bresp,
    input  wire                 m0_axi_bvalid,
    output wire                 m0_axi_bready,
    output wire [ID_WIDTH:0]    m0_axi_arid,
    output wire [31:0]          m0_axi_araddr,
    output wire [7:0]           m0_axi_arlen,
    output wire [2:0]           m0_axi_arsize,
    output wire [1:0]           m0_axi_arburst,
    output wire [2:0]           m0_axi_arprot,
    output wire                 m0_axi_arvalid,
    input  wire                 m0_axi_arready,
    input  wire [ID_WIDTH:0]    m0_axi_rid,
    input  wire [31:0]          m0_axi_rdata,
    input  wire [1:0]           m0_axi_rresp,
    input  wire                 m0_axi_rlast,
    input  wire                 m0_axi_rvalid,
    output wire                 m0_axi_rready,

    // -------------------------------------------------------------------------
    // m1_axi_* : AXI4 master port 1 (slave S1 connects here), ID width ID_WIDTH+1
    // -------------------------------------------------------------------------
    output wire [ID_WIDTH:0]    m1_axi_awid,
    output wire [31:0]          m1_axi_awaddr,
    output wire [7:0]           m1_axi_awlen,
    output wire [2:0]           m1_axi_awsize,
    output wire [1:0]           m1_axi_awburst,
    output wire [2:0]           m1_axi_awprot,
    output wire                 m1_axi_awvalid,
    input  wire                 m1_axi_awready,
    output wire [31:0]          m1_axi_wdata,
    output wire [3:0]           m1_axi_wstrb,
    output wire                 m1_axi_wlast,
    output wire                 m1_axi_wvalid,
    input  wire                 m1_axi_wready,
    input  wire [ID_WIDTH:0]    m1_axi_bid,
    input  wire [1:0]           m1_axi_bresp,
    input  wire                 m1_axi_bvalid,
    output wire                 m1_axi_bready,
    output wire [ID_WIDTH:0]    m1_axi_arid,
    output wire [31:0]          m1_axi_araddr,
    output wire [7:0]           m1_axi_arlen,
    output wire [2:0]           m1_axi_arsize,
    output wire [1:0]           m1_axi_arburst,
    output wire [2:0]           m1_axi_arprot,
    output wire                 m1_axi_arvalid,
    input  wire                 m1_axi_arready,
    input  wire [ID_WIDTH:0]    m1_axi_rid,
    input  wire [31:0]          m1_axi_rdata,
    input  wire [1:0]           m1_axi_rresp,
    input  wire                 m1_axi_rlast,
    input  wire                 m1_axi_rvalid,
    output wire                 m1_axi_rready
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    localparam [1:0] D_M0  = 2'd0;    // destination: m0 port (S0 device)
    localparam [1:0] D_M1  = 2'd1;    // destination: m1 port (S1 device)
    localparam [1:0] D_DEF = 2'd2;    // destination: internal default slave

    localparam [1:0] RESP_DECERR = 2'b11;

    // default-slave write engine states
    localparam [1:0] DW_IDLE = 2'd0;
    localparam [1:0] DW_DATA = 2'd1;
    localparam [1:0] DW_RESP = 2'd2;

    // default-slave read engine states
    localparam DR_IDLE = 1'b0;
    localparam DR_DATA = 1'b1;

    // Address decode per SPEC.md section 1
    function [1:0] decode_dest;
        input [31:0] addr;
        begin
            if (addr[31:12] == 20'h00000)
                decode_dest = D_M0;
            else if (addr[31:12] == 20'h00001)
                decode_dest = D_M1;
            else
                decode_dest = D_DEF;
        end
    endfunction

    // -------------------------------------------------------------------------
    // State declarations
    // -------------------------------------------------------------------------

    // master-port write front-ends (one outstanding write per master port)
    reg               wr_active0, wr_active1;  // AW accepted .. B handshake
    reg               aw_pend0,   aw_pend1;    // captured AW awaiting delivery
    reg  [1:0]        aw_dest0,   aw_dest1;
    reg  [ID_WIDTH:0] aw_id0,     aw_id1;      // {master_index, master_id}
    reg  [31:0]       aw_addr0,   aw_addr1;
    reg  [7:0]        aw_len0,    aw_len1;
    reg  [2:0]        aw_size0,   aw_size1;
    reg  [1:0]        aw_burst0,  aw_burst1;
    reg  [2:0]        aw_prot0,   aw_prot1;

    // master-port read front-ends (one outstanding read per master port)
    reg               rd_active0, rd_active1;  // AR accepted .. RLAST handshake
    reg               ar_pend0,   ar_pend1;    // captured AR awaiting delivery
    reg  [1:0]        ar_dest0,   ar_dest1;
    reg  [ID_WIDTH:0] ar_id0,     ar_id1;
    reg  [31:0]       ar_addr0,   ar_addr1;
    reg  [7:0]        ar_len0,    ar_len1;
    reg  [2:0]        ar_size0,   ar_size1;
    reg  [1:0]        ar_burst0,  ar_burst1;
    reg  [2:0]        ar_prot0,   ar_prot1;

    // per-destination write grants (owner: 0 = master 0, 1 = master 1;
    // w_rr_*: which master has priority next time both request)
    reg               wgrant_valid_m0,  wgrant_owner_m0,  w_rr_m0;
    reg               wgrant_valid_m1,  wgrant_owner_m1,  w_rr_m1;
    reg               wgrant_valid_def, wgrant_owner_def, w_rr_def;

    // per-destination read grants (address-phase lock only)
    reg               rgrant_valid_m0,  rgrant_owner_m0,  r_rr_m0;
    reg               rgrant_valid_m1,  rgrant_owner_m1,  r_rr_m1;
    reg               rgrant_valid_def, rgrant_owner_def, r_rr_def;

    // B return select per master port (combinational)
    reg               b_sel_valid0, b_sel_valid1;
    reg  [1:0]        b_sel0,       b_sel1;

    // R return select per master port + per-burst source lock (registered)
    reg               rlock0, rlock1;
    reg  [1:0]        rsrc0,  rsrc1;
    reg               r_sel_valid0, r_sel_valid1;
    reg  [1:0]        r_sel0,       r_sel1;

    // internal default slave state
    reg  [1:0]        def_wstate;
    reg  [ID_WIDTH:0] def_bid_r;
    reg               def_rstate;
    reg  [ID_WIDTH:0] def_rid_r;
    reg  [7:0]        def_rlen_r;
    reg  [7:0]        def_rcnt;

    // -------------------------------------------------------------------------
    // Wire declarations
    // -------------------------------------------------------------------------

    // internal default slave interface (mirrors an m-port, ID width ID_WIDTH+1)
    wire              def_awvalid, def_awready;
    wire [ID_WIDTH:0] def_awid;
    wire              def_wvalid, def_wready, def_wlast;
    wire [ID_WIDTH:0] def_bid;
    wire [1:0]        def_bresp;
    wire              def_bvalid, def_bready;
    wire              def_arvalid, def_arready;
    wire [ID_WIDTH:0] def_arid;
    wire [7:0]        def_arlen;
    wire [ID_WIDTH:0] def_rid;
    wire [31:0]       def_rdata;
    wire [1:0]        def_rresp;
    wire              def_rlast, def_rvalid, def_rready;

    // write-path request / ownership / event wires
    wire wreq0_m0,  wreq1_m0;
    wire wreq0_m1,  wreq1_m1;
    wire wreq0_def, wreq1_def;
    wire aw_pend_own_m0, aw_pend_own_m1, aw_pend_own_def;
    wire awfire_m0, awfire_m1, awfire_def;
    wire aw0_deliver, aw1_deliver;
    wire wlast_fire_m0, wlast_fire_m1, wlast_fire_def;

    // read-path request / ownership / event wires
    wire rreq0_m0,  rreq1_m0;
    wire rreq0_m1,  rreq1_m1;
    wire rreq0_def, rreq1_def;
    wire ar_pend_own_m0, ar_pend_own_m1, ar_pend_own_def;
    wire arfire_m0, arfire_m1, arfire_def;
    wire ar0_deliver, ar1_deliver;

    // R candidate hits (source has an R beat for the given master port)
    wire rhit0_m0, rhit0_m1, rhit0_def;
    wire rhit1_m0, rhit1_m1, rhit1_def;

    // =========================================================================
    // WRITE PATH
    // =========================================================================

    // ---- master-port AW acceptance gates (purely registered state) ----------
    assign s0_axi_awready = aresetn && !wr_active0;
    assign s1_axi_awready = aresetn && !wr_active1;

    // ---- per-destination write requests -------------------------------------
    assign wreq0_m0  = aw_pend0 && (aw_dest0 == D_M0);
    assign wreq1_m0  = aw_pend1 && (aw_dest1 == D_M0);
    assign wreq0_m1  = aw_pend0 && (aw_dest0 == D_M1);
    assign wreq1_m1  = aw_pend1 && (aw_dest1 == D_M1);
    assign wreq0_def = aw_pend0 && (aw_dest0 == D_DEF);
    assign wreq1_def = aw_pend1 && (aw_dest1 == D_DEF);

    assign aw_pend_own_m0  = wgrant_owner_m0  ? aw_pend1 : aw_pend0;
    assign aw_pend_own_m1  = wgrant_owner_m1  ? aw_pend1 : aw_pend0;
    assign aw_pend_own_def = wgrant_owner_def ? aw_pend1 : aw_pend0;

    // ---- AW forwarding to destinations (registered grant + captured payload)
    assign m0_axi_awid    = wgrant_owner_m0 ? aw_id1    : aw_id0;
    assign m0_axi_awaddr  = wgrant_owner_m0 ? aw_addr1  : aw_addr0;
    assign m0_axi_awlen   = wgrant_owner_m0 ? aw_len1   : aw_len0;
    assign m0_axi_awsize  = wgrant_owner_m0 ? aw_size1  : aw_size0;
    assign m0_axi_awburst = wgrant_owner_m0 ? aw_burst1 : aw_burst0;
    assign m0_axi_awprot  = wgrant_owner_m0 ? aw_prot1  : aw_prot0;
    assign m0_axi_awvalid = wgrant_valid_m0 && aw_pend_own_m0;

    assign m1_axi_awid    = wgrant_owner_m1 ? aw_id1    : aw_id0;
    assign m1_axi_awaddr  = wgrant_owner_m1 ? aw_addr1  : aw_addr0;
    assign m1_axi_awlen   = wgrant_owner_m1 ? aw_len1   : aw_len0;
    assign m1_axi_awsize  = wgrant_owner_m1 ? aw_size1  : aw_size0;
    assign m1_axi_awburst = wgrant_owner_m1 ? aw_burst1 : aw_burst0;
    assign m1_axi_awprot  = wgrant_owner_m1 ? aw_prot1  : aw_prot0;
    assign m1_axi_awvalid = wgrant_valid_m1 && aw_pend_own_m1;

    assign def_awid    = wgrant_owner_def ? aw_id1 : aw_id0;
    assign def_awvalid = wgrant_valid_def && aw_pend_own_def;

    // ---- AW delivery events -------------------------------------------------
    assign awfire_m0  = m0_axi_awvalid && m0_axi_awready;
    assign awfire_m1  = m1_axi_awvalid && m1_axi_awready;
    assign awfire_def = def_awvalid    && def_awready;

    assign aw0_deliver = (awfire_m0  && !wgrant_owner_m0)
                      || (awfire_m1  && !wgrant_owner_m1)
                      || (awfire_def && !wgrant_owner_def);
    assign aw1_deliver = (awfire_m0  &&  wgrant_owner_m0)
                      || (awfire_m1  &&  wgrant_owner_m1)
                      || (awfire_def &&  wgrant_owner_def);

    // ---- W forwarding: locked to the grant owner, only after AW delivered ---
    assign m0_axi_wdata  = wgrant_owner_m0 ? s1_axi_wdata : s0_axi_wdata;
    assign m0_axi_wstrb  = wgrant_owner_m0 ? s1_axi_wstrb : s0_axi_wstrb;
    assign m0_axi_wlast  = wgrant_owner_m0 ? s1_axi_wlast : s0_axi_wlast;
    assign m0_axi_wvalid = wgrant_valid_m0 && !aw_pend_own_m0 &&
                           (wgrant_owner_m0 ? s1_axi_wvalid : s0_axi_wvalid);

    assign m1_axi_wdata  = wgrant_owner_m1 ? s1_axi_wdata : s0_axi_wdata;
    assign m1_axi_wstrb  = wgrant_owner_m1 ? s1_axi_wstrb : s0_axi_wstrb;
    assign m1_axi_wlast  = wgrant_owner_m1 ? s1_axi_wlast : s0_axi_wlast;
    assign m1_axi_wvalid = wgrant_valid_m1 && !aw_pend_own_m1 &&
                           (wgrant_owner_m1 ? s1_axi_wvalid : s0_axi_wvalid);

    assign def_wlast  = wgrant_owner_def ? s1_axi_wlast : s0_axi_wlast;
    assign def_wvalid = wgrant_valid_def && !aw_pend_own_def &&
                        (wgrant_owner_def ? s1_axi_wvalid : s0_axi_wvalid);

    // ---- W ready back-routing to the masters --------------------------------
    // A master's single outstanding write means at most one destination grant
    // can be owned by it at any time, so these OR terms are one-hot.
    assign s0_axi_wready =
        (wgrant_valid_m0  && !wgrant_owner_m0  && !aw_pend0 && m0_axi_wready) ||
        (wgrant_valid_m1  && !wgrant_owner_m1  && !aw_pend0 && m1_axi_wready) ||
        (wgrant_valid_def && !wgrant_owner_def && !aw_pend0 && def_wready);
    assign s1_axi_wready =
        (wgrant_valid_m0  &&  wgrant_owner_m0  && !aw_pend1 && m0_axi_wready) ||
        (wgrant_valid_m1  &&  wgrant_owner_m1  && !aw_pend1 && m1_axi_wready) ||
        (wgrant_valid_def &&  wgrant_owner_def && !aw_pend1 && def_wready);

    // ---- WLAST completion events (release the AW/W grant) -------------------
    assign wlast_fire_m0  = m0_axi_wvalid && m0_axi_wready && m0_axi_wlast;
    assign wlast_fire_m1  = m1_axi_wvalid && m1_axi_wready && m1_axi_wlast;
    assign wlast_fire_def = def_wvalid    && def_wready    && def_wlast;

    // ---- master-port write front-end sequencers -----------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_active0 <= 1'b0;
            aw_pend0   <= 1'b0;
            aw_dest0   <= D_M0;
            aw_id0     <= {(ID_WIDTH+1){1'b0}};
            aw_addr0   <= 32'd0;
            aw_len0    <= 8'd0;
            aw_size0   <= 3'd0;
            aw_burst0  <= 2'd0;
            aw_prot0   <= 3'd0;
        end else begin
            if (s0_axi_awvalid && s0_axi_awready) begin
                wr_active0 <= 1'b1;
                aw_pend0   <= 1'b1;
                aw_dest0   <= decode_dest(s0_axi_awaddr);
                aw_id0     <= {1'b0, s0_axi_awid};
                aw_addr0   <= s0_axi_awaddr;
                aw_len0    <= s0_axi_awlen;
                aw_size0   <= s0_axi_awsize;
                aw_burst0  <= s0_axi_awburst;
                aw_prot0   <= s0_axi_awprot;
            end else if (aw0_deliver) begin
                aw_pend0 <= 1'b0;
            end
            if (s0_axi_bvalid && s0_axi_bready)
                wr_active0 <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_active1 <= 1'b0;
            aw_pend1   <= 1'b0;
            aw_dest1   <= D_M0;
            aw_id1     <= {(ID_WIDTH+1){1'b0}};
            aw_addr1   <= 32'd0;
            aw_len1    <= 8'd0;
            aw_size1   <= 3'd0;
            aw_burst1  <= 2'd0;
            aw_prot1   <= 3'd0;
        end else begin
            if (s1_axi_awvalid && s1_axi_awready) begin
                wr_active1 <= 1'b1;
                aw_pend1   <= 1'b1;
                aw_dest1   <= decode_dest(s1_axi_awaddr);
                aw_id1     <= {1'b1, s1_axi_awid};
                aw_addr1   <= s1_axi_awaddr;
                aw_len1    <= s1_axi_awlen;
                aw_size1   <= s1_axi_awsize;
                aw_burst1  <= s1_axi_awburst;
                aw_prot1   <= s1_axi_awprot;
            end else if (aw1_deliver) begin
                aw_pend1 <= 1'b0;
            end
            if (s1_axi_bvalid && s1_axi_bready)
                wr_active1 <= 1'b0;
        end
    end

    // ---- per-destination write grant arbiters (registered, round-robin) -----
    // Grant claimed for a captured AW; held until the WLAST handshake at the
    // destination, then released and the other master gets priority.
    always @(posedge aclk) begin
        if (!aresetn) begin
            wgrant_valid_m0 <= 1'b0;
            wgrant_owner_m0 <= 1'b0;
            w_rr_m0         <= 1'b0;
        end else if (!wgrant_valid_m0) begin
            if (wreq0_m0 && wreq1_m0) begin
                wgrant_valid_m0 <= 1'b1;
                wgrant_owner_m0 <= w_rr_m0;
            end else if (wreq0_m0) begin
                wgrant_valid_m0 <= 1'b1;
                wgrant_owner_m0 <= 1'b0;
            end else if (wreq1_m0) begin
                wgrant_valid_m0 <= 1'b1;
                wgrant_owner_m0 <= 1'b1;
            end
        end else if (wlast_fire_m0) begin
            wgrant_valid_m0 <= 1'b0;
            w_rr_m0         <= ~wgrant_owner_m0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            wgrant_valid_m1 <= 1'b0;
            wgrant_owner_m1 <= 1'b0;
            w_rr_m1         <= 1'b0;
        end else if (!wgrant_valid_m1) begin
            if (wreq0_m1 && wreq1_m1) begin
                wgrant_valid_m1 <= 1'b1;
                wgrant_owner_m1 <= w_rr_m1;
            end else if (wreq0_m1) begin
                wgrant_valid_m1 <= 1'b1;
                wgrant_owner_m1 <= 1'b0;
            end else if (wreq1_m1) begin
                wgrant_valid_m1 <= 1'b1;
                wgrant_owner_m1 <= 1'b1;
            end
        end else if (wlast_fire_m1) begin
            wgrant_valid_m1 <= 1'b0;
            w_rr_m1         <= ~wgrant_owner_m1;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            wgrant_valid_def <= 1'b0;
            wgrant_owner_def <= 1'b0;
            w_rr_def         <= 1'b0;
        end else if (!wgrant_valid_def) begin
            if (wreq0_def && wreq1_def) begin
                wgrant_valid_def <= 1'b1;
                wgrant_owner_def <= w_rr_def;
            end else if (wreq0_def) begin
                wgrant_valid_def <= 1'b1;
                wgrant_owner_def <= 1'b0;
            end else if (wreq1_def) begin
                wgrant_valid_def <= 1'b1;
                wgrant_owner_def <= 1'b1;
            end
        end else if (wlast_fire_def) begin
            wgrant_valid_def <= 1'b0;
            w_rr_def         <= ~wgrant_owner_def;
        end
    end

    // ---- B return routing (decoupled from the AW/W grant): by BID MSB -------
    // One outstanding write per master port => at most one source can hold a
    // B for a given master port; the priority chain never actually arbitrates.
    always @* begin
        b_sel_valid0 = 1'b0;
        b_sel0       = D_M0;
        if (m0_axi_bvalid && (m0_axi_bid[ID_WIDTH] == 1'b0)) begin
            b_sel_valid0 = 1'b1;
            b_sel0       = D_M0;
        end else if (m1_axi_bvalid && (m1_axi_bid[ID_WIDTH] == 1'b0)) begin
            b_sel_valid0 = 1'b1;
            b_sel0       = D_M1;
        end else if (def_bvalid && (def_bid[ID_WIDTH] == 1'b0)) begin
            b_sel_valid0 = 1'b1;
            b_sel0       = D_DEF;
        end
    end

    always @* begin
        b_sel_valid1 = 1'b0;
        b_sel1       = D_M0;
        if (m0_axi_bvalid && (m0_axi_bid[ID_WIDTH] == 1'b1)) begin
            b_sel_valid1 = 1'b1;
            b_sel1       = D_M0;
        end else if (m1_axi_bvalid && (m1_axi_bid[ID_WIDTH] == 1'b1)) begin
            b_sel_valid1 = 1'b1;
            b_sel1       = D_M1;
        end else if (def_bvalid && (def_bid[ID_WIDTH] == 1'b1)) begin
            b_sel_valid1 = 1'b1;
            b_sel1       = D_DEF;
        end
    end

    assign s0_axi_bvalid = b_sel_valid0;
    assign s0_axi_bid    = (b_sel0 == D_M0) ? m0_axi_bid[ID_WIDTH-1:0] :
                           (b_sel0 == D_M1) ? m1_axi_bid[ID_WIDTH-1:0] :
                                              def_bid[ID_WIDTH-1:0];
    assign s0_axi_bresp  = (b_sel0 == D_M0) ? m0_axi_bresp :
                           (b_sel0 == D_M1) ? m1_axi_bresp :
                                              def_bresp;

    assign s1_axi_bvalid = b_sel_valid1;
    assign s1_axi_bid    = (b_sel1 == D_M0) ? m0_axi_bid[ID_WIDTH-1:0] :
                           (b_sel1 == D_M1) ? m1_axi_bid[ID_WIDTH-1:0] :
                                              def_bid[ID_WIDTH-1:0];
    assign s1_axi_bresp  = (b_sel1 == D_M0) ? m0_axi_bresp :
                           (b_sel1 == D_M1) ? m1_axi_bresp :
                                              def_bresp;

    assign m0_axi_bready = (b_sel_valid0 && (b_sel0 == D_M0) && s0_axi_bready) ||
                           (b_sel_valid1 && (b_sel1 == D_M0) && s1_axi_bready);
    assign m1_axi_bready = (b_sel_valid0 && (b_sel0 == D_M1) && s0_axi_bready) ||
                           (b_sel_valid1 && (b_sel1 == D_M1) && s1_axi_bready);
    assign def_bready    = (b_sel_valid0 && (b_sel0 == D_DEF) && s0_axi_bready) ||
                           (b_sel_valid1 && (b_sel1 == D_DEF) && s1_axi_bready);

    // =========================================================================
    // READ PATH
    // =========================================================================

    // ---- master-port AR acceptance gates (purely registered state) ----------
    assign s0_axi_arready = aresetn && !rd_active0;
    assign s1_axi_arready = aresetn && !rd_active1;

    // ---- per-destination read requests --------------------------------------
    assign rreq0_m0  = ar_pend0 && (ar_dest0 == D_M0);
    assign rreq1_m0  = ar_pend1 && (ar_dest1 == D_M0);
    assign rreq0_m1  = ar_pend0 && (ar_dest0 == D_M1);
    assign rreq1_m1  = ar_pend1 && (ar_dest1 == D_M1);
    assign rreq0_def = ar_pend0 && (ar_dest0 == D_DEF);
    assign rreq1_def = ar_pend1 && (ar_dest1 == D_DEF);

    assign ar_pend_own_m0  = rgrant_owner_m0  ? ar_pend1 : ar_pend0;
    assign ar_pend_own_m1  = rgrant_owner_m1  ? ar_pend1 : ar_pend0;
    assign ar_pend_own_def = rgrant_owner_def ? ar_pend1 : ar_pend0;

    // ---- AR forwarding to destinations --------------------------------------
    assign m0_axi_arid    = rgrant_owner_m0 ? ar_id1    : ar_id0;
    assign m0_axi_araddr  = rgrant_owner_m0 ? ar_addr1  : ar_addr0;
    assign m0_axi_arlen   = rgrant_owner_m0 ? ar_len1   : ar_len0;
    assign m0_axi_arsize  = rgrant_owner_m0 ? ar_size1  : ar_size0;
    assign m0_axi_arburst = rgrant_owner_m0 ? ar_burst1 : ar_burst0;
    assign m0_axi_arprot  = rgrant_owner_m0 ? ar_prot1  : ar_prot0;
    assign m0_axi_arvalid = rgrant_valid_m0 && ar_pend_own_m0;

    assign m1_axi_arid    = rgrant_owner_m1 ? ar_id1    : ar_id0;
    assign m1_axi_araddr  = rgrant_owner_m1 ? ar_addr1  : ar_addr0;
    assign m1_axi_arlen   = rgrant_owner_m1 ? ar_len1   : ar_len0;
    assign m1_axi_arsize  = rgrant_owner_m1 ? ar_size1  : ar_size0;
    assign m1_axi_arburst = rgrant_owner_m1 ? ar_burst1 : ar_burst0;
    assign m1_axi_arprot  = rgrant_owner_m1 ? ar_prot1  : ar_prot0;
    assign m1_axi_arvalid = rgrant_valid_m1 && ar_pend_own_m1;

    assign def_arid    = rgrant_owner_def ? ar_id1  : ar_id0;
    assign def_arlen   = rgrant_owner_def ? ar_len1 : ar_len0;
    assign def_arvalid = rgrant_valid_def && ar_pend_own_def;

    // ---- AR delivery events -------------------------------------------------
    assign arfire_m0  = m0_axi_arvalid && m0_axi_arready;
    assign arfire_m1  = m1_axi_arvalid && m1_axi_arready;
    assign arfire_def = def_arvalid    && def_arready;

    assign ar0_deliver = (arfire_m0  && !rgrant_owner_m0)
                      || (arfire_m1  && !rgrant_owner_m1)
                      || (arfire_def && !rgrant_owner_def);
    assign ar1_deliver = (arfire_m0  &&  rgrant_owner_m0)
                      || (arfire_m1  &&  rgrant_owner_m1)
                      || (arfire_def &&  rgrant_owner_def);

    // ---- master-port read front-end sequencers ------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_active0 <= 1'b0;
            ar_pend0   <= 1'b0;
            ar_dest0   <= D_M0;
            ar_id0     <= {(ID_WIDTH+1){1'b0}};
            ar_addr0   <= 32'd0;
            ar_len0    <= 8'd0;
            ar_size0   <= 3'd0;
            ar_burst0  <= 2'd0;
            ar_prot0   <= 3'd0;
        end else begin
            if (s0_axi_arvalid && s0_axi_arready) begin
                rd_active0 <= 1'b1;
                ar_pend0   <= 1'b1;
                ar_dest0   <= decode_dest(s0_axi_araddr);
                ar_id0     <= {1'b0, s0_axi_arid};
                ar_addr0   <= s0_axi_araddr;
                ar_len0    <= s0_axi_arlen;
                ar_size0   <= s0_axi_arsize;
                ar_burst0  <= s0_axi_arburst;
                ar_prot0   <= s0_axi_arprot;
            end else if (ar0_deliver) begin
                ar_pend0 <= 1'b0;
            end
            if (s0_axi_rvalid && s0_axi_rready && s0_axi_rlast)
                rd_active0 <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_active1 <= 1'b0;
            ar_pend1   <= 1'b0;
            ar_dest1   <= D_M0;
            ar_id1     <= {(ID_WIDTH+1){1'b0}};
            ar_addr1   <= 32'd0;
            ar_len1    <= 8'd0;
            ar_size1   <= 3'd0;
            ar_burst1  <= 2'd0;
            ar_prot1   <= 3'd0;
        end else begin
            if (s1_axi_arvalid && s1_axi_arready) begin
                rd_active1 <= 1'b1;
                ar_pend1   <= 1'b1;
                ar_dest1   <= decode_dest(s1_axi_araddr);
                ar_id1     <= {1'b1, s1_axi_arid};
                ar_addr1   <= s1_axi_araddr;
                ar_len1    <= s1_axi_arlen;
                ar_size1   <= s1_axi_arsize;
                ar_burst1  <= s1_axi_arburst;
                ar_prot1   <= s1_axi_arprot;
            end else if (ar1_deliver) begin
                ar_pend1 <= 1'b0;
            end
            if (s1_axi_rvalid && s1_axi_rready && s1_axi_rlast)
                rd_active1 <= 1'b0;
        end
    end

    // ---- per-destination read grant arbiters (registered, round-robin) ------
    // Grant released once the destination AR handshake completes.
    always @(posedge aclk) begin
        if (!aresetn) begin
            rgrant_valid_m0 <= 1'b0;
            rgrant_owner_m0 <= 1'b0;
            r_rr_m0         <= 1'b0;
        end else if (!rgrant_valid_m0) begin
            if (rreq0_m0 && rreq1_m0) begin
                rgrant_valid_m0 <= 1'b1;
                rgrant_owner_m0 <= r_rr_m0;
            end else if (rreq0_m0) begin
                rgrant_valid_m0 <= 1'b1;
                rgrant_owner_m0 <= 1'b0;
            end else if (rreq1_m0) begin
                rgrant_valid_m0 <= 1'b1;
                rgrant_owner_m0 <= 1'b1;
            end
        end else if (arfire_m0) begin
            rgrant_valid_m0 <= 1'b0;
            r_rr_m0         <= ~rgrant_owner_m0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rgrant_valid_m1 <= 1'b0;
            rgrant_owner_m1 <= 1'b0;
            r_rr_m1         <= 1'b0;
        end else if (!rgrant_valid_m1) begin
            if (rreq0_m1 && rreq1_m1) begin
                rgrant_valid_m1 <= 1'b1;
                rgrant_owner_m1 <= r_rr_m1;
            end else if (rreq0_m1) begin
                rgrant_valid_m1 <= 1'b1;
                rgrant_owner_m1 <= 1'b0;
            end else if (rreq1_m1) begin
                rgrant_valid_m1 <= 1'b1;
                rgrant_owner_m1 <= 1'b1;
            end
        end else if (arfire_m1) begin
            rgrant_valid_m1 <= 1'b0;
            r_rr_m1         <= ~rgrant_owner_m1;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rgrant_valid_def <= 1'b0;
            rgrant_owner_def <= 1'b0;
            r_rr_def         <= 1'b0;
        end else if (!rgrant_valid_def) begin
            if (rreq0_def && rreq1_def) begin
                rgrant_valid_def <= 1'b1;
                rgrant_owner_def <= r_rr_def;
            end else if (rreq0_def) begin
                rgrant_valid_def <= 1'b1;
                rgrant_owner_def <= 1'b0;
            end else if (rreq1_def) begin
                rgrant_valid_def <= 1'b1;
                rgrant_owner_def <= 1'b1;
            end
        end else if (arfire_def) begin
            rgrant_valid_def <= 1'b0;
            r_rr_def         <= ~rgrant_owner_def;
        end
    end

    // ---- R return routing: by RID MSB, with per-master-port burst lock ------
    assign rhit0_m0  = m0_axi_rvalid && (m0_axi_rid[ID_WIDTH] == 1'b0);
    assign rhit0_m1  = m1_axi_rvalid && (m1_axi_rid[ID_WIDTH] == 1'b0);
    assign rhit0_def = def_rvalid    && (def_rid[ID_WIDTH]    == 1'b0);
    assign rhit1_m0  = m0_axi_rvalid && (m0_axi_rid[ID_WIDTH] == 1'b1);
    assign rhit1_m1  = m1_axi_rvalid && (m1_axi_rid[ID_WIDTH] == 1'b1);
    assign rhit1_def = def_rvalid    && (def_rid[ID_WIDTH]    == 1'b1);

    // master port 0 R source select: locked to rsrc0 from first beat to RLAST
    always @* begin
        if (rlock0) begin
            r_sel0       = rsrc0;
            r_sel_valid0 = (rsrc0 == D_M0) ? rhit0_m0 :
                           (rsrc0 == D_M1) ? rhit0_m1 :
                                             rhit0_def;
        end else begin
            r_sel_valid0 = 1'b0;
            r_sel0       = D_M0;
            if (rhit0_m0) begin
                r_sel_valid0 = 1'b1;
                r_sel0       = D_M0;
            end else if (rhit0_m1) begin
                r_sel_valid0 = 1'b1;
                r_sel0       = D_M1;
            end else if (rhit0_def) begin
                r_sel_valid0 = 1'b1;
                r_sel0       = D_DEF;
            end
        end
    end

    // master port 1 R source select
    always @* begin
        if (rlock1) begin
            r_sel1       = rsrc1;
            r_sel_valid1 = (rsrc1 == D_M0) ? rhit1_m0 :
                           (rsrc1 == D_M1) ? rhit1_m1 :
                                             rhit1_def;
        end else begin
            r_sel_valid1 = 1'b0;
            r_sel1       = D_M0;
            if (rhit1_m0) begin
                r_sel_valid1 = 1'b1;
                r_sel1       = D_M0;
            end else if (rhit1_m1) begin
                r_sel_valid1 = 1'b1;
                r_sel1       = D_M1;
            end else if (rhit1_def) begin
                r_sel_valid1 = 1'b1;
                r_sel1       = D_DEF;
            end
        end
    end

    assign s0_axi_rvalid = r_sel_valid0;
    assign s0_axi_rid    = (r_sel0 == D_M0) ? m0_axi_rid[ID_WIDTH-1:0] :
                           (r_sel0 == D_M1) ? m1_axi_rid[ID_WIDTH-1:0] :
                                              def_rid[ID_WIDTH-1:0];
    assign s0_axi_rdata  = (r_sel0 == D_M0) ? m0_axi_rdata :
                           (r_sel0 == D_M1) ? m1_axi_rdata :
                                              def_rdata;
    assign s0_axi_rresp  = (r_sel0 == D_M0) ? m0_axi_rresp :
                           (r_sel0 == D_M1) ? m1_axi_rresp :
                                              def_rresp;
    assign s0_axi_rlast  = (r_sel0 == D_M0) ? m0_axi_rlast :
                           (r_sel0 == D_M1) ? m1_axi_rlast :
                                              def_rlast;

    assign s1_axi_rvalid = r_sel_valid1;
    assign s1_axi_rid    = (r_sel1 == D_M0) ? m0_axi_rid[ID_WIDTH-1:0] :
                           (r_sel1 == D_M1) ? m1_axi_rid[ID_WIDTH-1:0] :
                                              def_rid[ID_WIDTH-1:0];
    assign s1_axi_rdata  = (r_sel1 == D_M0) ? m0_axi_rdata :
                           (r_sel1 == D_M1) ? m1_axi_rdata :
                                              def_rdata;
    assign s1_axi_rresp  = (r_sel1 == D_M0) ? m0_axi_rresp :
                           (r_sel1 == D_M1) ? m1_axi_rresp :
                                              def_rresp;
    assign s1_axi_rlast  = (r_sel1 == D_M0) ? m0_axi_rlast :
                           (r_sel1 == D_M1) ? m1_axi_rlast :
                                              def_rlast;

    assign m0_axi_rready = (r_sel_valid0 && (r_sel0 == D_M0) && s0_axi_rready) ||
                           (r_sel_valid1 && (r_sel1 == D_M0) && s1_axi_rready);
    assign m1_axi_rready = (r_sel_valid0 && (r_sel0 == D_M1) && s0_axi_rready) ||
                           (r_sel_valid1 && (r_sel1 == D_M1) && s1_axi_rready);
    assign def_rready    = (r_sel_valid0 && (r_sel0 == D_DEF) && s0_axi_rready) ||
                           (r_sel_valid1 && (r_sel1 == D_DEF) && s1_axi_rready);

    // ---- R source lock state (per master port): first beat .. RLAST ---------
    always @(posedge aclk) begin
        if (!aresetn) begin
            rlock0 <= 1'b0;
            rsrc0  <= D_M0;
        end else if (s0_axi_rvalid && s0_axi_rready) begin
            if (s0_axi_rlast) begin
                rlock0 <= 1'b0;
            end else begin
                rlock0 <= 1'b1;
                rsrc0  <= r_sel0;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rlock1 <= 1'b0;
            rsrc1  <= D_M0;
        end else if (s1_axi_rvalid && s1_axi_rready) begin
            if (s1_axi_rlast) begin
                rlock1 <= 1'b0;
            end else begin
                rlock1 <= 1'b1;
                rsrc1  <= r_sel1;
            end
        end
    end

    // =========================================================================
    // INTERNAL DEFAULT SLAVE (burst-capable DECERR responder)
    // =========================================================================

    // ---- write engine: accept AW, consume W to WLAST, single B = DECERR -----
    assign def_awready = (def_wstate == DW_IDLE);
    assign def_wready  = (def_wstate == DW_DATA);
    assign def_bvalid  = (def_wstate == DW_RESP);
    assign def_bresp   = RESP_DECERR;
    assign def_bid     = def_bid_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            def_wstate <= DW_IDLE;
            def_bid_r  <= {(ID_WIDTH+1){1'b0}};
        end else begin
            case (def_wstate)
                DW_IDLE: begin
                    if (def_awvalid && def_awready) begin
                        def_bid_r  <= def_awid;
                        def_wstate <= DW_DATA;
                    end
                end
                DW_DATA: begin
                    if (def_wvalid && def_wready && def_wlast)
                        def_wstate <= DW_RESP;
                end
                DW_RESP: begin
                    if (def_bready)
                        def_wstate <= DW_IDLE;
                end
                default: def_wstate <= DW_IDLE;
            endcase
        end
    end

    // ---- read engine: arlen+1 beats, rdata=32'hDEC0DE00, rresp=DECERR -------
    assign def_arready = (def_rstate == DR_IDLE);
    assign def_rvalid  = (def_rstate == DR_DATA);
    assign def_rdata   = 32'hDEC0DE00;
    assign def_rresp   = RESP_DECERR;
    assign def_rid     = def_rid_r;
    assign def_rlast   = (def_rstate == DR_DATA) && (def_rcnt == def_rlen_r);

    always @(posedge aclk) begin
        if (!aresetn) begin
            def_rstate <= DR_IDLE;
            def_rid_r  <= {(ID_WIDTH+1){1'b0}};
            def_rlen_r <= 8'd0;
            def_rcnt   <= 8'd0;
        end else begin
            case (def_rstate)
                DR_IDLE: begin
                    if (def_arvalid && def_arready) begin
                        def_rid_r  <= def_arid;
                        def_rlen_r <= def_arlen;
                        def_rcnt   <= 8'd0;
                        def_rstate <= DR_DATA;
                    end
                end
                DR_DATA: begin
                    if (def_rvalid && def_rready) begin
                        if (def_rcnt == def_rlen_r)
                            def_rstate <= DR_IDLE;
                        else
                            def_rcnt <= def_rcnt + 8'd1;
                    end
                end
                default: def_rstate <= DR_IDLE;
            endcase
        end
    end

endmodule
