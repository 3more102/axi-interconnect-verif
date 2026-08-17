// -----------------------------------------------------------------------------
// tb_axi4_interconnect.v
// Self-checking testbench for axi4_interconnect (SPEC.md sections 5, 10).
//
// Topology: 2 x axi4_master_bfm (ID_WIDTH=4) -> DUT -> 2 x axi4_mem_slave
//           (ID_WIDTH=5, MEM_BYTES=3072), plus the DUT's internal burst-capable
//           DECERR default slave. Passive axi4_protocol_checker on all four DUT
//           interfaces (slave ports ID_WIDTH=4, master ports ID_WIDTH=5) and
//           axi4_coverage on the two slave ports -- the only place in the whole
//           regression where DECERR responses are observable.
//
// Tests (+TEST=): targeted | decerr | parallel | contention | random
// Options       : +SEED=<n> (default 1), +DUMP (VCD waves)
//
// Concurrency discipline (same as tb_axi4_lite_interconnect): the two masters
// run under fork/join, so each gets its OWN static scoreboard tasks and its OWN
// error counter, and they own disjoint address regions on BOTH slaves so the
// reference model can never be raced:
//     master 0 -> offsets 0x000..0x5FF
//     master 1 -> offsets 0x600..0xBFF
// Both regions sit inside the slaves' OKAY range (offset < MEM_BYTES = 0xC00).
// Unmapped DECERR addresses are stateless and therefore safe for both masters.
//
// Language subset (SPEC.md section 0): Verilog-2001 plus only
// $urandom / $urandom_range / $value$plusargs / $test$plusargs.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_axi4_interconnect;

  localparam MID         = 4;        // master-side ID width
  localparam SID         = 5;        // slave-side ID width (MID + 1)
  localparam MEM_BYTES   = 3072;
  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;
  localparam RESP_DECERR = 2'b11;
  localparam DEF_RDATA   = 32'hDEC0DE00;

  localparam BT_FIXED = 2'b00;
  localparam BT_INCR  = 2'b01;
  localparam BT_WRAP  = 2'b10;

  // per-master disjoint address regions (byte offsets within a slave)
  localparam M0_LO = 32'h000, M0_HI = 32'h600;   // [lo, hi)
  localparam M1_LO = 32'h600, M1_HI = 32'hC00;

  // ---------------------------------------------------------------------------
  // Clock / reset
  // ---------------------------------------------------------------------------
  reg aclk;
  reg aresetn;

  initial begin
    aclk = 1'b0;
    forever #5 aclk = ~aclk;                 // 10 ns period
  end

  initial begin
    aresetn = 1'b0;
    repeat (5) @(posedge aclk);
    aresetn <= 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Master-side interfaces (BFM <-> DUT slave ports), ID width 4
  // ---------------------------------------------------------------------------
  wire [MID-1:0] s0_awid;  wire [31:0] s0_awaddr; wire [7:0] s0_awlen;
  wire [2:0]     s0_awsize; wire [1:0] s0_awburst; wire [2:0] s0_awprot;
  wire           s0_awvalid, s0_awready;
  wire [31:0]    s0_wdata; wire [3:0] s0_wstrb;
  wire           s0_wlast, s0_wvalid, s0_wready;
  wire [MID-1:0] s0_bid;  wire [1:0] s0_bresp; wire s0_bvalid, s0_bready;
  wire [MID-1:0] s0_arid; wire [31:0] s0_araddr; wire [7:0] s0_arlen;
  wire [2:0]     s0_arsize; wire [1:0] s0_arburst; wire [2:0] s0_arprot;
  wire           s0_arvalid, s0_arready;
  wire [MID-1:0] s0_rid; wire [31:0] s0_rdata; wire [1:0] s0_rresp;
  wire           s0_rlast, s0_rvalid, s0_rready;

  wire [MID-1:0] s1_awid;  wire [31:0] s1_awaddr; wire [7:0] s1_awlen;
  wire [2:0]     s1_awsize; wire [1:0] s1_awburst; wire [2:0] s1_awprot;
  wire           s1_awvalid, s1_awready;
  wire [31:0]    s1_wdata; wire [3:0] s1_wstrb;
  wire           s1_wlast, s1_wvalid, s1_wready;
  wire [MID-1:0] s1_bid;  wire [1:0] s1_bresp; wire s1_bvalid, s1_bready;
  wire [MID-1:0] s1_arid; wire [31:0] s1_araddr; wire [7:0] s1_arlen;
  wire [2:0]     s1_arsize; wire [1:0] s1_arburst; wire [2:0] s1_arprot;
  wire           s1_arvalid, s1_arready;
  wire [MID-1:0] s1_rid; wire [31:0] s1_rdata; wire [1:0] s1_rresp;
  wire           s1_rlast, s1_rvalid, s1_rready;

  // ---------------------------------------------------------------------------
  // Slave-side interfaces (DUT master ports <-> memory slaves), ID width 5
  // ---------------------------------------------------------------------------
  wire [SID-1:0] m0_awid;  wire [31:0] m0_awaddr; wire [7:0] m0_awlen;
  wire [2:0]     m0_awsize; wire [1:0] m0_awburst; wire [2:0] m0_awprot;
  wire           m0_awvalid, m0_awready;
  wire [31:0]    m0_wdata; wire [3:0] m0_wstrb;
  wire           m0_wlast, m0_wvalid, m0_wready;
  wire [SID-1:0] m0_bid;  wire [1:0] m0_bresp; wire m0_bvalid, m0_bready;
  wire [SID-1:0] m0_arid; wire [31:0] m0_araddr; wire [7:0] m0_arlen;
  wire [2:0]     m0_arsize; wire [1:0] m0_arburst; wire [2:0] m0_arprot;
  wire           m0_arvalid, m0_arready;
  wire [SID-1:0] m0_rid; wire [31:0] m0_rdata; wire [1:0] m0_rresp;
  wire           m0_rlast, m0_rvalid, m0_rready;

  wire [SID-1:0] m1_awid;  wire [31:0] m1_awaddr; wire [7:0] m1_awlen;
  wire [2:0]     m1_awsize; wire [1:0] m1_awburst; wire [2:0] m1_awprot;
  wire           m1_awvalid, m1_awready;
  wire [31:0]    m1_wdata; wire [3:0] m1_wstrb;
  wire           m1_wlast, m1_wvalid, m1_wready;
  wire [SID-1:0] m1_bid;  wire [1:0] m1_bresp; wire m1_bvalid, m1_bready;
  wire [SID-1:0] m1_arid; wire [31:0] m1_araddr; wire [7:0] m1_arlen;
  wire [2:0]     m1_arsize; wire [1:0] m1_arburst; wire [2:0] m1_arprot;
  wire           m1_arvalid, m1_arready;
  wire [SID-1:0] m1_rid; wire [31:0] m1_rdata; wire [1:0] m1_rresp;
  wire           m1_rlast, m1_rvalid, m1_rready;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  axi4_interconnect #(.ID_WIDTH (MID)) u_dut (
    .aclk (aclk), .aresetn (aresetn),

    .s0_axi_awid (s0_awid), .s0_axi_awaddr (s0_awaddr), .s0_axi_awlen (s0_awlen),
    .s0_axi_awsize (s0_awsize), .s0_axi_awburst (s0_awburst),
    .s0_axi_awprot (s0_awprot), .s0_axi_awvalid (s0_awvalid),
    .s0_axi_awready (s0_awready),
    .s0_axi_wdata (s0_wdata), .s0_axi_wstrb (s0_wstrb), .s0_axi_wlast (s0_wlast),
    .s0_axi_wvalid (s0_wvalid), .s0_axi_wready (s0_wready),
    .s0_axi_bid (s0_bid), .s0_axi_bresp (s0_bresp),
    .s0_axi_bvalid (s0_bvalid), .s0_axi_bready (s0_bready),
    .s0_axi_arid (s0_arid), .s0_axi_araddr (s0_araddr), .s0_axi_arlen (s0_arlen),
    .s0_axi_arsize (s0_arsize), .s0_axi_arburst (s0_arburst),
    .s0_axi_arprot (s0_arprot), .s0_axi_arvalid (s0_arvalid),
    .s0_axi_arready (s0_arready),
    .s0_axi_rid (s0_rid), .s0_axi_rdata (s0_rdata), .s0_axi_rresp (s0_rresp),
    .s0_axi_rlast (s0_rlast), .s0_axi_rvalid (s0_rvalid),
    .s0_axi_rready (s0_rready),

    .s1_axi_awid (s1_awid), .s1_axi_awaddr (s1_awaddr), .s1_axi_awlen (s1_awlen),
    .s1_axi_awsize (s1_awsize), .s1_axi_awburst (s1_awburst),
    .s1_axi_awprot (s1_awprot), .s1_axi_awvalid (s1_awvalid),
    .s1_axi_awready (s1_awready),
    .s1_axi_wdata (s1_wdata), .s1_axi_wstrb (s1_wstrb), .s1_axi_wlast (s1_wlast),
    .s1_axi_wvalid (s1_wvalid), .s1_axi_wready (s1_wready),
    .s1_axi_bid (s1_bid), .s1_axi_bresp (s1_bresp),
    .s1_axi_bvalid (s1_bvalid), .s1_axi_bready (s1_bready),
    .s1_axi_arid (s1_arid), .s1_axi_araddr (s1_araddr), .s1_axi_arlen (s1_arlen),
    .s1_axi_arsize (s1_arsize), .s1_axi_arburst (s1_arburst),
    .s1_axi_arprot (s1_arprot), .s1_axi_arvalid (s1_arvalid),
    .s1_axi_arready (s1_arready),
    .s1_axi_rid (s1_rid), .s1_axi_rdata (s1_rdata), .s1_axi_rresp (s1_rresp),
    .s1_axi_rlast (s1_rlast), .s1_axi_rvalid (s1_rvalid),
    .s1_axi_rready (s1_rready),

    .m0_axi_awid (m0_awid), .m0_axi_awaddr (m0_awaddr), .m0_axi_awlen (m0_awlen),
    .m0_axi_awsize (m0_awsize), .m0_axi_awburst (m0_awburst),
    .m0_axi_awprot (m0_awprot), .m0_axi_awvalid (m0_awvalid),
    .m0_axi_awready (m0_awready),
    .m0_axi_wdata (m0_wdata), .m0_axi_wstrb (m0_wstrb), .m0_axi_wlast (m0_wlast),
    .m0_axi_wvalid (m0_wvalid), .m0_axi_wready (m0_wready),
    .m0_axi_bid (m0_bid), .m0_axi_bresp (m0_bresp),
    .m0_axi_bvalid (m0_bvalid), .m0_axi_bready (m0_bready),
    .m0_axi_arid (m0_arid), .m0_axi_araddr (m0_araddr), .m0_axi_arlen (m0_arlen),
    .m0_axi_arsize (m0_arsize), .m0_axi_arburst (m0_arburst),
    .m0_axi_arprot (m0_arprot), .m0_axi_arvalid (m0_arvalid),
    .m0_axi_arready (m0_arready),
    .m0_axi_rid (m0_rid), .m0_axi_rdata (m0_rdata), .m0_axi_rresp (m0_rresp),
    .m0_axi_rlast (m0_rlast), .m0_axi_rvalid (m0_rvalid),
    .m0_axi_rready (m0_rready),

    .m1_axi_awid (m1_awid), .m1_axi_awaddr (m1_awaddr), .m1_axi_awlen (m1_awlen),
    .m1_axi_awsize (m1_awsize), .m1_axi_awburst (m1_awburst),
    .m1_axi_awprot (m1_awprot), .m1_axi_awvalid (m1_awvalid),
    .m1_axi_awready (m1_awready),
    .m1_axi_wdata (m1_wdata), .m1_axi_wstrb (m1_wstrb), .m1_axi_wlast (m1_wlast),
    .m1_axi_wvalid (m1_wvalid), .m1_axi_wready (m1_wready),
    .m1_axi_bid (m1_bid), .m1_axi_bresp (m1_bresp),
    .m1_axi_bvalid (m1_bvalid), .m1_axi_bready (m1_bready),
    .m1_axi_arid (m1_arid), .m1_axi_araddr (m1_araddr), .m1_axi_arlen (m1_arlen),
    .m1_axi_arsize (m1_arsize), .m1_axi_arburst (m1_arburst),
    .m1_axi_arprot (m1_arprot), .m1_axi_arvalid (m1_arvalid),
    .m1_axi_arready (m1_arready),
    .m1_axi_rid (m1_rid), .m1_axi_rdata (m1_rdata), .m1_axi_rresp (m1_rresp),
    .m1_axi_rlast (m1_rlast), .m1_axi_rvalid (m1_rvalid),
    .m1_axi_rready (m1_rready)
  );

  // ---------------------------------------------------------------------------
  // Master BFMs
  // ---------------------------------------------------------------------------
  axi4_master_bfm #(.ID_WIDTH (MID)) u_bfm0 (
    .aclk (aclk), .aresetn (aresetn),
    .m_axi_awid (s0_awid), .m_axi_awaddr (s0_awaddr), .m_axi_awlen (s0_awlen),
    .m_axi_awsize (s0_awsize), .m_axi_awburst (s0_awburst),
    .m_axi_awprot (s0_awprot), .m_axi_awvalid (s0_awvalid),
    .m_axi_awready (s0_awready),
    .m_axi_wdata (s0_wdata), .m_axi_wstrb (s0_wstrb), .m_axi_wlast (s0_wlast),
    .m_axi_wvalid (s0_wvalid), .m_axi_wready (s0_wready),
    .m_axi_bid (s0_bid), .m_axi_bresp (s0_bresp),
    .m_axi_bvalid (s0_bvalid), .m_axi_bready (s0_bready),
    .m_axi_arid (s0_arid), .m_axi_araddr (s0_araddr), .m_axi_arlen (s0_arlen),
    .m_axi_arsize (s0_arsize), .m_axi_arburst (s0_arburst),
    .m_axi_arprot (s0_arprot), .m_axi_arvalid (s0_arvalid),
    .m_axi_arready (s0_arready),
    .m_axi_rid (s0_rid), .m_axi_rdata (s0_rdata), .m_axi_rresp (s0_rresp),
    .m_axi_rlast (s0_rlast), .m_axi_rvalid (s0_rvalid), .m_axi_rready (s0_rready)
  );

  axi4_master_bfm #(.ID_WIDTH (MID)) u_bfm1 (
    .aclk (aclk), .aresetn (aresetn),
    .m_axi_awid (s1_awid), .m_axi_awaddr (s1_awaddr), .m_axi_awlen (s1_awlen),
    .m_axi_awsize (s1_awsize), .m_axi_awburst (s1_awburst),
    .m_axi_awprot (s1_awprot), .m_axi_awvalid (s1_awvalid),
    .m_axi_awready (s1_awready),
    .m_axi_wdata (s1_wdata), .m_axi_wstrb (s1_wstrb), .m_axi_wlast (s1_wlast),
    .m_axi_wvalid (s1_wvalid), .m_axi_wready (s1_wready),
    .m_axi_bid (s1_bid), .m_axi_bresp (s1_bresp),
    .m_axi_bvalid (s1_bvalid), .m_axi_bready (s1_bready),
    .m_axi_arid (s1_arid), .m_axi_araddr (s1_araddr), .m_axi_arlen (s1_arlen),
    .m_axi_arsize (s1_arsize), .m_axi_arburst (s1_arburst),
    .m_axi_arprot (s1_arprot), .m_axi_arvalid (s1_arvalid),
    .m_axi_arready (s1_arready),
    .m_axi_rid (s1_rid), .m_axi_rdata (s1_rdata), .m_axi_rresp (s1_rresp),
    .m_axi_rlast (s1_rlast), .m_axi_rvalid (s1_rvalid), .m_axi_rready (s1_rready)
  );

  // ---------------------------------------------------------------------------
  // Memory slaves behind the DUT's master ports
  // ---------------------------------------------------------------------------
  axi4_mem_slave #(.ID_WIDTH (SID), .MEM_BYTES (MEM_BYTES)) u_slv0 (
    .aclk (aclk), .aresetn (aresetn),
    .s_axi_awid (m0_awid), .s_axi_awaddr (m0_awaddr), .s_axi_awlen (m0_awlen),
    .s_axi_awsize (m0_awsize), .s_axi_awburst (m0_awburst),
    .s_axi_awprot (m0_awprot), .s_axi_awvalid (m0_awvalid),
    .s_axi_awready (m0_awready),
    .s_axi_wdata (m0_wdata), .s_axi_wstrb (m0_wstrb), .s_axi_wlast (m0_wlast),
    .s_axi_wvalid (m0_wvalid), .s_axi_wready (m0_wready),
    .s_axi_bid (m0_bid), .s_axi_bresp (m0_bresp),
    .s_axi_bvalid (m0_bvalid), .s_axi_bready (m0_bready),
    .s_axi_arid (m0_arid), .s_axi_araddr (m0_araddr), .s_axi_arlen (m0_arlen),
    .s_axi_arsize (m0_arsize), .s_axi_arburst (m0_arburst),
    .s_axi_arprot (m0_arprot), .s_axi_arvalid (m0_arvalid),
    .s_axi_arready (m0_arready),
    .s_axi_rid (m0_rid), .s_axi_rdata (m0_rdata), .s_axi_rresp (m0_rresp),
    .s_axi_rlast (m0_rlast), .s_axi_rvalid (m0_rvalid), .s_axi_rready (m0_rready)
  );

  axi4_mem_slave #(.ID_WIDTH (SID), .MEM_BYTES (MEM_BYTES)) u_slv1 (
    .aclk (aclk), .aresetn (aresetn),
    .s_axi_awid (m1_awid), .s_axi_awaddr (m1_awaddr), .s_axi_awlen (m1_awlen),
    .s_axi_awsize (m1_awsize), .s_axi_awburst (m1_awburst),
    .s_axi_awprot (m1_awprot), .s_axi_awvalid (m1_awvalid),
    .s_axi_awready (m1_awready),
    .s_axi_wdata (m1_wdata), .s_axi_wstrb (m1_wstrb), .s_axi_wlast (m1_wlast),
    .s_axi_wvalid (m1_wvalid), .s_axi_wready (m1_wready),
    .s_axi_bid (m1_bid), .s_axi_bresp (m1_bresp),
    .s_axi_bvalid (m1_bvalid), .s_axi_bready (m1_bready),
    .s_axi_arid (m1_arid), .s_axi_araddr (m1_araddr), .s_axi_arlen (m1_arlen),
    .s_axi_arsize (m1_arsize), .s_axi_arburst (m1_arburst),
    .s_axi_arprot (m1_arprot), .s_axi_arvalid (m1_arvalid),
    .s_axi_arready (m1_arready),
    .s_axi_rid (m1_rid), .s_axi_rdata (m1_rdata), .s_axi_rresp (m1_rresp),
    .s_axi_rlast (m1_rlast), .s_axi_rvalid (m1_rvalid), .s_axi_rready (m1_rready)
  );

  // ---------------------------------------------------------------------------
  // Passive protocol checkers on all four DUT interfaces
  // ---------------------------------------------------------------------------
  axi4_protocol_checker #(.ID_WIDTH (MID), .NAME ("S0PC")) u_pc_s0 (
    .aclk (aclk), .aresetn (aresetn),
    .awid (s0_awid), .awaddr (s0_awaddr), .awlen (s0_awlen),
    .awsize (s0_awsize), .awburst (s0_awburst), .awprot (s0_awprot),
    .awvalid (s0_awvalid), .awready (s0_awready),
    .wdata (s0_wdata), .wstrb (s0_wstrb), .wlast (s0_wlast),
    .wvalid (s0_wvalid), .wready (s0_wready),
    .bid (s0_bid), .bresp (s0_bresp), .bvalid (s0_bvalid), .bready (s0_bready),
    .arid (s0_arid), .araddr (s0_araddr), .arlen (s0_arlen),
    .arsize (s0_arsize), .arburst (s0_arburst), .arprot (s0_arprot),
    .arvalid (s0_arvalid), .arready (s0_arready),
    .rid (s0_rid), .rdata (s0_rdata), .rresp (s0_rresp), .rlast (s0_rlast),
    .rvalid (s0_rvalid), .rready (s0_rready)
  );

  axi4_protocol_checker #(.ID_WIDTH (MID), .NAME ("S1PC")) u_pc_s1 (
    .aclk (aclk), .aresetn (aresetn),
    .awid (s1_awid), .awaddr (s1_awaddr), .awlen (s1_awlen),
    .awsize (s1_awsize), .awburst (s1_awburst), .awprot (s1_awprot),
    .awvalid (s1_awvalid), .awready (s1_awready),
    .wdata (s1_wdata), .wstrb (s1_wstrb), .wlast (s1_wlast),
    .wvalid (s1_wvalid), .wready (s1_wready),
    .bid (s1_bid), .bresp (s1_bresp), .bvalid (s1_bvalid), .bready (s1_bready),
    .arid (s1_arid), .araddr (s1_araddr), .arlen (s1_arlen),
    .arsize (s1_arsize), .arburst (s1_arburst), .arprot (s1_arprot),
    .arvalid (s1_arvalid), .arready (s1_arready),
    .rid (s1_rid), .rdata (s1_rdata), .rresp (s1_rresp), .rlast (s1_rlast),
    .rvalid (s1_rvalid), .rready (s1_rready)
  );

  axi4_protocol_checker #(.ID_WIDTH (SID), .NAME ("M0PC")) u_pc_m0 (
    .aclk (aclk), .aresetn (aresetn),
    .awid (m0_awid), .awaddr (m0_awaddr), .awlen (m0_awlen),
    .awsize (m0_awsize), .awburst (m0_awburst), .awprot (m0_awprot),
    .awvalid (m0_awvalid), .awready (m0_awready),
    .wdata (m0_wdata), .wstrb (m0_wstrb), .wlast (m0_wlast),
    .wvalid (m0_wvalid), .wready (m0_wready),
    .bid (m0_bid), .bresp (m0_bresp), .bvalid (m0_bvalid), .bready (m0_bready),
    .arid (m0_arid), .araddr (m0_araddr), .arlen (m0_arlen),
    .arsize (m0_arsize), .arburst (m0_arburst), .arprot (m0_arprot),
    .arvalid (m0_arvalid), .arready (m0_arready),
    .rid (m0_rid), .rdata (m0_rdata), .rresp (m0_rresp), .rlast (m0_rlast),
    .rvalid (m0_rvalid), .rready (m0_rready)
  );

  axi4_protocol_checker #(.ID_WIDTH (SID), .NAME ("M1PC")) u_pc_m1 (
    .aclk (aclk), .aresetn (aresetn),
    .awid (m1_awid), .awaddr (m1_awaddr), .awlen (m1_awlen),
    .awsize (m1_awsize), .awburst (m1_awburst), .awprot (m1_awprot),
    .awvalid (m1_awvalid), .awready (m1_awready),
    .wdata (m1_wdata), .wstrb (m1_wstrb), .wlast (m1_wlast),
    .wvalid (m1_wvalid), .wready (m1_wready),
    .bid (m1_bid), .bresp (m1_bresp), .bvalid (m1_bvalid), .bready (m1_bready),
    .arid (m1_arid), .araddr (m1_araddr), .arlen (m1_arlen),
    .arsize (m1_arsize), .arburst (m1_arburst), .arprot (m1_arprot),
    .arvalid (m1_arvalid), .arready (m1_arready),
    .rid (m1_rid), .rdata (m1_rdata), .rresp (m1_rresp), .rlast (m1_rlast),
    .rvalid (m1_rvalid), .rready (m1_rready)
  );

  // ---------------------------------------------------------------------------
  // Functional coverage on the two slave ports (sees DECERR, which the memory
  // slaves never produce -- these instances close the resp bins)
  // ---------------------------------------------------------------------------
  axi4_coverage #(.ID_WIDTH (MID), .NAME ("S0CV")) u_cov_s0 (
    .aclk (aclk), .aresetn (aresetn),
    .awid (s0_awid), .awaddr (s0_awaddr), .awlen (s0_awlen),
    .awsize (s0_awsize), .awburst (s0_awburst), .awprot (s0_awprot),
    .awvalid (s0_awvalid), .awready (s0_awready),
    .wdata (s0_wdata), .wstrb (s0_wstrb), .wlast (s0_wlast),
    .wvalid (s0_wvalid), .wready (s0_wready),
    .bid (s0_bid), .bresp (s0_bresp), .bvalid (s0_bvalid), .bready (s0_bready),
    .arid (s0_arid), .araddr (s0_araddr), .arlen (s0_arlen),
    .arsize (s0_arsize), .arburst (s0_arburst), .arprot (s0_arprot),
    .arvalid (s0_arvalid), .arready (s0_arready),
    .rid (s0_rid), .rdata (s0_rdata), .rresp (s0_rresp), .rlast (s0_rlast),
    .rvalid (s0_rvalid), .rready (s0_rready)
  );

  axi4_coverage #(.ID_WIDTH (MID), .NAME ("S1CV")) u_cov_s1 (
    .aclk (aclk), .aresetn (aresetn),
    .awid (s1_awid), .awaddr (s1_awaddr), .awlen (s1_awlen),
    .awsize (s1_awsize), .awburst (s1_awburst), .awprot (s1_awprot),
    .awvalid (s1_awvalid), .awready (s1_awready),
    .wdata (s1_wdata), .wstrb (s1_wstrb), .wlast (s1_wlast),
    .wvalid (s1_wvalid), .wready (s1_wready),
    .bid (s1_bid), .bresp (s1_bresp), .bvalid (s1_bvalid), .bready (s1_bready),
    .arid (s1_arid), .araddr (s1_araddr), .arlen (s1_arlen),
    .arsize (s1_arsize), .arburst (s1_arburst), .arprot (s1_arprot),
    .arvalid (s1_arvalid), .arready (s1_arready),
    .rid (s1_rid), .rdata (s1_rdata), .rresp (s1_rresp), .rlast (s1_rlast),
    .rvalid (s1_rvalid), .rready (s1_rready)
  );

  // ---------------------------------------------------------------------------
  // Crossbar concurrency observer (F22). A serializing interconnect would still
  // pass a naive parallel test, so record whether both destination ports were
  // ever driven in the same cycle.
  // ---------------------------------------------------------------------------
  reg concurrent_seen;
  always @(posedge aclk) begin
    if (!aresetn)
      concurrent_seen <= 1'b0;
    else if ((m0_awvalid && m1_awvalid) || (m0_arvalid && m1_arvalid) ||
             (m0_wvalid  && m1_wvalid)  || (m0_rvalid  && m1_rvalid))
      concurrent_seen <= 1'b1;
  end

  // ---------------------------------------------------------------------------
  // Test bookkeeping and reference model
  // ---------------------------------------------------------------------------
  reg [255:0] testname;
  integer     seed, seed_req, dummy;
  integer     sb_errors, sb_err0, sb_err1;
  integer     bursts0, bursts1;
  integer     i, j0, j1;
  integer     pi0, pi1;      // prefill loop indices, one per master thread

  // 2 slaves x 1024 words, plus a per-byte "has been written" mask
  reg [31:0] model    [0:2047];
  reg [3:0]  mem_bval [0:2047];

  // per-master scratch (never shared between the two forked threads)
  integer rb0, rs0, rl0, rt0, rbase0, ra0, rslot0, rsl0;
  integer rb1, rs1, rl1, rt1, rbase1, ra1, rslot1, rsl1;
  reg [MID-1:0] rid0, rid1;

  // ---------------------------------------------------------------------------
  // Helper functions
  // ---------------------------------------------------------------------------
  function [31:0] beat_addr_of;
    input [31:0] addr;
    input [7:0]  len;
    input [2:0]  size;
    input [1:0]  burst;
    input integer bi;
    integer nbytes, total, k;
    reg [31:0] lower, upper, a;
    begin
      nbytes = 1 << size;
      total  = (len + 1) * nbytes;
      lower  = (addr / total) * total;
      upper  = lower + total;
      a      = addr;
      for (k = 0; k < bi; k = k + 1) begin
        if (burst != BT_FIXED) begin
          a = a + nbytes;
          if (burst == BT_WRAP && a >= upper)
            a = lower;
        end
      end
      beat_addr_of = a;
    end
  endfunction

  function [31:0] size_mask;
    input [2:0] size;
    begin
      case (size)
        3'd0:    size_mask = 32'h0000_00FF;
        3'd1:    size_mask = 32'h0000_FFFF;
        default: size_mask = 32'hFFFF_FFFF;
      endcase
    end
  endfunction

  // decoded destination: 0 -> slave 0, 1 -> slave 1, 2 -> internal DECERR slave
  function integer dest_of;
    input [31:0] addr;
    begin
      if (addr[31:12] == 20'h00000)      dest_of = 0;
      else if (addr[31:12] == 20'h00001) dest_of = 1;
      else                               dest_of = 2;
    end
  endfunction

  // address of byte `off` in slave `s`
  function [31:0] sa;
    input integer s;
    input integer off;
    begin
      sa = (s << 12) | off;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Scoreboarded burst operations -- one static task pair per master, because
  // the two masters run concurrently under fork/join and static task locals
  // cannot be shared between threads.
  // ---------------------------------------------------------------------------
`define IC_WR_BURST(TASKNAME, BFM, ERRC, NB)                                   \
  task TASKNAME;                                                               \
    input [MID-1:0] id;                                                        \
    input [31:0]    addr;                                                      \
    input [7:0]     len;                                                       \
    input [2:0]     size;                                                      \
    input [1:0]     burst;                                                     \
    integer    bi, b, nbytes, lane, widx, off, dst;                            \
    reg [1:0]  resp, exp_resp;                                                 \
    reg [31:0] A, tmp, byteval;                                                \
    begin                                                                      \
      nbytes = 1 << size;                                                      \
      dst    = dest_of(addr);                                                  \
      for (bi = 0; bi <= len; bi = bi + 1)                                     \
        BFM.wbuf[bi] = $urandom & size_mask(size);                             \
      if (dst == 2) exp_resp = RESP_DECERR;                                    \
      else begin                                                               \
        exp_resp = RESP_OKAY;                                                  \
        for (bi = 0; bi <= len; bi = bi + 1) begin                             \
          A = beat_addr_of(addr, len, size, burst, bi);                        \
          if ((A % 4096) >= MEM_BYTES) exp_resp = RESP_SLVERR;                 \
        end                                                                    \
      end                                                                      \
      BFM.axi_write_burst(id, addr, len, size, burst, resp);                   \
      if (resp !== exp_resp) begin                                             \
        ERRC = ERRC + 1;                                                       \
        $display("[TB] %0t SB: BRESP addr=0x%08h len=%0d size=%0d exp=%b got=%b", \
                 $time, addr, len, size, exp_resp, resp);                      \
      end                                                                      \
      if (dst != 2) begin                                                      \
        for (bi = 0; bi <= len; bi = bi + 1) begin                             \
          A    = beat_addr_of(addr, len, size, burst, bi);                     \
          off  = A % 4096;                                                     \
          lane = A % 4;                                                        \
          widx = dst * 1024 + (off >> 2);                                      \
          if (off < MEM_BYTES) begin                                           \
            tmp = model[widx];                                                 \
            for (b = 0; b < nbytes; b = b + 1) begin                           \
              byteval = (BFM.wbuf[bi] >> (8 * b)) & 32'h0000_00FF;             \
              tmp     = tmp & ~(32'h0000_00FF << (8 * (lane + b)));            \
              tmp     = tmp | (byteval << (8 * (lane + b)));                   \
              mem_bval[widx] = mem_bval[widx] | (4'd1 << (lane + b));          \
            end                                                                \
            model[widx] = tmp;                                                 \
          end                                                                  \
        end                                                                    \
      end                                                                      \
      NB = NB + 1;                                                             \
    end                                                                        \
  endtask

`define IC_RD_BURST(TASKNAME, BFM, ERRC, NB)                                   \
  task TASKNAME;                                                               \
    input [MID-1:0] id;                                                        \
    input [31:0]    addr;                                                      \
    input [7:0]     len;                                                       \
    input [2:0]     size;                                                      \
    input [1:0]     burst;                                                     \
    integer    bi, b, nbytes, lane, widx, off, dst;                            \
    reg [1:0]  resp, exp_worst, exp_beat;                                      \
    reg [31:0] A, exp_data;                                                    \
    reg        all_valid;                                                      \
    begin                                                                      \
      nbytes    = 1 << size;                                                   \
      dst       = dest_of(addr);                                               \
      exp_worst = RESP_OKAY;                                                   \
      BFM.axi_read_burst(id, addr, len, size, burst, resp);                    \
      for (bi = 0; bi <= len; bi = bi + 1) begin                               \
        A    = beat_addr_of(addr, len, size, burst, bi);                       \
        off  = A % 4096;                                                       \
        lane = A % 4;                                                          \
        widx = dst * 1024 + (off >> 2);                                        \
        all_valid = 1'b1;                                                      \
        if (dst == 2) begin                                                    \
          exp_beat = RESP_DECERR;                                              \
          exp_data = (DEF_RDATA >> (8 * lane)) & size_mask(size);              \
        end else if (off >= MEM_BYTES) begin                                   \
          exp_beat = RESP_SLVERR;                                              \
          exp_data = 32'h0000_0000;                                            \
        end else begin                                                         \
          exp_beat = RESP_OKAY;                                                \
          exp_data = 32'h0000_0000;                                            \
          for (b = 0; b < nbytes; b = b + 1) begin                             \
            if (!mem_bval[widx][lane + b]) all_valid = 1'b0;                   \
            exp_data = exp_data |                                              \
              (((model[widx] >> (8 * (lane + b))) & 32'h0000_00FF) << (8 * b)); \
          end                                                                  \
        end                                                                    \
        if (exp_beat > exp_worst) exp_worst = exp_beat;                        \
        if (BFM.rresp_buf[bi] !== exp_beat) begin                              \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: RRESP beat %0d addr=0x%08h exp=%b got=%b",    \
                   $time, bi, A, exp_beat, BFM.rresp_buf[bi]);                 \
        end                                                                    \
        if (all_valid && (BFM.rbuf[bi] !== exp_data)) begin                    \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: RDATA beat %0d addr=0x%08h exp=0x%08h got=0x%08h", \
                   $time, bi, A, exp_data, BFM.rbuf[bi]);                      \
        end                                                                    \
      end                                                                      \
      if (resp !== exp_worst) begin                                            \
        ERRC = ERRC + 1;                                                       \
        $display("[TB] %0t SB: worst RRESP addr=0x%08h exp=%b got=%b",         \
                 $time, addr, exp_worst, resp);                                \
      end                                                                      \
      NB = NB + 1;                                                             \
    end                                                                        \
  endtask

  `IC_WR_BURST(wr0, u_bfm0, sb_err0, bursts0)
  `IC_RD_BURST(rd0, u_bfm0, sb_err0, bursts0)
  `IC_WR_BURST(wr1, u_bfm1, sb_err1, bursts1)
  `IC_RD_BURST(rd1, u_bfm1, sb_err1, bursts1)

  // Word-granularity write-before-read: the memory slaves return the whole
  // addressed word and are not initialized, so each master fills its own region
  // on both slaves before reading anything back (see tb_axi4_mem_slave.v).
  // NOTE: pi0/pi1 are per-master loop indices, not the shared `i`. These two
  // tasks are called inside fork/join, and a shared index would let each thread
  // advance the other's loop -- leaving part of the window unwritten, which then
  // shows up as X on RDATA rather than as a data mismatch.
  task prefill_m0;
    begin
      for (pi0 = 0; pi0 < 2; pi0 = pi0 + 1) begin
        wr0(4'h0, sa(pi0, M0_LO + 32'h000), 8'd127, 3'd2, BT_INCR);
        wr0(4'h0, sa(pi0, M0_LO + 32'h200), 8'd127, 3'd2, BT_INCR);
        wr0(4'h0, sa(pi0, M0_LO + 32'h400), 8'd127, 3'd2, BT_INCR);
      end
    end
  endtask

  task prefill_m1;
    begin
      for (pi1 = 0; pi1 < 2; pi1 = pi1 + 1) begin
        wr1(4'h0, sa(pi1, M1_LO + 32'h000), 8'd127, 3'd2, BT_INCR);
        wr1(4'h0, sa(pi1, M1_LO + 32'h200), 8'd127, 3'd2, BT_INCR);
        wr1(4'h0, sa(pi1, M1_LO + 32'h400), 8'd127, 3'd2, BT_INCR);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  // targeted: each master bursts to each slave (INCR len 7), model-checked
  task test_targeted;
    begin
      for (i = 0; i < 2; i = i + 1) begin
        wr0(4'h1, sa(i, 32'h000), 8'd7, 3'd2, BT_INCR);
        rd0(4'h1, sa(i, 32'h000), 8'd7, 3'd2, BT_INCR);
        wr0(4'h2, sa(i, 32'h100), 8'd7, 3'd2, BT_INCR);
        rd0(4'h2, sa(i, 32'h100), 8'd7, 3'd2, BT_INCR);
      end
      for (i = 0; i < 2; i = i + 1) begin
        wr1(4'h3, sa(i, 32'h600), 8'd7, 3'd2, BT_INCR);
        rd1(4'h3, sa(i, 32'h600), 8'd7, 3'd2, BT_INCR);
        wr1(4'h4, sa(i, 32'h700), 8'd7, 3'd2, BT_INCR);
        rd1(4'h4, sa(i, 32'h700), 8'd7, 3'd2, BT_INCR);
      end
      // distinct IDs must come back reflected on the right master port
      wr0(4'hA, sa(0, 32'h200), 8'd7, 3'd2, BT_INCR);
      wr1(4'hA, sa(1, 32'h800), 8'd7, 3'd2, BT_INCR);
      rd0(4'hA, sa(0, 32'h200), 8'd7, 3'd2, BT_INCR);
      rd1(4'hA, sa(1, 32'h800), 8'd7, 3'd2, BT_INCR);
    end
  endtask

  // decerr: unmapped addresses from both masters. The BFM itself checks the
  // beat count and RLAST position, so a default slave that returned the wrong
  // number of R beats fails here (or hangs into the watchdog).
  task test_decerr;
    begin
      wr0(4'h1, 32'h0000_2000, 8'd0,  3'd2, BT_INCR);
      rd0(4'h1, 32'h0000_2000, 8'd0,  3'd2, BT_INCR);
      wr0(4'h2, 32'h0000_2000, 8'd7,  3'd2, BT_INCR);
      rd0(4'h2, 32'h0000_2000, 8'd7,  3'd2, BT_INCR);
      wr0(4'h3, 32'h8000_0000, 8'd15, 3'd2, BT_INCR);
      rd0(4'h3, 32'h8000_0000, 8'd15, 3'd2, BT_INCR);
      wr1(4'h4, 32'h0000_3000, 8'd0,  3'd2, BT_INCR);
      rd1(4'h4, 32'h0000_3000, 8'd0,  3'd2, BT_INCR);
      wr1(4'h5, 32'hFFFF_F000, 8'd3,  3'd2, BT_INCR);
      rd1(4'h5, 32'hFFFF_F000, 8'd3,  3'd2, BT_INCR);
      // narrow DECERR reads exercise the lane-shifted default read data
      rd1(4'h6, 32'h0000_2001, 8'd3,  3'd0, BT_INCR);
      // a DECERR burst must not disturb real traffic that follows it
      prefill_m0;
      rd0(4'h7, sa(0, 32'h000), 8'd7, 3'd2, BT_INCR);
      // both masters hitting the default slave at once
      fork
        begin
          for (j0 = 0; j0 < 8; j0 = j0 + 1) begin
            wr0(4'h8, 32'h0000_2000, 8'd3, 3'd2, BT_INCR);
            rd0(4'h8, 32'h0000_2000, 8'd3, 3'd2, BT_INCR);
          end
        end
        begin
          for (j1 = 0; j1 < 8; j1 = j1 + 1) begin
            wr1(4'h9, 32'h0000_5000, 8'd3, 3'd2, BT_INCR);
            rd1(4'h9, 32'h0000_5000, 8'd3, 3'd2, BT_INCR);
          end
        end
      join
    end
  endtask

  // parallel: M0->S0 with M1->S1, then the crossed pairing (long INCR len 15)
  task test_parallel;
    begin
      fork
        prefill_m0;
        prefill_m1;
      join
      fork
        begin
          for (j0 = 0; j0 < 8; j0 = j0 + 1) begin
            wr0(4'h1, sa(0, 32'h000 + j0 * 32'h40), 8'd15, 3'd2, BT_INCR);
            rd0(4'h1, sa(0, 32'h000 + j0 * 32'h40), 8'd15, 3'd2, BT_INCR);
          end
        end
        begin
          for (j1 = 0; j1 < 8; j1 = j1 + 1) begin
            wr1(4'h2, sa(1, 32'h600 + j1 * 32'h40), 8'd15, 3'd2, BT_INCR);
            rd1(4'h2, sa(1, 32'h600 + j1 * 32'h40), 8'd15, 3'd2, BT_INCR);
          end
        end
      join
      // crossed: M0->S1 while M1->S0
      fork
        begin
          for (j0 = 0; j0 < 8; j0 = j0 + 1) begin
            wr0(4'h3, sa(1, 32'h000 + j0 * 32'h40), 8'd15, 3'd2, BT_INCR);
            rd0(4'h3, sa(1, 32'h000 + j0 * 32'h40), 8'd15, 3'd2, BT_INCR);
          end
        end
        begin
          for (j1 = 0; j1 < 8; j1 = j1 + 1) begin
            wr1(4'h4, sa(0, 32'h600 + j1 * 32'h40), 8'd15, 3'd2, BT_INCR);
            rd1(4'h4, sa(0, 32'h600 + j1 * 32'h40), 8'd15, 3'd2, BT_INCR);
          end
        end
      join
      if (!concurrent_seen) begin
        sb_err0 = sb_err0 + 1;
        $display("[TB] %0t SB: no cycle with both destination ports active -- %0s",
                 $time, "crossbar is serializing");
      end
    end
  endtask

  // contention: both masters hammer the SAME slave, disjoint regions.
  // 20 bursts each; finishing at all is the fairness evidence (F21) -- a
  // starving arbiter would stall one master into the watchdog.
  task test_contention;
    begin
      fork
        prefill_m0;
        prefill_m1;
      join
      bursts0 = 0;
      bursts1 = 0;
      fork
        begin
          for (j0 = 0; j0 < 10; j0 = j0 + 1) begin
            wr0(4'h1, sa(0, 32'h000 + j0 * 32'h20), 8'd7, 3'd2, BT_INCR);
            rd0(4'h1, sa(0, 32'h000 + j0 * 32'h20), 8'd7, 3'd2, BT_INCR);
          end
        end
        begin
          for (j1 = 0; j1 < 10; j1 = j1 + 1) begin
            wr1(4'h2, sa(0, 32'h600 + j1 * 32'h20), 8'd7, 3'd2, BT_INCR);
            rd1(4'h2, sa(0, 32'h600 + j1 * 32'h20), 8'd7, 3'd2, BT_INCR);
          end
        end
      join
      if (bursts0 != 20 || bursts1 != 20) begin
        sb_err0 = sb_err0 + 1;
        $display("[TB] %0t SB: contention starvation bursts0=%0d bursts1=%0d",
                 $time, bursts0, bursts1);
      end
    end
  endtask

  // random: 60 legal random bursts per master over the full map, random IDs,
  // each master confined to its own address region so the model is race-free
  task test_random_m0;
    begin
      for (j0 = 0; j0 < 60; j0 = j0 + 1) begin
        rid0 = $urandom_range(0, 15);
        rs0  = $urandom_range(0, 2);
        rb0  = $urandom_range(0, 2);
        rsl0 = $urandom_range(0, 1);
        if ($urandom_range(0, 9) == 0) begin
          // unmapped -> DECERR
          if ($urandom_range(0, 1) == 0)
            wr0(rid0, 32'h0000_2000, 8'd3, 3'd2, BT_INCR);
          else
            rd0(rid0, 32'h0000_2000, 8'd3, 3'd2, BT_INCR);
        end else begin
          if (rb0 == 2) begin
            case ($urandom_range(0, 3))
              0: rl0 = 1;  1: rl0 = 3;  2: rl0 = 7;  default: rl0 = 15;
            endcase
            rt0    = (rl0 + 1) * (1 << rs0);
            rslot0 = (M0_HI - M0_LO) / rt0;
            rbase0 = M0_LO + $urandom_range(0, rslot0 - 1) * rt0;
            ra0    = rbase0 + $urandom_range(0, rl0) * (1 << rs0);
          end else if (rb0 == 1) begin
            rl0 = $urandom_range(0, 15);
            rt0 = (rl0 + 1) * (1 << rs0);
            ra0 = M0_LO + $urandom_range(0, (M0_HI - M0_LO - rt0) >> rs0)
                          * (1 << rs0);
          end else begin
            rl0 = $urandom_range(0, 3);
            ra0 = M0_LO + $urandom_range(0, ((M0_HI - M0_LO) >> rs0) - 1)
                          * (1 << rs0);
          end
          if ($urandom_range(0, 1) == 0)
            wr0(rid0, sa(rsl0, ra0), rl0[7:0], rs0[2:0], rb0[1:0]);
          else
            rd0(rid0, sa(rsl0, ra0), rl0[7:0], rs0[2:0], rb0[1:0]);
        end
      end
    end
  endtask

  task test_random_m1;
    begin
      for (j1 = 0; j1 < 60; j1 = j1 + 1) begin
        rid1 = $urandom_range(0, 15);
        rs1  = $urandom_range(0, 2);
        rb1  = $urandom_range(0, 2);
        rsl1 = $urandom_range(0, 1);
        if ($urandom_range(0, 9) == 0) begin
          if ($urandom_range(0, 1) == 0)
            wr1(rid1, 32'h0000_6000, 8'd3, 3'd2, BT_INCR);
          else
            rd1(rid1, 32'h0000_6000, 8'd3, 3'd2, BT_INCR);
        end else begin
          if (rb1 == 2) begin
            case ($urandom_range(0, 3))
              0: rl1 = 1;  1: rl1 = 3;  2: rl1 = 7;  default: rl1 = 15;
            endcase
            rt1    = (rl1 + 1) * (1 << rs1);
            rslot1 = (M1_HI - M1_LO) / rt1;
            rbase1 = M1_LO + $urandom_range(0, rslot1 - 1) * rt1;
            ra1    = rbase1 + $urandom_range(0, rl1) * (1 << rs1);
          end else if (rb1 == 1) begin
            rl1 = $urandom_range(0, 15);
            rt1 = (rl1 + 1) * (1 << rs1);
            ra1 = M1_LO + $urandom_range(0, (M1_HI - M1_LO - rt1) >> rs1)
                          * (1 << rs1);
          end else begin
            rl1 = $urandom_range(0, 3);
            ra1 = M1_LO + $urandom_range(0, ((M1_HI - M1_LO) >> rs1) - 1)
                          * (1 << rs1);
          end
          if ($urandom_range(0, 1) == 0)
            wr1(rid1, sa(rsl1, ra1), rl1[7:0], rs1[2:0], rb1[1:0]);
          else
            rd1(rid1, sa(rsl1, ra1), rl1[7:0], rs1[2:0], rb1[1:0]);
        end
      end
    end
  endtask

  task test_random;
    begin
      fork
        prefill_m0;
        prefill_m1;
      join
      fork
        test_random_m0;
        test_random_m1;
      join
    end
  endtask

  // ---------------------------------------------------------------------------
  // Verdict
  // ---------------------------------------------------------------------------
  task print_summary_fail;
    begin
      $display("=== TEST FAILED: %0s (sb=%0d pc=%0d bfm=%0d) ===",
               testname, sb_err0 + sb_err1,
               u_pc_s0.error_count + u_pc_s1.error_count +
               u_pc_m0.error_count + u_pc_m1.error_count,
               u_bfm0.bfm_errors + u_bfm1.bfm_errors);
    end
  endtask

  task summary;
    begin
      sb_errors = sb_err0 + sb_err1;
      if ((sb_errors == 0) &&
          (u_bfm0.bfm_errors == 0) && (u_bfm1.bfm_errors == 0) &&
          (u_pc_s0.error_count == 0) && (u_pc_s1.error_count == 0) &&
          (u_pc_m0.error_count == 0) && (u_pc_m1.error_count == 0))
        $display("=== TEST PASSED: %0s ===", testname);
      else
        print_summary_fail;
      u_cov_s0.print_coverage;
      u_cov_s1.print_coverage;
      $finish;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Watchdog
  // ---------------------------------------------------------------------------
  initial begin
    #5_000_000;
    $display("[TB] TIMEOUT");
    print_summary_fail;
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------------------
  initial begin : main
    if (!$value$plusargs("TEST=%s", testname)) testname = "targeted";
    seed = 1;
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    seed_req = seed;
    dummy    = $urandom(seed);   // seeds the stream; also overwrites `seed`
    if ($test$plusargs("DUMP")) begin
      $dumpfile("tb_axi4_interconnect.vcd");
      $dumpvars(0, tb_axi4_interconnect);
    end

    sb_err0 = 0;  sb_err1 = 0;  sb_errors = 0;
    bursts0 = 0;  bursts1 = 0;
    for (i = 0; i < 2048; i = i + 1) begin
      model[i]    = 32'h0000_0000;
      mem_bval[i] = 4'h0;
    end

    @(posedge aresetn);
    repeat (2) @(posedge aclk);
    $display("[TB] %0t running TEST=%0s SEED=%0d", $time, testname, seed_req);

    if      (testname == "targeted")   test_targeted;
    else if (testname == "decerr")     test_decerr;
    else if (testname == "parallel")   test_parallel;
    else if (testname == "contention") test_contention;
    else if (testname == "random")     test_random;
    else begin
      $display("[TB] %0t unknown TEST=%0s", $time, testname);
      sb_err0 = sb_err0 + 1;
    end

    repeat (5) @(posedge aclk);
    summary;
  end

endmodule
