// =============================================================================
// axi4_lite_interconnect.v
// AXI4-Lite 2-master x (2-slave + internal DECERR default slave) crossbar.
// Implements SPEC.md section 3.
//
//   s0_axi_* / s1_axi_* : AXI4-Lite slave ports  (the two masters connect here)
//   m0_axi_* / m1_axi_* : AXI4-Lite master ports (the two slaves connect here)
//
// Address decode (SPEC.md section 1), on addr[31:12]:
//   20'h00000 -> m0 port (S0 device)
//   20'h00001 -> m1 port (S1 device)
//   else      -> internal DECERR default slave (read data 32'hDEC0DE00)
//
// Write path:
//   Each master port accepts one AW into a holding register (this is its single
//   outstanding write; s*_axi_awready = ~wr_active*, a purely registered gate).
//   Per destination a registered round-robin arbiter claims a grant for one
//   captured AW; the grant is held from claim through the B handshake on that
//   destination. W is streamed combinationally from the granted master and is
//   forwarded only after that master's AW has been delivered. B is routed back
//   to whichever master holds the destination's write grant.
//
// Read path:
//   Identical structure and fully independent of the write path: one AR is
//   captured per master port, a per-destination registered round-robin arbiter
//   grants it, and the grant is held until the R handshake completes.
//
// Round-robin fairness: after a master completes a transaction on a
// destination, the other master takes priority next time both request it.
//
// Architectural note (same choice as axi4_interconnect.v): AW is *captured*
// and then forwarded, rather than passed through combinationally. A master
// therefore always gets its first AW accepted, and stalls at the arbiter
// instead of at the AW handshake; its awready is low for the remainder of the
// transaction. The externally observable property SPEC.md section 3 asks for --
// a master cannot push a write through a destination another master holds, and
// M0->S0 runs concurrently with M1->S1 -- is preserved. See SPEC.md section 11.
//
// Strict Verilog-2001: synchronous active-low reset, no initial, no delays.
// =============================================================================

