// =============================================================================
// formal/axi4_lite_ic_formal.v
// Unbounded property check for axi4_lite_interconnect (SymbiYosys, abc pdr).
//
// This is a BLACK-BOX harness: it asserts only on the DUT's ports, never on its
// internal state, so the properties are statements about the interconnect's
// contract rather than a mirror of its implementation. rtl/ is untouched.
//
// The environment is constrained to be AXI-legal (masters hold VALID with a
// stable payload until READY; slaves only respond to transactions they actually
// accepted). Everything else -- addresses, data, ready timing, response codes --
// is left free, so a proof covers every legal traffic pattern, not a sampled
// subset.
//
// ASSUMED (environment):
//   A1  reset is held low for the first 5 cycles
//   A2  master AW/W/AR channels obey VALID/payload stability
//   A3  slave B/R channels obey VALID/payload stability
//   A4  a slave only raises BVALID/RVALID for a transaction it accepted
//
// ASSERTED (DUT obligations):
//   P1  all DUT-driven VALIDs are low during reset
//   P2  decode: an address forwarded to m0 is always in S0's range, and one
//       forwarded to m1 is always in S1's range -- no transaction can ever
//       reach the wrong slave
//   P3  every DUT-driven channel obeys VALID/payload stability (PC01-PC05,
//       proven for all time rather than sampled by the testbench)
//   P4  one outstanding write and one outstanding read per master port
//   P5  no B or R response to a master that has nothing outstanding
//   P6  a W beat is never forwarded to a destination that has no AW pending
//       there, and the AW/W imbalance stays bounded
// =============================================================================

