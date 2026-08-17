// -----------------------------------------------------------------------------
// tb_axi4_lite_interconnect.v
// Self-checking testbench for axi4_lite_interconnect (SPEC.md sections 3, 10).
//
// Topology: 2 x axi4_lite_master_bfm -> DUT -> 2 x axi4_lite_slave (NUM_REGS=12),
// plus the DUT's internal DECERR default slave. Passive lite protocol checkers
// sit on all four DUT interfaces.
//
// Tests (+TEST=): targeted | decerr | contention | parallel | random
// Options       : +SEED=<n> (default 1), +DUMP (VCD waves)
//
// Concurrency discipline: the two masters run in fork/join for the contention,
// parallel and random tests, so each master gets its OWN scoreboard tasks and
// its OWN error counter. Static tasks are never shared between the two threads
// (SPEC.md section 0), and the two masters own disjoint register sets so the
// reference model can never be raced:
//     master 0 -> register indices 0..5   (invalid-index probes: 12, 13)
//     master 1 -> register indices 6..11  (invalid-index probes: 14, 15)
// DECERR addresses are stateless and therefore safe for both masters.
//
// Language subset (SPEC.md section 0): Verilog-2001 plus only
// $urandom / $urandom_range / $value$plusargs / $test$plusargs.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_axi4_lite_interconnect;

  localparam NUM_REGS    = 12;
  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;
  localparam RESP_DECERR = 2'b11;
  localparam DEF_RDATA   = 32'hDEC0DE00;

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
  // Master-side interfaces (BFM <-> DUT slave ports)
  // ---------------------------------------------------------------------------
  wire [31:0] s0_awaddr;  wire [2:0] s0_awprot;  wire s0_awvalid; wire s0_awready;
  wire [31:0] s0_wdata;   wire [3:0] s0_wstrb;   wire s0_wvalid;  wire s0_wready;
  wire [1:0]  s0_bresp;   wire       s0_bvalid;  wire s0_bready;
  wire [31:0] s0_araddr;  wire [2:0] s0_arprot;  wire s0_arvalid; wire s0_arready;
  wire [31:0] s0_rdata;   wire [1:0] s0_rresp;   wire s0_rvalid;  wire s0_rready;

  wire [31:0] s1_awaddr;  wire [2:0] s1_awprot;  wire s1_awvalid; wire s1_awready;
  wire [31:0] s1_wdata;   wire [3:0] s1_wstrb;   wire s1_wvalid;  wire s1_wready;
  wire [1:0]  s1_bresp;   wire       s1_bvalid;  wire s1_bready;
  wire [31:0] s1_araddr;  wire [2:0] s1_arprot;  wire s1_arvalid; wire s1_arready;
  wire [31:0] s1_rdata;   wire [1:0] s1_rresp;   wire s1_rvalid;  wire s1_rready;

  // ---------------------------------------------------------------------------
  // Slave-side interfaces (DUT master ports <-> lite slaves)
  // ---------------------------------------------------------------------------
  wire [31:0] m0_awaddr;  wire [2:0] m0_awprot;  wire m0_awvalid; wire m0_awready;
  wire [31:0] m0_wdata;   wire [3:0] m0_wstrb;   wire m0_wvalid;  wire m0_wready;
  wire [1:0]  m0_bresp;   wire       m0_bvalid;  wire m0_bready;
  wire [31:0] m0_araddr;  wire [2:0] m0_arprot;  wire m0_arvalid; wire m0_arready;
  wire [31:0] m0_rdata;   wire [1:0] m0_rresp;   wire m0_rvalid;  wire m0_rready;

  wire [31:0] m1_awaddr;  wire [2:0] m1_awprot;  wire m1_awvalid; wire m1_awready;
  wire [31:0] m1_wdata;   wire [3:0] m1_wstrb;   wire m1_wvalid;  wire m1_wready;
  wire [1:0]  m1_bresp;   wire       m1_bvalid;  wire m1_bready;
  wire [31:0] m1_araddr;  wire [2:0] m1_arprot;  wire m1_arvalid; wire m1_arready;
  wire [31:0] m1_rdata;   wire [1:0] m1_rresp;   wire m1_rvalid;  wire m1_rready;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  axi4_lite_interconnect u_dut (
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

  // ---------------------------------------------------------------------------
  // Master BFMs
  // ---------------------------------------------------------------------------
  axi4_lite_master_bfm u_bfm0 (
    .aclk (aclk), .aresetn (aresetn),
    .m_axi_awaddr (s0_awaddr), .m_axi_awprot (s0_awprot),
    .m_axi_awvalid(s0_awvalid), .m_axi_awready(s0_awready),
    .m_axi_wdata  (s0_wdata),  .m_axi_wstrb  (s0_wstrb),
    .m_axi_wvalid (s0_wvalid), .m_axi_wready (s0_wready),
    .m_axi_bresp  (s0_bresp),  .m_axi_bvalid (s0_bvalid),
    .m_axi_bready (s0_bready),
    .m_axi_araddr (s0_araddr), .m_axi_arprot (s0_arprot),
    .m_axi_arvalid(s0_arvalid), .m_axi_arready(s0_arready),
    .m_axi_rdata  (s0_rdata),  .m_axi_rresp  (s0_rresp),
    .m_axi_rvalid (s0_rvalid), .m_axi_rready (s0_rready)
  );

  axi4_lite_master_bfm u_bfm1 (
    .aclk (aclk), .aresetn (aresetn),
    .m_axi_awaddr (s1_awaddr), .m_axi_awprot (s1_awprot),
    .m_axi_awvalid(s1_awvalid), .m_axi_awready(s1_awready),
    .m_axi_wdata  (s1_wdata),  .m_axi_wstrb  (s1_wstrb),
    .m_axi_wvalid (s1_wvalid), .m_axi_wready (s1_wready),
    .m_axi_bresp  (s1_bresp),  .m_axi_bvalid (s1_bvalid),
    .m_axi_bready (s1_bready),
    .m_axi_araddr (s1_araddr), .m_axi_arprot (s1_arprot),
    .m_axi_arvalid(s1_arvalid), .m_axi_arready(s1_arready),
    .m_axi_rdata  (s1_rdata),  .m_axi_rresp  (s1_rresp),
    .m_axi_rvalid (s1_rvalid), .m_axi_rready (s1_rready)
  );

  // ---------------------------------------------------------------------------
  // Real slaves behind the DUT's master ports
  // ---------------------------------------------------------------------------
  axi4_lite_slave #(.NUM_REGS (NUM_REGS)) u_slv0 (
    .aclk (aclk), .aresetn (aresetn),
    .s_axi_awaddr (m0_awaddr), .s_axi_awprot (m0_awprot),
    .s_axi_awvalid(m0_awvalid), .s_axi_awready(m0_awready),
    .s_axi_wdata  (m0_wdata),  .s_axi_wstrb  (m0_wstrb),
    .s_axi_wvalid (m0_wvalid), .s_axi_wready (m0_wready),
    .s_axi_bresp  (m0_bresp),  .s_axi_bvalid (m0_bvalid),
    .s_axi_bready (m0_bready),
    .s_axi_araddr (m0_araddr), .s_axi_arprot (m0_arprot),
    .s_axi_arvalid(m0_arvalid), .s_axi_arready(m0_arready),
    .s_axi_rdata  (m0_rdata),  .s_axi_rresp  (m0_rresp),
    .s_axi_rvalid (m0_rvalid), .s_axi_rready (m0_rready)
  );

  axi4_lite_slave #(.NUM_REGS (NUM_REGS)) u_slv1 (
    .aclk (aclk), .aresetn (aresetn),
    .s_axi_awaddr (m1_awaddr), .s_axi_awprot (m1_awprot),
    .s_axi_awvalid(m1_awvalid), .s_axi_awready(m1_awready),
    .s_axi_wdata  (m1_wdata),  .s_axi_wstrb  (m1_wstrb),
    .s_axi_wvalid (m1_wvalid), .s_axi_wready (m1_wready),
    .s_axi_bresp  (m1_bresp),  .s_axi_bvalid (m1_bvalid),
    .s_axi_bready (m1_bready),
    .s_axi_araddr (m1_araddr), .s_axi_arprot (m1_arprot),
    .s_axi_arvalid(m1_arvalid), .s_axi_arready(m1_arready),
    .s_axi_rdata  (m1_rdata),  .s_axi_rresp  (m1_rresp),
    .s_axi_rvalid (m1_rvalid), .s_axi_rready (m1_rready)
  );

  // ---------------------------------------------------------------------------
  // Passive protocol checkers on all four DUT interfaces
  // ---------------------------------------------------------------------------
  axi4_lite_protocol_checker #(.NAME ("S0PC")) u_pc_s0 (
    .aclk (aclk), .aresetn (aresetn),
    .awaddr(s0_awaddr), .awprot(s0_awprot), .awvalid(s0_awvalid), .awready(s0_awready),
    .wdata (s0_wdata),  .wstrb (s0_wstrb),  .wvalid (s0_wvalid),  .wready (s0_wready),
    .bresp (s0_bresp),  .bvalid(s0_bvalid), .bready (s0_bready),
    .araddr(s0_araddr), .arprot(s0_arprot), .arvalid(s0_arvalid), .arready(s0_arready),
    .rdata (s0_rdata),  .rresp (s0_rresp),  .rvalid (s0_rvalid),  .rready (s0_rready)
  );

  axi4_lite_protocol_checker #(.NAME ("S1PC")) u_pc_s1 (
    .aclk (aclk), .aresetn (aresetn),
    .awaddr(s1_awaddr), .awprot(s1_awprot), .awvalid(s1_awvalid), .awready(s1_awready),
    .wdata (s1_wdata),  .wstrb (s1_wstrb),  .wvalid (s1_wvalid),  .wready (s1_wready),
    .bresp (s1_bresp),  .bvalid(s1_bvalid), .bready (s1_bready),
    .araddr(s1_araddr), .arprot(s1_arprot), .arvalid(s1_arvalid), .arready(s1_arready),
    .rdata (s1_rdata),  .rresp (s1_rresp),  .rvalid (s1_rvalid),  .rready (s1_rready)
  );

  axi4_lite_protocol_checker #(.NAME ("M0PC")) u_pc_m0 (
    .aclk (aclk), .aresetn (aresetn),
    .awaddr(m0_awaddr), .awprot(m0_awprot), .awvalid(m0_awvalid), .awready(m0_awready),
    .wdata (m0_wdata),  .wstrb (m0_wstrb),  .wvalid (m0_wvalid),  .wready (m0_wready),
    .bresp (m0_bresp),  .bvalid(m0_bvalid), .bready (m0_bready),
    .araddr(m0_araddr), .arprot(m0_arprot), .arvalid(m0_arvalid), .arready(m0_arready),
    .rdata (m0_rdata),  .rresp (m0_rresp),  .rvalid (m0_rvalid),  .rready (m0_rready)
  );

  axi4_lite_protocol_checker #(.NAME ("M1PC")) u_pc_m1 (
    .aclk (aclk), .aresetn (aresetn),
    .awaddr(m1_awaddr), .awprot(m1_awprot), .awvalid(m1_awvalid), .awready(m1_awready),
    .wdata (m1_wdata),  .wstrb (m1_wstrb),  .wvalid (m1_wvalid),  .wready (m1_wready),
    .bresp (m1_bresp),  .bvalid(m1_bvalid), .bready (m1_bready),
    .araddr(m1_araddr), .arprot(m1_arprot), .arvalid(m1_arvalid), .arready(m1_arready),
    .rdata (m1_rdata),  .rresp (m1_rresp),  .rvalid (m1_rvalid),  .rready (m1_rready)
  );

  // ---------------------------------------------------------------------------
  // Crossbar concurrency observer.
  // A fully serializing "interconnect" would still pass a naive parallel test,
  // so record whether the two destination ports were ever driven in the same
  // cycle. test_parallel asserts this actually happened.
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
  // Test bookkeeping
  // ---------------------------------------------------------------------------
  reg [255:0] testname;
  integer     seed;
  integer     seed_req;
  integer     dummy;
  integer     sb_errors;      // total, computed in summary
  integer     sb_err0;        // master 0 thread only
  integer     sb_err1;        // master 1 thread only
  integer     bfm_errors;     // lite BFM has no self-checks -> stays 0
  integer     ops0, ops1;     // completed ops per master (fairness evidence)
  integer     i;
  integer     j0, j1;

  // Reference model: 2 slaves x 16 registers, with per-byte written flags.
  // The DUT slaves reset their register files to 0, but the write-before-read
  // discipline of SPEC.md section 10 is still followed for data comparison.
  reg [31:0] model      [0:31];
  reg [3:0]  model_bval [0:31];

  // per-master scratch (never shared between the two forked threads)
  reg [31:0] d0, d1;
  reg [3:0]  st0, st1;
  integer    idx0, idx1, sl0, sl1, sel0, sel1;

  // Address for register `idx` of slave `s` (s = 0 -> 0x0000_0xxx, 1 -> 0x0000_1xxx)
  function [31:0] sa;
    input integer s;
    input integer idx;
    begin
      sa = (s << 12) | (idx << 2);
    end
  endfunction

  // Model index for slave `s`, register `idx`
  function integer mi;
    input integer s;
    input integer idx;
    begin
      mi = s * 16 + idx;
    end
  endfunction

  // Decoded destination of an address: 0 -> S0, 1 -> S1, 2 -> default slave
  function integer dest_of;
    input [31:0] addr;
    begin
      if (addr[31:12] == 20'h00000)      dest_of = 0;
      else if (addr[31:12] == 20'h00001) dest_of = 1;
      else                               dest_of = 2;
    end
  endfunction

  // ---------------------------------------------------------------------------
  // Scoreboarded operations -- one static task pair per master, because the two
  // masters run concurrently under fork/join and static task locals cannot be
  // shared between threads.
  // ---------------------------------------------------------------------------
`define LITE_IC_DO_WRITE(TASKNAME, BFM, ERRC, OPS, RESPV, EXPV, IDXV, DSTV)    \
  task TASKNAME (input [31:0] addr, input [31:0] data, input [3:0] strb);      \
    begin                                                                      \
      DSTV = dest_of(addr);                                                    \
      IDXV = addr[5:2];                                                        \
      EXPV = (DSTV == 2)      ? RESP_DECERR :                                  \
             (IDXV >= NUM_REGS) ? RESP_SLVERR : RESP_OKAY;                     \
      BFM.axi_write(addr, data, strb, RESPV);                                  \
      if (RESPV !== EXPV) begin                                                \
        ERRC = ERRC + 1;                                                       \
        $display("[TB] %0t SB: BRESP mismatch addr=0x%08h exp=%b got=%b",      \
                 $time, addr, EXPV, RESPV);                                    \
      end                                                                      \
      if (EXPV == RESP_OKAY) begin                                             \
        if (strb[0]) begin model[mi(DSTV,IDXV)][7:0]   = data[7:0];            \
                           model_bval[mi(DSTV,IDXV)][0] = 1'b1; end            \
        if (strb[1]) begin model[mi(DSTV,IDXV)][15:8]  = data[15:8];           \
                           model_bval[mi(DSTV,IDXV)][1] = 1'b1; end            \
        if (strb[2]) begin model[mi(DSTV,IDXV)][23:16] = data[23:16];          \
                           model_bval[mi(DSTV,IDXV)][2] = 1'b1; end            \
        if (strb[3]) begin model[mi(DSTV,IDXV)][31:24] = data[31:24];          \
                           model_bval[mi(DSTV,IDXV)][3] = 1'b1; end            \
      end                                                                      \
      OPS = OPS + 1;                                                           \
    end                                                                        \
  endtask

`define LITE_IC_DO_READ(TASKNAME, BFM, ERRC, OPS, DATAV, RESPV, EXPV, IDXV, DSTV) \
  task TASKNAME (input [31:0] addr);                                           \
    begin                                                                      \
      DSTV = dest_of(addr);                                                    \
      IDXV = addr[5:2];                                                        \
      EXPV = (DSTV == 2)      ? RESP_DECERR :                                  \
             (IDXV >= NUM_REGS) ? RESP_SLVERR : RESP_OKAY;                     \
      BFM.axi_read(addr, DATAV, RESPV);                                        \
      if (RESPV !== EXPV) begin                                                \
        ERRC = ERRC + 1;                                                       \
        $display("[TB] %0t SB: RRESP mismatch addr=0x%08h exp=%b got=%b",      \
                 $time, addr, EXPV, RESPV);                                    \
      end                                                                      \
      if (DSTV == 2) begin                                                     \
        if (DATAV !== DEF_RDATA) begin                                         \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: DECERR rdata addr=0x%08h exp=0x%08h got=0x%08h", \
                   $time, addr, DEF_RDATA, DATAV);                             \
        end                                                                    \
      end else if (IDXV >= NUM_REGS) begin                                     \
        if (DATAV !== 32'h0000_0000) begin                                     \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: invalid-index rdata addr=0x%08h got=0x%08h",  \
                   $time, addr, DATAV);                                        \
        end                                                                    \
      end else begin                                                           \
        if (model_bval[mi(DSTV,IDXV)][0] &&                                    \
            (DATAV[7:0] !== model[mi(DSTV,IDXV)][7:0])) begin                  \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: rdata lane0 addr=0x%08h exp=0x%02h got=0x%02h", \
                   $time, addr, model[mi(DSTV,IDXV)][7:0], DATAV[7:0]);        \
        end                                                                    \
        if (model_bval[mi(DSTV,IDXV)][1] &&                                    \
            (DATAV[15:8] !== model[mi(DSTV,IDXV)][15:8])) begin                \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: rdata lane1 addr=0x%08h exp=0x%02h got=0x%02h", \
                   $time, addr, model[mi(DSTV,IDXV)][15:8], DATAV[15:8]);      \
        end                                                                    \
        if (model_bval[mi(DSTV,IDXV)][2] &&                                    \
            (DATAV[23:16] !== model[mi(DSTV,IDXV)][23:16])) begin              \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: rdata lane2 addr=0x%08h exp=0x%02h got=0x%02h", \
                   $time, addr, model[mi(DSTV,IDXV)][23:16], DATAV[23:16]);    \
        end                                                                    \
        if (model_bval[mi(DSTV,IDXV)][3] &&                                    \
            (DATAV[31:24] !== model[mi(DSTV,IDXV)][31:24])) begin              \
          ERRC = ERRC + 1;                                                     \
          $display("[TB] %0t SB: rdata lane3 addr=0x%08h exp=0x%02h got=0x%02h", \
                   $time, addr, model[mi(DSTV,IDXV)][31:24], DATAV[31:24]);    \
        end                                                                    \
      end                                                                      \
      OPS = OPS + 1;                                                           \
    end                                                                        \
  endtask

  // per-task response/scratch storage (one set per master, never shared)
  reg [1:0]  rsp0, exp0;
  reg [1:0]  rsp1, exp1;
  reg [31:0] rd0, rd1;

  `LITE_IC_DO_WRITE(do_write_m0, u_bfm0, sb_err0, ops0, rsp0, exp0, idx0, sl0)
  `LITE_IC_DO_READ (do_read_m0,  u_bfm0, sb_err0, ops0, rd0, rsp0, exp0, idx0, sl0)
  `LITE_IC_DO_WRITE(do_write_m1, u_bfm1, sb_err1, ops1, rsp1, exp1, idx1, sl1)
  `LITE_IC_DO_READ (do_read_m1,  u_bfm1, sb_err1, ops1, rd1, rsp1, exp1, idx1, sl1)

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  // targeted: each master writes and reads back each slave (F06, F08)
  task test_targeted;
    begin
      // master 0 -> slave 0, then slave 1 (its own register range 0..5)
      for (i = 0; i < 6; i = i + 1) begin
        do_write_m0(sa(0, i), 32'hA000_0000 | i, 4'hF);
        do_read_m0 (sa(0, i));
      end
      for (i = 0; i < 6; i = i + 1) begin
        do_write_m0(sa(1, i), 32'hB000_0000 | i, 4'hF);
        do_read_m0 (sa(1, i));
      end
      // master 1 -> slave 0, then slave 1 (its own register range 6..11)
      for (i = 6; i < 12; i = i + 1) begin
        do_write_m1(sa(0, i), 32'hC000_0000 | i, 4'hF);
        do_read_m1 (sa(0, i));
      end
      for (i = 6; i < 12; i = i + 1) begin
        do_write_m1(sa(1, i), 32'hD000_0000 | i, 4'hF);
        do_read_m1 (sa(1, i));
      end
      // cross-check: master 0 reads back what it wrote to slave 1 and vice versa
      for (i = 0; i < 6; i = i + 1)
        do_read_m0(sa(1, i));
      for (i = 6; i < 12; i = i + 1)
        do_read_m1(sa(0, i));
      // an aliased address still lands on the same register (addr[11:6] ignored)
      do_write_m0(sa(0, 2), 32'h5EED_0002, 4'hF);
      do_read_m0 (32'h0000_0048);   // 0x48[5:2] = 2 -> same register
    end
  endtask

  // decerr: unmapped addresses from both masters -> DECERR, rdata 0xDEC0DE00
  task test_decerr;
    begin
      do_write_m0(32'h0000_2000, 32'hDEAD_0000, 4'hF);
      do_read_m0 (32'h0000_2000);
      do_write_m0(32'h8000_0000, 32'hDEAD_0001, 4'hF);
      do_read_m0 (32'h8000_0000);
      do_write_m1(32'h0000_2000, 32'hDEAD_0002, 4'hF);
      do_read_m1 (32'h0000_2000);
      do_write_m1(32'h8000_0000, 32'hDEAD_0003, 4'hF);
      do_read_m1 (32'h8000_0000);
      // a DECERR transaction must not disturb normal traffic afterwards
      do_write_m0(sa(0, 0), 32'h600D_0000, 4'hF);
      do_read_m0 (sa(0, 0));
      do_write_m1(sa(1, 7), 32'h600D_0007, 4'hF);
      do_read_m1 (sa(1, 7));
      // mixed: DECERR from one master while the other uses a real slave
      fork
        begin
          for (j0 = 0; j0 < 10; j0 = j0 + 1) begin
            do_write_m0(32'h0000_3000, 32'hBAD0_0000 | j0, 4'hF);
            do_read_m0 (32'h0000_3000);
          end
        end
        begin
          for (j1 = 0; j1 < 10; j1 = j1 + 1) begin
            do_write_m1(sa(0, 8), 32'h700D_0000 | j1, 4'hF);
            do_read_m1 (sa(0, 8));
          end
        end
      join
    end
  endtask

  // contention: both masters hammer the SAME slave, disjoint register sets.
  // Completing at all (no watchdog) plus ops0 == ops1 == 100 is the fairness
  // evidence required by F21 -- a starving arbiter would hang the run.
  task test_contention;
    begin
      fork
        begin
          for (j0 = 0; j0 < 25; j0 = j0 + 1) begin
            do_write_m0(sa(0, j0 % 6), 32'h1000_0000 | j0, 4'hF);
            do_read_m0 (sa(0, j0 % 6));
          end
        end
        begin
          for (j1 = 0; j1 < 25; j1 = j1 + 1) begin
            do_write_m1(sa(0, 6 + (j1 % 6)), 32'h2000_0000 | j1, 4'hF);
            do_read_m1 (sa(0, 6 + (j1 % 6)));
          end
        end
      join
      if (ops0 != 50 || ops1 != 50) begin
        sb_err0 = sb_err0 + 1;
        $display("[TB] %0t SB: contention starvation ops0=%0d ops1=%0d",
                 $time, ops0, ops1);
      end
    end
  endtask

  // parallel: M0->S0 concurrently with M1->S1, then the crossed pairing.
  task test_parallel;
    begin
      fork
        begin
          for (j0 = 0; j0 < 25; j0 = j0 + 1) begin
            do_write_m0(sa(0, j0 % 6), 32'h3000_0000 | j0, 4'hF);
            do_read_m0 (sa(0, j0 % 6));
          end
        end
        begin
          for (j1 = 0; j1 < 25; j1 = j1 + 1) begin
            do_write_m1(sa(1, 6 + (j1 % 6)), 32'h4000_0000 | j1, 4'hF);
            do_read_m1 (sa(1, 6 + (j1 % 6)));
          end
        end
      join
      // swapped pairing: M0->S1 while M1->S0
      fork
        begin
          for (j0 = 0; j0 < 25; j0 = j0 + 1) begin
            do_write_m0(sa(1, j0 % 6), 32'h5000_0000 | j0, 4'hF);
            do_read_m0 (sa(1, j0 % 6));
          end
        end
        begin
          for (j1 = 0; j1 < 25; j1 = j1 + 1) begin
            do_write_m1(sa(0, 6 + (j1 % 6)), 32'h6000_0000 | j1, 4'hF);
            do_read_m1 (sa(0, 6 + (j1 % 6)));
          end
        end
      join
      // F22: distinct crossbar paths must actually have been active together
      if (!concurrent_seen) begin
        sb_err0 = sb_err0 + 1;
        $display("[TB] %0t SB: no cycle with both destination ports active -- %0s",
                 $time, "crossbar is serializing");
      end
    end
  endtask

  // random: both masters, 100 ops each over the full map, model-checked.
  // Each master keeps to its own register range and its own invalid indices,
  // so the model is race-free despite the two threads running concurrently.
  task test_random_m0;
    begin
      for (j0 = 0; j0 < 100; j0 = j0 + 1) begin
        sel0 = $urandom_range(0, 9);
        sl0  = $urandom_range(0, 1);
        if (sel0 < 4) begin
          idx0 = $urandom_range(0, 5);
          d0   = $urandom;
          st0  = $urandom_range(0, 15);
          do_write_m0(sa(sl0, idx0), d0, st0);
        end else if (sel0 < 8) begin
          idx0 = $urandom_range(0, 5);
          do_read_m0(sa(sl0, idx0));
        end else if (sel0 == 8) begin
          idx0 = 12 + $urandom_range(0, 1);          // invalid index -> SLVERR
          if ($urandom_range(0, 1) == 0)
            do_write_m0(sa(sl0, idx0), $urandom, 4'hF);
          else
            do_read_m0(sa(sl0, idx0));
        end else begin
          if ($urandom_range(0, 1) == 0)             // unmapped -> DECERR
            do_write_m0(32'h0000_2000, $urandom, 4'hF);
          else
            do_read_m0(32'h8000_0000);
        end
      end
    end
  endtask

  task test_random_m1;
    begin
      for (j1 = 0; j1 < 100; j1 = j1 + 1) begin
        sel1 = $urandom_range(0, 9);
        sl1  = $urandom_range(0, 1);
        if (sel1 < 4) begin
          idx1 = 6 + $urandom_range(0, 5);
          d1   = $urandom;
          st1  = $urandom_range(0, 15);
          do_write_m1(sa(sl1, idx1), d1, st1);
        end else if (sel1 < 8) begin
          idx1 = 6 + $urandom_range(0, 5);
          do_read_m1(sa(sl1, idx1));
        end else if (sel1 == 8) begin
          idx1 = 14 + $urandom_range(0, 1);          // invalid index -> SLVERR
          if ($urandom_range(0, 1) == 0)
            do_write_m1(sa(sl1, idx1), $urandom, 4'hF);
          else
            do_read_m1(sa(sl1, idx1));
        end else begin
          if ($urandom_range(0, 1) == 0)             // unmapped -> DECERR
            do_write_m1(32'h0000_4000, $urandom, 4'hF);
          else
            do_read_m1(32'hFFFF_0000);
        end
      end
    end
  endtask

  task test_random;
    begin
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
               bfm_errors);
    end
  endtask

  task summary;
    begin
      sb_errors = sb_err0 + sb_err1;
      if ((sb_errors == 0) && (bfm_errors == 0) &&
          (u_pc_s0.error_count == 0) && (u_pc_s1.error_count == 0) &&
          (u_pc_m0.error_count == 0) && (u_pc_m1.error_count == 0))
        $display("=== TEST PASSED: %0s ===", testname);
      else
        print_summary_fail;
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
      $dumpfile("tb_axi4_lite_interconnect.vcd");
      $dumpvars(0, tb_axi4_lite_interconnect);
    end

    sb_err0    = 0;
    sb_err1    = 0;
    sb_errors  = 0;
    bfm_errors = 0;
    ops0       = 0;
    ops1       = 0;
    for (i = 0; i < 32; i = i + 1) begin
      model[i]      = 32'h0000_0000;
      model_bval[i] = 4'h0;
    end

    @(posedge aresetn);
    repeat (2) @(posedge aclk);
    $display("[TB] %0t running TEST=%0s SEED=%0d", $time, testname, seed_req);

    if      (testname == "targeted")   test_targeted;
    else if (testname == "decerr")     test_decerr;
    else if (testname == "contention") test_contention;
    else if (testname == "parallel")   test_parallel;
    else if (testname == "random")     test_random;
    else begin
      $display("[TB] %0t unknown TEST=%0s", $time, testname);
      sb_err0 = sb_err0 + 1;
    end

    repeat (5) @(posedge aclk);
    summary;
  end

endmodule