module axi4_lite_interconnect (
    input  wire        aclk,
    input  wire        aresetn,

    // -------------------------------------------------------------------------
    // s0_axi_* : AXI4-Lite slave port 0 (master 0 connects here)
    // -------------------------------------------------------------------------
    input  wire [31:0] s0_axi_awaddr,
    input  wire [2:0]  s0_axi_awprot,
    input  wire        s0_axi_awvalid,
    output wire        s0_axi_awready,
    input  wire [31:0] s0_axi_wdata,
    input  wire [3:0]  s0_axi_wstrb,
    input  wire        s0_axi_wvalid,
    output wire        s0_axi_wready,
    output wire [1:0]  s0_axi_bresp,
    output wire        s0_axi_bvalid,
    input  wire        s0_axi_bready,
    input  wire [31:0] s0_axi_araddr,
    input  wire [2:0]  s0_axi_arprot,
    input  wire        s0_axi_arvalid,
    output wire        s0_axi_arready,
    output wire [31:0] s0_axi_rdata,
    output wire [1:0]  s0_axi_rresp,
    output wire        s0_axi_rvalid,
    input  wire        s0_axi_rready,

    // -------------------------------------------------------------------------
    // s1_axi_* : AXI4-Lite slave port 1 (master 1 connects here)
    // -------------------------------------------------------------------------
    input  wire [31:0] s1_axi_awaddr,
    input  wire [2:0]  s1_axi_awprot,
    input  wire        s1_axi_awvalid,
    output wire        s1_axi_awready,
    input  wire [31:0] s1_axi_wdata,
    input  wire [3:0]  s1_axi_wstrb,
    input  wire        s1_axi_wvalid,
    output wire        s1_axi_wready,
    output wire [1:0]  s1_axi_bresp,
    output wire        s1_axi_bvalid,
    input  wire        s1_axi_bready,
    input  wire [31:0] s1_axi_araddr,
    input  wire [2:0]  s1_axi_arprot,
    input  wire        s1_axi_arvalid,
    output wire        s1_axi_arready,
    output wire [31:0] s1_axi_rdata,
    output wire [1:0]  s1_axi_rresp,
    output wire        s1_axi_rvalid,
    input  wire        s1_axi_rready,

    // -------------------------------------------------------------------------
    // m0_axi_* : AXI4-Lite master port 0 (slave S0 connects here)
    // -------------------------------------------------------------------------
    output wire [31:0] m0_axi_awaddr,
    output wire [2:0]  m0_axi_awprot,
    output wire        m0_axi_awvalid,
    input  wire        m0_axi_awready,
    output wire [31:0] m0_axi_wdata,
    output wire [3:0]  m0_axi_wstrb,
    output wire        m0_axi_wvalid,
    input  wire        m0_axi_wready,
    input  wire [1:0]  m0_axi_bresp,
    input  wire        m0_axi_bvalid,
    output wire        m0_axi_bready,
    output wire [31:0] m0_axi_araddr,
    output wire [2:0]  m0_axi_arprot,
    output wire        m0_axi_arvalid,
    input  wire        m0_axi_arready,
    input  wire [31:0] m0_axi_rdata,
    input  wire [1:0]  m0_axi_rresp,
    input  wire        m0_axi_rvalid,
    output wire        m0_axi_rready,

    // -------------------------------------------------------------------------
    // m1_axi_* : AXI4-Lite master port 1 (slave S1 connects here)
    // -------------------------------------------------------------------------
    output wire [31:0] m1_axi_awaddr,
    output wire [2:0]  m1_axi_awprot,
    output wire        m1_axi_awvalid,
    input  wire        m1_axi_awready,
    output wire [31:0] m1_axi_wdata,
    output wire [3:0]  m1_axi_wstrb,
    output wire        m1_axi_wvalid,
    input  wire        m1_axi_wready,
    input  wire [1:0]  m1_axi_bresp,
    input  wire        m1_axi_bvalid,
    output wire        m1_axi_bready,
    output wire [31:0] m1_axi_araddr,
    output wire [2:0]  m1_axi_arprot,
    output wire        m1_axi_arvalid,
    input  wire        m1_axi_arready,
    input  wire [31:0] m1_axi_rdata,
    input  wire [1:0]  m1_axi_rresp,
    input  wire        m1_axi_rvalid,
    output wire        m1_axi_rready
);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    localparam [1:0] D_M0  = 2'd0;    // destination: m0 port (S0 device)
    localparam [1:0] D_M1  = 2'd1;    // destination: m1 port (S1 device)
    localparam [1:0] D_DEF = 2'd2;    // destination: internal default slave

    localparam [1:0]  RESP_DECERR = 2'b11;
    localparam [31:0] DEF_RDATA   = 32'hDEC0DE00;

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
    reg        wr_active0, wr_active1;   // AW accepted .. B handshake
    reg        aw_pend0,   aw_pend1;     // captured AW awaiting delivery
    reg [1:0]  aw_dest0,   aw_dest1;
    reg [31:0] aw_addr0,   aw_addr1;
    reg [2:0]  aw_prot0,   aw_prot1;

    // master-port read front-ends (one outstanding read per master port)
    reg        rd_active0, rd_active1;   // AR accepted .. R handshake
    reg        ar_pend0,   ar_pend1;     // captured AR awaiting delivery
    reg [1:0]  ar_dest0,   ar_dest1;
    reg [31:0] ar_addr0,   ar_addr1;
    reg [2:0]  ar_prot0,   ar_prot1;

    // per-destination write grants (owner: 0 = master 0, 1 = master 1;
    // w_rr_*: which master has priority next time both request)
    reg        wgrant_valid_m0,  wgrant_owner_m0,  w_rr_m0;
    reg        wgrant_valid_m1,  wgrant_owner_m1,  w_rr_m1;
    reg        wgrant_valid_def, wgrant_owner_def, w_rr_def;

    // per-destination read grants
    reg        rgrant_valid_m0,  rgrant_owner_m0,  r_rr_m0;
    reg        rgrant_valid_m1,  rgrant_owner_m1,  r_rr_m1;
    reg        rgrant_valid_def, rgrant_owner_def, r_rr_def;

    // internal default slave state
    reg        def_aw_got, def_w_got, def_bvalid_r;
    reg        def_rvalid_r;

    // -------------------------------------------------------------------------
    // Wire declarations
    // -------------------------------------------------------------------------

    // internal default slave interface (mirrors an m-port)
    wire       def_awvalid, def_awready;
    wire       def_wvalid,  def_wready;
    wire [1:0] def_bresp;
    wire       def_bvalid,  def_bready;
    wire       def_arvalid, def_arready;
    wire [1:0] def_rresp;
    wire       def_rvalid,  def_rready;

    // write-path request / ownership / event wires
    wire wreq0_m0,  wreq1_m0;
    wire wreq0_m1,  wreq1_m1;
    wire wreq0_def, wreq1_def;
    wire aw_pend_own_m0, aw_pend_own_m1, aw_pend_own_def;
    wire awfire_m0, awfire_m1, awfire_def;
    wire aw0_deliver, aw1_deliver;
    wire wrel_m0, wrel_m1, wrel_def;

    // read-path request / ownership / event wires
    wire rreq0_m0,  rreq1_m0;
    wire rreq0_m1,  rreq1_m1;
    wire rreq0_def, rreq1_def;
    wire ar_pend_own_m0, ar_pend_own_m1, ar_pend_own_def;
    wire arfire_m0, arfire_m1, arfire_def;
    wire ar0_deliver, ar1_deliver;
    wire rrel_m0, rrel_m1, rrel_def;

    // per-master ownership of each destination (write path)
    wire w_own0_m0,  w_own1_m0;
    wire w_own0_m1,  w_own1_m1;
    wire w_own0_def, w_own1_def;

    // per-master ownership of each destination (read path)
    wire r_own0_m0,  r_own1_m0;
    wire r_own0_m1,  r_own1_m1;
    wire r_own0_def, r_own1_def;

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

    // A master holds at most one write grant at a time (it requests exactly one
    // destination), so at most one w_own<master>_* is ever high.
    assign w_own0_m0  = wgrant_valid_m0  && !wgrant_owner_m0;
    assign w_own1_m0  = wgrant_valid_m0  &&  wgrant_owner_m0;
    assign w_own0_m1  = wgrant_valid_m1  && !wgrant_owner_m1;
    assign w_own1_m1  = wgrant_valid_m1  &&  wgrant_owner_m1;
    assign w_own0_def = wgrant_valid_def && !wgrant_owner_def;
    assign w_own1_def = wgrant_valid_def &&  wgrant_owner_def;

    // ---- AW forwarding to destinations (registered grant + captured payload)
    assign m0_axi_awaddr  = wgrant_owner_m0 ? aw_addr1 : aw_addr0;
    assign m0_axi_awprot  = wgrant_owner_m0 ? aw_prot1 : aw_prot0;
    assign m0_axi_awvalid = wgrant_valid_m0 && aw_pend_own_m0;

    assign m1_axi_awaddr  = wgrant_owner_m1 ? aw_addr1 : aw_addr0;
    assign m1_axi_awprot  = wgrant_owner_m1 ? aw_prot1 : aw_prot0;
    assign m1_axi_awvalid = wgrant_valid_m1 && aw_pend_own_m1;

    assign def_awvalid    = wgrant_valid_def && aw_pend_own_def;

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
    assign m0_axi_wvalid = wgrant_valid_m0 && !aw_pend_own_m0 &&
                           (wgrant_owner_m0 ? s1_axi_wvalid : s0_axi_wvalid);

    assign m1_axi_wdata  = wgrant_owner_m1 ? s1_axi_wdata : s0_axi_wdata;
    assign m1_axi_wstrb  = wgrant_owner_m1 ? s1_axi_wstrb : s0_axi_wstrb;
    assign m1_axi_wvalid = wgrant_valid_m1 && !aw_pend_own_m1 &&
                           (wgrant_owner_m1 ? s1_axi_wvalid : s0_axi_wvalid);

    assign def_wvalid    = wgrant_valid_def && !aw_pend_own_def &&
                           (wgrant_owner_def ? s1_axi_wvalid : s0_axi_wvalid);

    // ---- W ready back-routing to the masters --------------------------------
    assign s0_axi_wready = (w_own0_m0  && !aw_pend0 && m0_axi_wready)
                        || (w_own0_m1  && !aw_pend0 && m1_axi_wready)
                        || (w_own0_def && !aw_pend0 && def_wready);
    assign s1_axi_wready = (w_own1_m0  && !aw_pend1 && m0_axi_wready)
                        || (w_own1_m1  && !aw_pend1 && m1_axi_wready)
                        || (w_own1_def && !aw_pend1 && def_wready);

    // ---- B return routing ---------------------------------------------------
    assign s0_axi_bvalid = (w_own0_m0  && m0_axi_bvalid)
                        || (w_own0_m1  && m1_axi_bvalid)
                        || (w_own0_def && def_bvalid);
    assign s0_axi_bresp  = w_own0_m0  ? m0_axi_bresp :
                           w_own0_m1  ? m1_axi_bresp :
                           w_own0_def ? def_bresp    : 2'b00;

    assign s1_axi_bvalid = (w_own1_m0  && m0_axi_bvalid)
                        || (w_own1_m1  && m1_axi_bvalid)
                        || (w_own1_def && def_bvalid);
    assign s1_axi_bresp  = w_own1_m0  ? m0_axi_bresp :
                           w_own1_m1  ? m1_axi_bresp :
                           w_own1_def ? def_bresp    : 2'b00;

    assign m0_axi_bready = wgrant_valid_m0 &&
                           (wgrant_owner_m0 ? s1_axi_bready : s0_axi_bready);
    assign m1_axi_bready = wgrant_valid_m1 &&
                           (wgrant_owner_m1 ? s1_axi_bready : s0_axi_bready);
    assign def_bready    = wgrant_valid_def &&
                           (wgrant_owner_def ? s1_axi_bready : s0_axi_bready);

    // ---- write grant release: the B handshake on that destination -----------
    assign wrel_m0  = m0_axi_bvalid && m0_axi_bready;
    assign wrel_m1  = m1_axi_bvalid && m1_axi_bready;
    assign wrel_def = def_bvalid    && def_bready;

    // ---- master-port write front-end registers ------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_active0 <= 1'b0;
            aw_pend0   <= 1'b0;
            aw_dest0   <= D_M0;
            aw_addr0   <= 32'd0;
            aw_prot0   <= 3'd0;
        end else begin
            if (s0_axi_awvalid && s0_axi_awready) begin
                wr_active0 <= 1'b1;
                aw_pend0   <= 1'b1;
                aw_dest0   <= decode_dest(s0_axi_awaddr);
                aw_addr0   <= s0_axi_awaddr;
                aw_prot0   <= s0_axi_awprot;
            end
            if (aw0_deliver)
                aw_pend0 <= 1'b0;
            if (s0_axi_bvalid && s0_axi_bready)
                wr_active0 <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_active1 <= 1'b0;
            aw_pend1   <= 1'b0;
            aw_dest1   <= D_M0;
            aw_addr1   <= 32'd0;
            aw_prot1   <= 3'd0;
        end else begin
            if (s1_axi_awvalid && s1_axi_awready) begin
                wr_active1 <= 1'b1;
                aw_pend1   <= 1'b1;
                aw_dest1   <= decode_dest(s1_axi_awaddr);
                aw_addr1   <= s1_axi_awaddr;
                aw_prot1   <= s1_axi_awprot;
            end
            if (aw1_deliver)
                aw_pend1 <= 1'b0;
            if (s1_axi_bvalid && s1_axi_bready)
                wr_active1 <= 1'b0;
        end
    end

    // ---- per-destination write arbiters (registered round-robin) ------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            wgrant_valid_m0 <= 1'b0;
            wgrant_owner_m0 <= 1'b0;
            w_rr_m0         <= 1'b0;
        end else if (wgrant_valid_m0) begin
            if (wrel_m0) begin
                wgrant_valid_m0 <= 1'b0;
                w_rr_m0         <= ~wgrant_owner_m0;
            end
        end else if (w_rr_m0 == 1'b0) begin
            if (wreq0_m0) begin
                wgrant_valid_m0 <= 1'b1;
                wgrant_owner_m0 <= 1'b0;
            end else if (wreq1_m0) begin
                wgrant_valid_m0 <= 1'b1;
                wgrant_owner_m0 <= 1'b1;
            end
        end else begin
            if (wreq1_m0) begin
                wgrant_valid_m0 <= 1'b1;
                wgrant_owner_m0 <= 1'b1;
            end else if (wreq0_m0) begin
                wgrant_valid_m0 <= 1'b1;
                wgrant_owner_m0 <= 1'b0;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            wgrant_valid_m1 <= 1'b0;
            wgrant_owner_m1 <= 1'b0;
            w_rr_m1         <= 1'b0;
        end else if (wgrant_valid_m1) begin
            if (wrel_m1) begin
                wgrant_valid_m1 <= 1'b0;
                w_rr_m1         <= ~wgrant_owner_m1;
            end
        end else if (w_rr_m1 == 1'b0) begin
            if (wreq0_m1) begin
                wgrant_valid_m1 <= 1'b1;
                wgrant_owner_m1 <= 1'b0;
            end else if (wreq1_m1) begin
                wgrant_valid_m1 <= 1'b1;
                wgrant_owner_m1 <= 1'b1;
            end
        end else begin
            if (wreq1_m1) begin
                wgrant_valid_m1 <= 1'b1;
                wgrant_owner_m1 <= 1'b1;
            end else if (wreq0_m1) begin
                wgrant_valid_m1 <= 1'b1;
                wgrant_owner_m1 <= 1'b0;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            wgrant_valid_def <= 1'b0;
            wgrant_owner_def <= 1'b0;
            w_rr_def         <= 1'b0;
        end else if (wgrant_valid_def) begin
            if (wrel_def) begin
                wgrant_valid_def <= 1'b0;
                w_rr_def         <= ~wgrant_owner_def;
            end
        end else if (w_rr_def == 1'b0) begin
            if (wreq0_def) begin
                wgrant_valid_def <= 1'b1;
                wgrant_owner_def <= 1'b0;
            end else if (wreq1_def) begin
                wgrant_valid_def <= 1'b1;
                wgrant_owner_def <= 1'b1;
            end
        end else begin
            if (wreq1_def) begin
                wgrant_valid_def <= 1'b1;
                wgrant_owner_def <= 1'b1;
            end else if (wreq0_def) begin
                wgrant_valid_def <= 1'b1;
                wgrant_owner_def <= 1'b0;
            end
        end
    end

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

    assign r_own0_m0  = rgrant_valid_m0  && !rgrant_owner_m0;
    assign r_own1_m0  = rgrant_valid_m0  &&  rgrant_owner_m0;
    assign r_own0_m1  = rgrant_valid_m1  && !rgrant_owner_m1;
    assign r_own1_m1  = rgrant_valid_m1  &&  rgrant_owner_m1;
    assign r_own0_def = rgrant_valid_def && !rgrant_owner_def;
    assign r_own1_def = rgrant_valid_def &&  rgrant_owner_def;

    // ---- AR forwarding to destinations --------------------------------------
    assign m0_axi_araddr  = rgrant_owner_m0 ? ar_addr1 : ar_addr0;
    assign m0_axi_arprot  = rgrant_owner_m0 ? ar_prot1 : ar_prot0;
    assign m0_axi_arvalid = rgrant_valid_m0 && ar_pend_own_m0;

    assign m1_axi_araddr  = rgrant_owner_m1 ? ar_addr1 : ar_addr0;
    assign m1_axi_arprot  = rgrant_owner_m1 ? ar_prot1 : ar_prot0;
    assign m1_axi_arvalid = rgrant_valid_m1 && ar_pend_own_m1;

    assign def_arvalid    = rgrant_valid_def && ar_pend_own_def;

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

    // ---- R return routing ---------------------------------------------------
    assign s0_axi_rvalid = (r_own0_m0  && m0_axi_rvalid)
                        || (r_own0_m1  && m1_axi_rvalid)
                        || (r_own0_def && def_rvalid);
    assign s0_axi_rdata  = r_own0_m0  ? m0_axi_rdata :
                           r_own0_m1  ? m1_axi_rdata :
                           r_own0_def ? DEF_RDATA    : 32'd0;
    assign s0_axi_rresp  = r_own0_m0  ? m0_axi_rresp :
                           r_own0_m1  ? m1_axi_rresp :
                           r_own0_def ? def_rresp    : 2'b00;

    assign s1_axi_rvalid = (r_own1_m0  && m0_axi_rvalid)
                        || (r_own1_m1  && m1_axi_rvalid)
                        || (r_own1_def && def_rvalid);
    assign s1_axi_rdata  = r_own1_m0  ? m0_axi_rdata :
                           r_own1_m1  ? m1_axi_rdata :
                           r_own1_def ? DEF_RDATA    : 32'd0;
    assign s1_axi_rresp  = r_own1_m0  ? m0_axi_rresp :
                           r_own1_m1  ? m1_axi_rresp :
                           r_own1_def ? def_rresp    : 2'b00;

    assign m0_axi_rready = rgrant_valid_m0 &&
                           (rgrant_owner_m0 ? s1_axi_rready : s0_axi_rready);
    assign m1_axi_rready = rgrant_valid_m1 &&
                           (rgrant_owner_m1 ? s1_axi_rready : s0_axi_rready);
    assign def_rready    = rgrant_valid_def &&
                           (rgrant_owner_def ? s1_axi_rready : s0_axi_rready);

    // ---- read grant release: the R handshake on that destination ------------
    assign rrel_m0  = m0_axi_rvalid && m0_axi_rready;
    assign rrel_m1  = m1_axi_rvalid && m1_axi_rready;
    assign rrel_def = def_rvalid    && def_rready;

    // ---- master-port read front-end registers -------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_active0 <= 1'b0;
            ar_pend0   <= 1'b0;
            ar_dest0   <= D_M0;
            ar_addr0   <= 32'd0;
            ar_prot0   <= 3'd0;
        end else begin
            if (s0_axi_arvalid && s0_axi_arready) begin
                rd_active0 <= 1'b1;
                ar_pend0   <= 1'b1;
                ar_dest0   <= decode_dest(s0_axi_araddr);
                ar_addr0   <= s0_axi_araddr;
                ar_prot0   <= s0_axi_arprot;
            end
            if (ar0_deliver)
                ar_pend0 <= 1'b0;
            if (s0_axi_rvalid && s0_axi_rready)
                rd_active0 <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rd_active1 <= 1'b0;
            ar_pend1   <= 1'b0;
            ar_dest1   <= D_M0;
            ar_addr1   <= 32'd0;
            ar_prot1   <= 3'd0;
        end else begin
            if (s1_axi_arvalid && s1_axi_arready) begin
                rd_active1 <= 1'b1;
                ar_pend1   <= 1'b1;
                ar_dest1   <= decode_dest(s1_axi_araddr);
                ar_addr1   <= s1_axi_araddr;
                ar_prot1   <= s1_axi_arprot;
            end
            if (ar1_deliver)
                ar_pend1 <= 1'b0;
            if (s1_axi_rvalid && s1_axi_rready)
                rd_active1 <= 1'b0;
        end
    end

    // ---- per-destination read arbiters (registered round-robin) -------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            rgrant_valid_m0 <= 1'b0;
            rgrant_owner_m0 <= 1'b0;
            r_rr_m0         <= 1'b0;
        end else if (rgrant_valid_m0) begin
            if (rrel_m0) begin
                rgrant_valid_m0 <= 1'b0;
                r_rr_m0         <= ~rgrant_owner_m0;
            end
        end else if (r_rr_m0 == 1'b0) begin
            if (rreq0_m0) begin
                rgrant_valid_m0 <= 1'b1;
                rgrant_owner_m0 <= 1'b0;
            end else if (rreq1_m0) begin
                rgrant_valid_m0 <= 1'b1;
                rgrant_owner_m0 <= 1'b1;
            end
        end else begin
            if (rreq1_m0) begin
                rgrant_valid_m0 <= 1'b1;
                rgrant_owner_m0 <= 1'b1;
            end else if (rreq0_m0) begin
                rgrant_valid_m0 <= 1'b1;
                rgrant_owner_m0 <= 1'b0;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rgrant_valid_m1 <= 1'b0;
            rgrant_owner_m1 <= 1'b0;
            r_rr_m1         <= 1'b0;
        end else if (rgrant_valid_m1) begin
            if (rrel_m1) begin
                rgrant_valid_m1 <= 1'b0;
                r_rr_m1         <= ~rgrant_owner_m1;
            end
        end else if (r_rr_m1 == 1'b0) begin
            if (rreq0_m1) begin
                rgrant_valid_m1 <= 1'b1;
                rgrant_owner_m1 <= 1'b0;
            end else if (rreq1_m1) begin
                rgrant_valid_m1 <= 1'b1;
                rgrant_owner_m1 <= 1'b1;
            end
        end else begin
            if (rreq1_m1) begin
                rgrant_valid_m1 <= 1'b1;
                rgrant_owner_m1 <= 1'b1;
            end else if (rreq0_m1) begin
                rgrant_valid_m1 <= 1'b1;
                rgrant_owner_m1 <= 1'b0;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            rgrant_valid_def <= 1'b0;
            rgrant_owner_def <= 1'b0;
            r_rr_def         <= 1'b0;
        end else if (rgrant_valid_def) begin
            if (rrel_def) begin
                rgrant_valid_def <= 1'b0;
                r_rr_def         <= ~rgrant_owner_def;
            end
        end else if (r_rr_def == 1'b0) begin
            if (rreq0_def) begin
                rgrant_valid_def <= 1'b1;
                rgrant_owner_def <= 1'b0;
            end else if (rreq1_def) begin
                rgrant_valid_def <= 1'b1;
                rgrant_owner_def <= 1'b1;
            end
        end else begin
            if (rreq1_def) begin
                rgrant_valid_def <= 1'b1;
                rgrant_owner_def <= 1'b1;
            end else if (rreq0_def) begin
                rgrant_valid_def <= 1'b1;
                rgrant_owner_def <= 1'b0;
            end
        end
    end

    // =========================================================================
    // INTERNAL DEFAULT SLAVE (decode miss -> DECERR)
    // Same single-outstanding structure as axi4_lite_slave, responses forced
    // to DECERR and read data to 32'hDEC0DE00.
    // =========================================================================

    assign def_awready = !def_aw_got;
    assign def_wready  = !def_w_got;
    assign def_bvalid  = def_bvalid_r;
    assign def_bresp   = RESP_DECERR;

    always @(posedge aclk) begin
        if (!aresetn) begin
            def_aw_got   <= 1'b0;
            def_w_got    <= 1'b0;
            def_bvalid_r <= 1'b0;
        end else begin
            if (def_awvalid && def_awready)
                def_aw_got <= 1'b1;
            if (def_wvalid && def_wready)
                def_w_got <= 1'b1;
            if (!def_bvalid_r &&
                (def_aw_got || (def_awvalid && def_awready)) &&
                (def_w_got  || (def_wvalid  && def_wready))) begin
                def_bvalid_r <= 1'b1;
            end else if (def_bvalid && def_bready) begin
                def_bvalid_r <= 1'b0;
                def_aw_got   <= 1'b0;
                def_w_got    <= 1'b0;
            end
        end
    end

    assign def_arready = !def_rvalid_r;
    assign def_rvalid  = def_rvalid_r;
    assign def_rresp   = RESP_DECERR;

    always @(posedge aclk) begin
        if (!aresetn) begin
            def_rvalid_r <= 1'b0;
        end else begin
            if (def_arvalid && def_arready)
                def_rvalid_r <= 1'b1;
            else if (def_rvalid && def_rready)
                def_rvalid_r <= 1'b0;
        end
    end

endmodule