module axi4_lite_ic_formal (
    input wire        aclk,
    // ---- master-side stimulus (free) ----------------------------------------
    input wire [31:0] s0_awaddr,
    input wire [2:0]  s0_awprot,
    input wire        s0_awvalid,
    input wire [31:0] s0_wdata,
    input wire [3:0]  s0_wstrb,
    input wire        s0_wvalid,
    input wire        s0_bready,
    input wire [31:0] s0_araddr,
    input wire [2:0]  s0_arprot,
    input wire        s0_arvalid,
    input wire        s0_rready,
    input wire [31:0] s1_awaddr,
    input wire [2:0]  s1_awprot,
    input wire        s1_awvalid,
    input wire [31:0] s1_wdata,
    input wire [3:0]  s1_wstrb,
    input wire        s1_wvalid,
    input wire        s1_bready,
    input wire [31:0] s1_araddr,
    input wire [2:0]  s1_arprot,
    input wire        s1_arvalid,
    input wire        s1_rready,
    // ---- slave-side responses (free) ----------------------------------------
    input wire        m0_awready,
    input wire        m0_wready,
    input wire [1:0]  m0_bresp,
    input wire        m0_bvalid,
    input wire        m0_arready,
    input wire [31:0] m0_rdata,
    input wire [1:0]  m0_rresp,
    input wire        m0_rvalid,
    input wire        m1_awready,
    input wire        m1_wready,
    input wire [1:0]  m1_bresp,
    input wire        m1_bvalid,
    input wire        m1_arready,
    input wire [31:0] m1_rdata,
    input wire [1:0]  m1_rresp,
    input wire        m1_rvalid
);

    // -------------------------------------------------------------------------
    // A1: reset sequence. rstcnt has an initial value, so the model starts in a
    // known place and every DUT register is driven to its reset value before any
    // assertion is evaluated.
    // -------------------------------------------------------------------------
    reg [3:0] rstcnt = 4'd0;
    always @(posedge aclk)
        if (rstcnt != 4'd15)
            rstcnt <= rstcnt + 4'd1;

    wire aresetn = (rstcnt >= 4'd5);

    reg aresetn_q = 1'b0;
    always @(posedge aclk)
        aresetn_q <= aresetn;

    wire chk = aresetn && aresetn_q;   // out of reset, and a previous cycle exists

    // -------------------------------------------------------------------------
    // DUT outputs
    // -------------------------------------------------------------------------
    wire        s0_awready, s0_wready, s0_bvalid, s0_arready, s0_rvalid;
    wire [1:0]  s0_bresp, s0_rresp;
    wire [31:0] s0_rdata;
    wire        s1_awready, s1_wready, s1_bvalid, s1_arready, s1_rvalid;
    wire [1:0]  s1_bresp, s1_rresp;
    wire [31:0] s1_rdata;
    wire [31:0] m0_awaddr, m0_wdata, m0_araddr;
    wire [2:0]  m0_awprot, m0_arprot;
    wire [3:0]  m0_wstrb;
    wire        m0_awvalid, m0_wvalid, m0_bready, m0_arvalid, m0_rready;
    wire [31:0] m1_awaddr, m1_wdata, m1_araddr;
    wire [2:0]  m1_awprot, m1_arprot;
    wire [3:0]  m1_wstrb;
    wire        m1_awvalid, m1_wvalid, m1_bready, m1_arvalid, m1_rready;

    axi4_lite_interconnect dut (
        .aclk (aclk), .aresetn (aresetn),
        .s0_axi_awaddr (s0_awaddr), .s0_axi_awprot (s0_awprot),
        .s0_axi_awvalid(s0_awvalid), .s0_axi_awready(s0_awready),
        .s0_axi_wdata  (s0_wdata),  .s0_axi_wstrb  (s0_wstrb),
        .s0_axi_wvalid (s0_wvalid), .s0_axi_wready (s0_wready),
        .s0_axi_bresp  (s0_bresp),  .s0_axi_bvalid (s0_bvalid),
        .s0_axi_bready (s0_bready),
        .s0_axi_araddr (s0_araddr), .s0_axi_arprot (s0_arprot),
        .s0_axi_arvalid(s0_arvalid), .s0_axi_arready(s0_arready),
        .s0_axi_rdata  (s0_rdata),  .s0_axi_rresp  (s0_rresp),
        .s0_axi_rvalid (s0_rvalid), .s0_axi_rready (s0_rready),
        .s1_axi_awaddr (s1_awaddr), .s1_axi_awprot (s1_awprot),
        .s1_axi_awvalid(s1_awvalid), .s1_axi_awready(s1_awready),
        .s1_axi_wdata  (s1_wdata),  .s1_axi_wstrb  (s1_wstrb),
        .s1_axi_wvalid (s1_wvalid), .s1_axi_wready (s1_wready),
        .s1_axi_bresp  (s1_bresp),  .s1_axi_bvalid (s1_bvalid),
        .s1_axi_bready (s1_bready),
        .s1_axi_araddr (s1_araddr), .s1_axi_arprot (s1_arprot),
        .s1_axi_arvalid(s1_arvalid), .s1_axi_arready(s1_arready),
        .s1_axi_rdata  (s1_rdata),  .s1_axi_rresp  (s1_rresp),
        .s1_axi_rvalid (s1_rvalid), .s1_axi_rready (s1_rready),
        .m0_axi_awaddr (m0_awaddr), .m0_axi_awprot (m0_awprot),
        .m0_axi_awvalid(m0_awvalid), .m0_axi_awready(m0_awready),
        .m0_axi_wdata  (m0_wdata),  .m0_axi_wstrb  (m0_wstrb),
        .m0_axi_wvalid (m0_wvalid), .m0_axi_wready (m0_wready),
        .m0_axi_bresp  (m0_bresp),  .m0_axi_bvalid (m0_bvalid),
        .m0_axi_bready (m0_bready),
        .m0_axi_araddr (m0_araddr), .m0_axi_arprot (m0_arprot),
        .m0_axi_arvalid(m0_arvalid), .m0_axi_arready(m0_arready),
        .m0_axi_rdata  (m0_rdata),  .m0_axi_rresp  (m0_rresp),
        .m0_axi_rvalid (m0_rvalid), .m0_axi_rready (m0_rready),
        .m1_axi_awaddr (m1_awaddr), .m1_axi_awprot (m1_awprot),
        .m1_axi_awvalid(m1_awvalid), .m1_axi_awready(m1_awready),
        .m1_axi_wdata  (m1_wdata),  .m1_axi_wstrb  (m1_wstrb),
        .m1_axi_wvalid (m1_wvalid), .m1_axi_wready (m1_wready),
        .m1_axi_bresp  (m1_bresp),  .m1_axi_bvalid (m1_bvalid),
        .m1_axi_bready (m1_bready),
        .m1_axi_araddr (m1_araddr), .m1_axi_arprot (m1_arprot),
        .m1_axi_arvalid(m1_arvalid), .m1_axi_arready(m1_arready),
        .m1_axi_rdata  (m1_rdata),  .m1_axi_rresp  (m1_rresp),
        .m1_axi_rvalid (m1_rvalid), .m1_axi_rready (m1_rready)
    );

    // -------------------------------------------------------------------------
    // Channel stability helpers. Each channel gets one history register set;
    // ASSUME for channels the environment drives, ASSERT for channels the DUT
    // drives. Payloads are concatenated so one comparison covers the channel.
    // -------------------------------------------------------------------------
`define CHAN_HIST(NM, WIDTH, VAL, RDY, PL)                                     \
    reg             NM``_v_q = 1'b0;                                           \
    reg             NM``_r_q = 1'b0;                                           \
    reg [WIDTH-1:0] NM``_p_q = {WIDTH{1'b0}};                                  \
    always @(posedge aclk) begin                                               \
        NM``_v_q <= VAL;                                                       \
        NM``_r_q <= RDY;                                                       \
        NM``_p_q <= PL;                                                        \
    end

`define CHAN_ASSUME(NM, VAL, PL)                                               \
    always @(posedge aclk)                                                     \
        if (chk && NM``_v_q && !NM``_r_q) begin                                \
            assume (VAL);                                                      \
            assume ((PL) == NM``_p_q);                                         \
        end

`define CHAN_ASSERT(NM, VAL, PL)                                               \
    always @(posedge aclk)                                                     \
        if (chk && NM``_v_q && !NM``_r_q) begin                                \
            assert (VAL);                                                      \
            assert ((PL) == NM``_p_q);                                         \
        end

    // ---- A2: master-side channels are legal ---------------------------------
    `CHAN_HIST(s0aw, 35, s0_awvalid, s0_awready, {s0_awaddr, s0_awprot})
    `CHAN_ASSUME(s0aw, s0_awvalid, {s0_awaddr, s0_awprot})
    `CHAN_HIST(s0w,  36, s0_wvalid,  s0_wready,  {s0_wdata, s0_wstrb})
    `CHAN_ASSUME(s0w,  s0_wvalid,  {s0_wdata, s0_wstrb})
    `CHAN_HIST(s0ar, 35, s0_arvalid, s0_arready, {s0_araddr, s0_arprot})
    `CHAN_ASSUME(s0ar, s0_arvalid, {s0_araddr, s0_arprot})
    `CHAN_HIST(s1aw, 35, s1_awvalid, s1_awready, {s1_awaddr, s1_awprot})
    `CHAN_ASSUME(s1aw, s1_awvalid, {s1_awaddr, s1_awprot})
    `CHAN_HIST(s1w,  36, s1_wvalid,  s1_wready,  {s1_wdata, s1_wstrb})
    `CHAN_ASSUME(s1w,  s1_wvalid,  {s1_wdata, s1_wstrb})
    `CHAN_HIST(s1ar, 35, s1_arvalid, s1_arready, {s1_araddr, s1_arprot})
    `CHAN_ASSUME(s1ar, s1_arvalid, {s1_araddr, s1_arprot})

    // ---- A3: slave-side response channels are legal -------------------------
    `CHAN_HIST(m0b, 2,  m0_bvalid, m0_bready, m0_bresp)
    `CHAN_ASSUME(m0b, m0_bvalid, m0_bresp)
    `CHAN_HIST(m0r, 34, m0_rvalid, m0_rready, {m0_rdata, m0_rresp})
    `CHAN_ASSUME(m0r, m0_rvalid, {m0_rdata, m0_rresp})
    `CHAN_HIST(m1b, 2,  m1_bvalid, m1_bready, m1_bresp)
    `CHAN_ASSUME(m1b, m1_bvalid, m1_bresp)
    `CHAN_HIST(m1r, 34, m1_rvalid, m1_rready, {m1_rdata, m1_rresp})
    `CHAN_ASSUME(m1r, m1_rvalid, {m1_rdata, m1_rresp})

    // ---- P3: DUT-driven channels must be legal too --------------------------
    // (histories are always built; only the assertions are task-selectable)
`ifndef PROP_STABLE
`define CHAN_ASSERT(NM, VAL, PL)
`endif
    `CHAN_HIST(m0aw, 35, m0_awvalid, m0_awready, {m0_awaddr, m0_awprot})
    `CHAN_ASSERT(m0aw, m0_awvalid, {m0_awaddr, m0_awprot})
    `CHAN_HIST(m0w,  36, m0_wvalid,  m0_wready,  {m0_wdata, m0_wstrb})
    `CHAN_ASSERT(m0w,  m0_wvalid,  {m0_wdata, m0_wstrb})
    `CHAN_HIST(m0ar, 35, m0_arvalid, m0_arready, {m0_araddr, m0_arprot})
    `CHAN_ASSERT(m0ar, m0_arvalid, {m0_araddr, m0_arprot})
    `CHAN_HIST(m1aw, 35, m1_awvalid, m1_awready, {m1_awaddr, m1_awprot})
    `CHAN_ASSERT(m1aw, m1_awvalid, {m1_awaddr, m1_awprot})
    `CHAN_HIST(m1w,  36, m1_wvalid,  m1_wready,  {m1_wdata, m1_wstrb})
    `CHAN_ASSERT(m1w,  m1_wvalid,  {m1_wdata, m1_wstrb})
    `CHAN_HIST(m1ar, 35, m1_arvalid, m1_arready, {m1_araddr, m1_arprot})
    `CHAN_ASSERT(m1ar, m1_arvalid, {m1_araddr, m1_arprot})
    `CHAN_HIST(s0b, 2,  s0_bvalid, s0_bready, s0_bresp)
    `CHAN_ASSERT(s0b, s0_bvalid, s0_bresp)
    `CHAN_HIST(s0r, 34, s0_rvalid, s0_rready, {s0_rdata, s0_rresp})
    `CHAN_ASSERT(s0r, s0_rvalid, {s0_rdata, s0_rresp})
    `CHAN_HIST(s1b, 2,  s1_bvalid, s1_bready, s1_bresp)
    `CHAN_ASSERT(s1b, s1_bvalid, s1_bresp)
    `CHAN_HIST(s1r, 34, s1_rvalid, s1_rready, {s1_rdata, s1_rresp})
    `CHAN_ASSERT(s1r, s1_rvalid, {s1_rdata, s1_rresp})

    // -------------------------------------------------------------------------
    // Outstanding-transaction tracking, used by A4, P4, P5, P6
    // -------------------------------------------------------------------------
    // Per write transaction a master issues exactly one AW and one W beat (in
    // either order -- AXI permits W before AW), and a slave issues its B only
    // once it has accepted BOTH. Tracking the two phases separately is what
    // makes those two facts expressible.
    reg s0_aw_done = 1'b0, s0_w_done = 1'b0, s0_rd_out = 1'b0;
    reg s1_aw_done = 1'b0, s1_w_done = 1'b0, s1_rd_out = 1'b0;
    reg m0_aw_taken = 1'b0, m0_w_taken = 1'b0, m0_rd_out = 1'b0;
    reg m1_aw_taken = 1'b0, m1_w_taken = 1'b0, m1_rd_out = 1'b0;
    reg [2:0] m0_awpend = 3'd0, m1_awpend = 3'd0;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s0_aw_done  <= 1'b0; s0_w_done  <= 1'b0; s0_rd_out <= 1'b0;
            s1_aw_done  <= 1'b0; s1_w_done  <= 1'b0; s1_rd_out <= 1'b0;
            m0_aw_taken <= 1'b0; m0_w_taken <= 1'b0; m0_rd_out <= 1'b0;
            m1_aw_taken <= 1'b0; m1_w_taken <= 1'b0; m1_rd_out <= 1'b0;
            m0_awpend   <= 3'd0; m1_awpend  <= 3'd0;
        end else begin
            // master port 0 write phases, cleared when its B completes
            if (s0_bvalid && s0_bready) begin
                s0_aw_done <= 1'b0; s0_w_done <= 1'b0;
            end else begin
                if (s0_awvalid && s0_awready) s0_aw_done <= 1'b1;
                if (s0_wvalid  && s0_wready)  s0_w_done  <= 1'b1;
            end
            if (s1_bvalid && s1_bready) begin
                s1_aw_done <= 1'b0; s1_w_done <= 1'b0;
            end else begin
                if (s1_awvalid && s1_awready) s1_aw_done <= 1'b1;
                if (s1_wvalid  && s1_wready)  s1_w_done  <= 1'b1;
            end

            if (s0_arvalid && s0_arready)      s0_rd_out <= 1'b1;
            else if (s0_rvalid && s0_rready)   s0_rd_out <= 1'b0;
            if (s1_arvalid && s1_arready)      s1_rd_out <= 1'b1;
            else if (s1_rvalid && s1_rready)   s1_rd_out <= 1'b0;

            // slave port 0/1 write phases, cleared when B is consumed
            if (m0_bvalid && m0_bready) begin
                m0_aw_taken <= 1'b0; m0_w_taken <= 1'b0;
            end else begin
                if (m0_awvalid && m0_awready) m0_aw_taken <= 1'b1;
                if (m0_wvalid  && m0_wready)  m0_w_taken  <= 1'b1;
            end
            if (m1_bvalid && m1_bready) begin
                m1_aw_taken <= 1'b0; m1_w_taken <= 1'b0;
            end else begin
                if (m1_awvalid && m1_awready) m1_aw_taken <= 1'b1;
                if (m1_wvalid  && m1_wready)  m1_w_taken  <= 1'b1;
            end

            if (m0_arvalid && m0_arready)      m0_rd_out <= 1'b1;
            else if (m0_rvalid && m0_rready)   m0_rd_out <= 1'b0;
            if (m1_arvalid && m1_arready)      m1_rd_out <= 1'b1;
            else if (m1_rvalid && m1_rready)   m1_rd_out <= 1'b0;

            // AW delivered but its W beat not yet delivered, per destination
            case ({m0_awvalid && m0_awready, m0_wvalid && m0_wready})
                2'b10:   m0_awpend <= m0_awpend + 3'd1;
                2'b01:   m0_awpend <= m0_awpend - 3'd1;
                default: m0_awpend <= m0_awpend;
            endcase
            case ({m1_awvalid && m1_awready, m1_wvalid && m1_wready})
                2'b10:   m1_awpend <= m1_awpend + 3'd1;
                2'b01:   m1_awpend <= m1_awpend - 3'd1;
                default: m1_awpend <= m1_awpend;
            endcase
        end
    end

    // ---- A4: slaves respond only to complete transactions they accepted -----
    // A slave that raised BVALID before consuming the W beat would be illegal,
    // and would (correctly) break the DUT's WVALID stability -- so the write
    // response is gated on BOTH phases having been accepted, not just the AW.
    always @(posedge aclk) begin
        if (chk) begin
            assume (!m0_bvalid || (m0_aw_taken && m0_w_taken));
            assume (!m1_bvalid || (m1_aw_taken && m1_w_taken));
            assume (!m0_rvalid || m0_rd_out);
            assume (!m1_rvalid || m1_rd_out);
        end
    end

    // ---- A5: masters are single-outstanding, one AW and one W per write -----
    // Without this a "master" could keep pushing W beats with no matching AW,
    // which no real master does and which SPEC.md section 11 excludes.
    always @(posedge aclk) begin
        if (chk) begin
            assume (!s0_awvalid || !s0_aw_done);
            assume (!s0_wvalid  || !s0_w_done);
            assume (!s1_awvalid || !s1_aw_done);
            assume (!s1_wvalid  || !s1_w_done);
            assume (!s0_arvalid || !s0_rd_out);
            assume (!s1_arvalid || !s1_rd_out);
        end
    end

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
            // READYs too, not just VALIDs. SPEC.md section 0 only constrains
            // VALIDs in reset, which left a hole: dropping the reset term from a
            // master-port AWREADY was invisible to every tier (mutation M13).
            // Every DUT-driven READY here is already reset-gated, so requiring
            // it costs nothing and closes that hole.
            assert (!s0_awready); assert (!s0_wready); assert (!s0_arready);
            assert (!s1_awready); assert (!s1_wready); assert (!s1_arready);
            assert (!m0_bready);  assert (!m0_rready);
            assert (!m1_bready);  assert (!m1_rready);
        end
    end
`endif

    // -------------------------------------------------------------------------
    // P2: address decode. Nothing outside S0's range can ever appear on m0, and
    // nothing outside S1's range can ever appear on m1.
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
    // P4/P5: one outstanding transaction per master port, and no unsolicited
    // response to a master
    // -------------------------------------------------------------------------
`ifdef PROP_OUTSTANDING
    always @(posedge aclk) begin
        if (chk) begin
            // P5: no unsolicited response to a master
            assert (!s0_bvalid || s0_aw_done);
            assert (!s0_rvalid || s0_rd_out);
            assert (!s1_bvalid || s1_aw_done);
            assert (!s1_rvalid || s1_rd_out);
            // P4: single outstanding is enforced by the DUT's own READY output,
            // not merely by a well-behaved master -- so assert on awready/arready
            // directly. Asserting "the master never issues a second AW" would be
            // vacuous here, since assumption A5 already forbids it.
            assert (!s0_aw_done || !s0_awready);
            assert (!s0_rd_out  || !s0_arready);
            assert (!s1_aw_done || !s1_awready);
            assert (!s1_rd_out  || !s1_arready);
        end
    end
`endif

    // -------------------------------------------------------------------------
    // P6: a W beat is never pushed to a destination with no AW pending there.
    // The bound assertions also prove the pending counters cannot wrap, which
    // is what makes the first assertion sound.
    // -------------------------------------------------------------------------
`ifdef PROP_WORDER
    always @(posedge aclk) begin
        if (chk) begin
            assert (!(m0_wvalid && m0_wready && (m0_awpend == 3'd0)));
            assert (!(m1_wvalid && m1_wready && (m1_awpend == 3'd0)));
            assert (m0_awpend <= 3'd2);
            assert (m1_awpend <= 3'd2);
        end
    end
`endif

endmodule
