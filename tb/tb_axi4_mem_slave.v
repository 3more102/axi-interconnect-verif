// -----------------------------------------------------------------------------
// tb_axi4_mem_slave.v
// Self-checking testbench for axi4_mem_slave (SPEC.md sections 4, 10).
//
// Topology: one axi4_master_bfm (ID_WIDTH=4) -> DUT axi4_mem_slave
//           (ID_WIDTH=4, MEM_BYTES=3072), with a passive axi4_protocol_checker
//           and an axi4_coverage collector on the same interface.
//
// Tests (+TEST=): smoke | incr | wrap | fixed | narrow | errors | boundary | random
// Options       : +SEED=<n> (default 1), +DUMP (VCD waves)
//
// The reference model mirrors the DUT's 4 KB window as 1024 words plus a
// per-byte "has been written" mask. Read data is only compared on bytes the
// test has actually written (write-before-read discipline, SPEC.md section 10);
// responses are always compared, on every beat.
//
// Beat addresses are recomputed here independently of the BFM, from the burst
// rules in SPEC.md section 4, so a shared bug in the BFM's address stepping
// cannot hide itself.
//
// Language subset (SPEC.md section 0): Verilog-2001 plus only
// $urandom / $urandom_range / $value$plusargs / $test$plusargs.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_axi4_mem_slave;

  localparam ID_WIDTH    = 4;
  localparam MEM_BYTES   = 3072;     // offsets 0..0xBFF are OKAY, 0xC00.. SLVERR
  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;

  localparam BT_FIXED = 2'b00;
  localparam BT_INCR  = 2'b01;
  localparam BT_WRAP  = 2'b10;

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
  // AXI4 interface (BFM master <-> DUT slave, observed by checker + coverage)
  // ---------------------------------------------------------------------------
  wire [ID_WIDTH-1:0] awid;
  wire [31:0]         awaddr;
  wire [7:0]          awlen;
  wire [2:0]          awsize;
  wire [1:0]          awburst;
  wire [2:0]          awprot;
  wire                awvalid, awready;
  wire [31:0]         wdata;
  wire [3:0]          wstrb;
  wire                wlast, wvalid, wready;
  wire [ID_WIDTH-1:0] bid;
  wire [1:0]          bresp;
  wire                bvalid, bready;
  wire [ID_WIDTH-1:0] arid;
  wire [31:0]         araddr;
  wire [7:0]          arlen;
  wire [2:0]          arsize;
  wire [1:0]          arburst;
  wire [2:0]          arprot;
  wire                arvalid, arready;
  wire [ID_WIDTH-1:0] rid;
  wire [31:0]         rdata;
  wire [1:0]          rresp;
  wire                rlast, rvalid, rready;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  axi4_mem_slave #(
    .ID_WIDTH  (ID_WIDTH),
    .MEM_BYTES (MEM_BYTES)
  ) u_dut (
    .aclk (aclk), .aresetn (aresetn),
    .s_axi_awid (awid), .s_axi_awaddr (awaddr), .s_axi_awlen (awlen),
    .s_axi_awsize (awsize), .s_axi_awburst (awburst), .s_axi_awprot (awprot),
    .s_axi_awvalid (awvalid), .s_axi_awready (awready),
    .s_axi_wdata (wdata), .s_axi_wstrb (wstrb), .s_axi_wlast (wlast),
    .s_axi_wvalid (wvalid), .s_axi_wready (wready),
    .s_axi_bid (bid), .s_axi_bresp (bresp),
    .s_axi_bvalid (bvalid), .s_axi_bready (bready),
    .s_axi_arid (arid), .s_axi_araddr (araddr), .s_axi_arlen (arlen),
    .s_axi_arsize (arsize), .s_axi_arburst (arburst), .s_axi_arprot (arprot),
    .s_axi_arvalid (arvalid), .s_axi_arready (arready),
    .s_axi_rid (rid), .s_axi_rdata (rdata), .s_axi_rresp (rresp),
    .s_axi_rlast (rlast), .s_axi_rvalid (rvalid), .s_axi_rready (rready)
  );

  // ---------------------------------------------------------------------------
  // Master BFM
  // ---------------------------------------------------------------------------
  axi4_master_bfm #(.ID_WIDTH (ID_WIDTH)) u_bfm (
    .aclk (aclk), .aresetn (aresetn),
    .m_axi_awid (awid), .m_axi_awaddr (awaddr), .m_axi_awlen (awlen),
    .m_axi_awsize (awsize), .m_axi_awburst (awburst), .m_axi_awprot (awprot),
    .m_axi_awvalid (awvalid), .m_axi_awready (awready),
    .m_axi_wdata (wdata), .m_axi_wstrb (wstrb), .m_axi_wlast (wlast),
    .m_axi_wvalid (wvalid), .m_axi_wready (wready),
    .m_axi_bid (bid), .m_axi_bresp (bresp),
    .m_axi_bvalid (bvalid), .m_axi_bready (bready),
    .m_axi_arid (arid), .m_axi_araddr (araddr), .m_axi_arlen (arlen),
    .m_axi_arsize (arsize), .m_axi_arburst (arburst), .m_axi_arprot (arprot),
    .m_axi_arvalid (arvalid), .m_axi_arready (arready),
    .m_axi_rid (rid), .m_axi_rdata (rdata), .m_axi_rresp (rresp),
    .m_axi_rlast (rlast), .m_axi_rvalid (rvalid), .m_axi_rready (rready)
  );

  // ---------------------------------------------------------------------------
  // Passive protocol checker + functional coverage
  // ---------------------------------------------------------------------------
  axi4_protocol_checker #(.ID_WIDTH (ID_WIDTH), .NAME ("MSPC")) u_pc (
    .aclk (aclk), .aresetn (aresetn),
    .awid (awid), .awaddr (awaddr), .awlen (awlen), .awsize (awsize),
    .awburst (awburst), .awprot (awprot), .awvalid (awvalid), .awready (awready),
    .wdata (wdata), .wstrb (wstrb), .wlast (wlast),
    .wvalid (wvalid), .wready (wready),
    .bid (bid), .bresp (bresp), .bvalid (bvalid), .bready (bready),
    .arid (arid), .araddr (araddr), .arlen (arlen), .arsize (arsize),
    .arburst (arburst), .arprot (arprot), .arvalid (arvalid), .arready (arready),
    .rid (rid), .rdata (rdata), .rresp (rresp), .rlast (rlast),
    .rvalid (rvalid), .rready (rready)
  );

  axi4_coverage #(.ID_WIDTH (ID_WIDTH), .NAME ("MSCV")) u_cov (
    .aclk (aclk), .aresetn (aresetn),
    .awid (awid), .awaddr (awaddr), .awlen (awlen), .awsize (awsize),
    .awburst (awburst), .awprot (awprot), .awvalid (awvalid), .awready (awready),
    .wdata (wdata), .wstrb (wstrb), .wlast (wlast),
    .wvalid (wvalid), .wready (wready),
    .bid (bid), .bresp (bresp), .bvalid (bvalid), .bready (bready),
    .arid (arid), .araddr (araddr), .arlen (arlen), .arsize (arsize),
    .arburst (arburst), .arprot (arprot), .arvalid (arvalid), .arready (arready),
    .rid (rid), .rdata (rdata), .rresp (rresp), .rlast (rlast),
    .rvalid (rvalid), .rready (rready)
  );

  // ---------------------------------------------------------------------------
  // Test bookkeeping and reference model
  // ---------------------------------------------------------------------------
  reg [255:0] testname;
  integer     seed;
  integer     seed_req;
  integer     dummy;
  integer     sb_errors;
  integer     i;
  integer     n;

  reg [31:0] model    [0:1023];   // mirror of the DUT's 4 KB window
  reg [3:0]  mem_bval [0:1023];   // per-byte "has been written" mask

  // scratch for the random test
  integer r_burst, r_size, r_len, r_total, r_base, r_addr, r_slots;
  reg [3:0] r_id;

  // ---------------------------------------------------------------------------
  // Helper functions
  // ---------------------------------------------------------------------------

  // Address of beat `i`, recomputed from SPEC.md section 4 burst rules.
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
        if (burst != BT_FIXED) begin          // INCR / WRAP (2'b11 as INCR)
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

  // ---------------------------------------------------------------------------
  // Scoreboarded burst operations
  // ---------------------------------------------------------------------------

  // Write a burst of random payload and check BRESP; then fold the in-range
  // beats into the model, in beat order (so a FIXED burst correctly leaves the
  // final beat's value behind).
  task wr_burst;
    input [ID_WIDTH-1:0] id;
    input [31:0]         addr;
    input [7:0]          len;
    input [2:0]          size;
    input [1:0]          burst;
    integer    bi, b, nbytes, lane, widx, off;
    reg [1:0]  resp, exp_resp;
    reg [31:0] A, tmp, byteval;
    begin
      nbytes   = 1 << size;
      exp_resp = RESP_OKAY;

      for (bi = 0; bi <= len; bi = bi + 1)
        u_bfm.wbuf[bi] = $urandom & size_mask(size);

      // predicted BRESP: SLVERR if ANY beat lands outside the valid range
      for (bi = 0; bi <= len; bi = bi + 1) begin
        A   = beat_addr_of(addr, len, size, burst, bi);
        off = A % 4096;
        if (off >= MEM_BYTES)
          exp_resp = RESP_SLVERR;
      end

      u_bfm.axi_write_burst(id, addr, len, size, burst, resp);

      if (resp !== exp_resp) begin
        sb_errors = sb_errors + 1;
        $display("[TB] %0t SB: BRESP addr=0x%03h len=%0d size=%0d burst=%b exp=%b got=%b",
                 $time, addr % 4096, len, size, burst, exp_resp, resp);
      end

      // model update -- in-range beats only, out-of-range beats are discarded
      for (bi = 0; bi <= len; bi = bi + 1) begin
        A    = beat_addr_of(addr, len, size, burst, bi);
        off  = A % 4096;
        lane = A % 4;
        widx = off >> 2;
        if (off < MEM_BYTES) begin
          tmp = model[widx];
          for (b = 0; b < nbytes; b = b + 1) begin
            byteval = (u_bfm.wbuf[bi] >> (8 * b)) & 32'h0000_00FF;
            tmp     = tmp & ~(32'h0000_00FF << (8 * (lane + b)));
            tmp     = tmp | (byteval << (8 * (lane + b)));
            mem_bval[widx] = mem_bval[widx] | (4'd1 << (lane + b));
          end
          model[widx] = tmp;
        end
      end
    end
  endtask

  // Read a burst and check every beat's RRESP, plus the data on byte lanes the
  // test has already written. Out-of-range beats must return SLVERR and zero.
  task rd_burst;
    input [ID_WIDTH-1:0] id;
    input [31:0]         addr;
    input [7:0]          len;
    input [2:0]          size;
    input [1:0]          burst;
    integer    bi, b, nbytes, lane, widx, off;
    reg [1:0]  resp, exp_worst, exp_beat;
    reg [31:0] A, exp_data;
    reg        all_valid;
    begin
      nbytes    = 1 << size;
      exp_worst = RESP_OKAY;

      u_bfm.axi_read_burst(id, addr, len, size, burst, resp);

      for (bi = 0; bi <= len; bi = bi + 1) begin
        A    = beat_addr_of(addr, len, size, burst, bi);
        off  = A % 4096;
        lane = A % 4;
        widx = off >> 2;

        if (off >= MEM_BYTES) begin
          exp_beat  = RESP_SLVERR;
          exp_data  = 32'h0000_0000;   // out-of-range beats read back as zero
          all_valid = 1'b1;
        end else begin
          exp_beat  = RESP_OKAY;
          exp_data  = 32'h0000_0000;
          all_valid = 1'b1;
          for (b = 0; b < nbytes; b = b + 1) begin
            if (!mem_bval[widx][lane + b])
              all_valid = 1'b0;
            exp_data = exp_data |
                       (((model[widx] >> (8 * (lane + b))) & 32'h0000_00FF)
                        << (8 * b));
          end
        end

        if (exp_beat > exp_worst)
          exp_worst = exp_beat;

        if (u_bfm.rresp_buf[bi] !== exp_beat) begin
          sb_errors = sb_errors + 1;
          $display("[TB] %0t SB: RRESP beat %0d addr=0x%03h exp=%b got=%b",
                   $time, bi, off, exp_beat, u_bfm.rresp_buf[bi]);
        end
        if (all_valid && (u_bfm.rbuf[bi] !== exp_data)) begin
          sb_errors = sb_errors + 1;
          $display("[TB] %0t SB: RDATA beat %0d addr=0x%03h size=%0d exp=0x%08h got=0x%08h",
                   $time, bi, off, size, exp_data, u_bfm.rbuf[bi]);
        end
      end

      if (resp !== exp_worst) begin
        sb_errors = sb_errors + 1;
        $display("[TB] %0t SB: worst RRESP addr=0x%03h exp=%b got=%b",
                 $time, addr % 4096, exp_worst, resp);
      end
    end
  endtask

  // Write-before-read has to hold at WORD granularity, not byte granularity:
  // the slave returns the whole addressed word on RDATA (SPEC.md section 4) and
  // its memory is not initialized (SPEC.md section 10), so reading a word whose
  // other byte lanes were never written puts X on RDATA and PC07 fires --
  // correctly. Tests that read words they only partially wrote fill the window
  // first. Doing so also strengthens them: every byte then has a known value, so
  // a narrow write that corrupts a neighbouring lane is caught instead of being
  // skipped as "not yet written".
  task prefill_window;
    begin
      wr_burst(4'h0, 32'h0000_0000, 8'd255, 3'd2, BT_INCR);   // 0x000..0x3FF
      wr_burst(4'h0, 32'h0000_0400, 8'd255, 3'd2, BT_INCR);   // 0x400..0x7FF
      wr_burst(4'h0, 32'h0000_0800, 8'd255, 3'd2, BT_INCR);   // 0x800..0xBFF
    end
  endtask

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  // smoke: single-beat (len=0, size=2) writes and readbacks
  task test_smoke;
    begin
      wr_burst(4'h1, 32'h0000_0000, 8'd0, 3'd2, BT_INCR);
      rd_burst(4'h1, 32'h0000_0000, 8'd0, 3'd2, BT_INCR);
      wr_burst(4'h2, 32'h0000_0004, 8'd0, 3'd2, BT_INCR);
      rd_burst(4'h2, 32'h0000_0004, 8'd0, 3'd2, BT_INCR);
      wr_burst(4'h3, 32'h0000_0100, 8'd0, 3'd2, BT_INCR);
      rd_burst(4'h3, 32'h0000_0100, 8'd0, 3'd2, BT_INCR);
      wr_burst(4'h4, 32'h0000_0BFC, 8'd0, 3'd2, BT_INCR);   // last OKAY word
      rd_burst(4'h4, 32'h0000_0BFC, 8'd0, 3'd2, BT_INCR);
      // overwrite and re-read
      wr_burst(4'h5, 32'h0000_0000, 8'd0, 3'd2, BT_INCR);
      rd_burst(4'h5, 32'h0000_0000, 8'd0, 3'd2, BT_INCR);
    end
  endtask

  // incr: INCR bursts of every length class, write -> readback -> compare
  task test_incr;
    begin
      wr_burst(4'h0, 32'h0000_0100, 8'd0,   3'd2, BT_INCR);
      rd_burst(4'h0, 32'h0000_0100, 8'd0,   3'd2, BT_INCR);
      wr_burst(4'h1, 32'h0000_0200, 8'd1,   3'd2, BT_INCR);
      rd_burst(4'h1, 32'h0000_0200, 8'd1,   3'd2, BT_INCR);
      wr_burst(4'h2, 32'h0000_0300, 8'd3,   3'd2, BT_INCR);
      rd_burst(4'h2, 32'h0000_0300, 8'd3,   3'd2, BT_INCR);
      wr_burst(4'h3, 32'h0000_0400, 8'd7,   3'd2, BT_INCR);
      rd_burst(4'h3, 32'h0000_0400, 8'd7,   3'd2, BT_INCR);
      wr_burst(4'h4, 32'h0000_0500, 8'd15,  3'd2, BT_INCR);
      rd_burst(4'h4, 32'h0000_0500, 8'd15,  3'd2, BT_INCR);
      wr_burst(4'h5, 32'h0000_0600, 8'd31,  3'd2, BT_INCR);
      rd_burst(4'h5, 32'h0000_0600, 8'd31,  3'd2, BT_INCR);
      // len=255 : 1024 bytes, 0x800..0xBFF -- entirely inside the OKAY region
      wr_burst(4'h6, 32'h0000_0800, 8'd255, 3'd2, BT_INCR);
      rd_burst(4'h6, 32'h0000_0800, 8'd255, 3'd2, BT_INCR);
      // reading back a subrange must agree with the model too
      rd_burst(4'h7, 32'h0000_0900, 8'd7,   3'd2, BT_INCR);
    end
  endtask

  // wrap: WRAP len in {1,3,7,15}, size=2, aligned starts. Each burst is read
  // back both as WRAP (same beat order) and as a plain INCR sweep of the wrap
  // region, which is what actually pins down where the data landed.
  task test_wrap;
    begin
      wr_burst(4'h1, 32'h0000_0104, 8'd1,  3'd2, BT_WRAP);  // region 0x100..0x107
      rd_burst(4'h1, 32'h0000_0104, 8'd1,  3'd2, BT_WRAP);
      rd_burst(4'h1, 32'h0000_0100, 8'd1,  3'd2, BT_INCR);

      wr_burst(4'h2, 32'h0000_0208, 8'd3,  3'd2, BT_WRAP);  // region 0x200..0x20F
      rd_burst(4'h2, 32'h0000_0208, 8'd3,  3'd2, BT_WRAP);
      rd_burst(4'h2, 32'h0000_0200, 8'd3,  3'd2, BT_INCR);

      wr_burst(4'h3, 32'h0000_030C, 8'd7,  3'd2, BT_WRAP);  // region 0x300..0x31F
      rd_burst(4'h3, 32'h0000_030C, 8'd7,  3'd2, BT_WRAP);
      rd_burst(4'h3, 32'h0000_0300, 8'd7,  3'd2, BT_INCR);

      wr_burst(4'h4, 32'h0000_0424, 8'd15, 3'd2, BT_WRAP);  // region 0x400..0x43F
      rd_burst(4'h4, 32'h0000_0424, 8'd15, 3'd2, BT_WRAP);
      rd_burst(4'h4, 32'h0000_0400, 8'd15, 3'd2, BT_INCR);

      // a WRAP burst that starts exactly on its wrap boundary never wraps
      wr_burst(4'h5, 32'h0000_0500, 8'd3,  3'd2, BT_WRAP);
      rd_burst(4'h5, 32'h0000_0500, 8'd3,  3'd2, BT_INCR);
    end
  endtask

  // fixed: FIXED bursts hit one address every beat; the final beat persists
  task test_fixed;
    begin
      wr_burst(4'h1, 32'h0000_0700, 8'd0, 3'd2, BT_FIXED);
      rd_burst(4'h1, 32'h0000_0700, 8'd0, 3'd2, BT_FIXED);
      // 4 beats to the same word: only the last one survives
      wr_burst(4'h2, 32'h0000_0704, 8'd3, 3'd2, BT_FIXED);
      rd_burst(4'h2, 32'h0000_0704, 8'd3, 3'd2, BT_FIXED);
      // and an INCR single-beat read sees that same final value
      rd_burst(4'h3, 32'h0000_0704, 8'd0, 3'd2, BT_INCR);
      // the neighbouring words must be untouched by a FIXED burst
      wr_burst(4'h4, 32'h0000_0708, 8'd0, 3'd2, BT_INCR);
      wr_burst(4'h5, 32'h0000_0704, 8'd3, 3'd2, BT_FIXED);
      rd_burst(4'h6, 32'h0000_0708, 8'd0, 3'd2, BT_INCR);
    end
  endtask

  // narrow: size 0/1 INCR bursts starting off the 32-bit word boundary
  task test_narrow;
    begin
      prefill_window;
      // byte transfers walking across a word boundary
      wr_burst(4'h1, 32'h0000_0141, 8'd5, 3'd0, BT_INCR);   // 0x141..0x146
      rd_burst(4'h1, 32'h0000_0141, 8'd5, 3'd0, BT_INCR);
      // half-word transfers starting at the upper half of a word
      wr_burst(4'h2, 32'h0000_0152, 8'd5, 3'd1, BT_INCR);   // 0x152..0x15C
      rd_burst(4'h2, 32'h0000_0152, 8'd5, 3'd1, BT_INCR);
      // whole-word reads must see the bytes exactly where the narrow writes put
      // them -- this is the check that actually pins down lane handling
      wr_burst(4'h3, 32'h0000_0160, 8'd3, 3'd0, BT_INCR);   // 4 bytes = 1 word
      rd_burst(4'h3, 32'h0000_0160, 8'd0, 3'd2, BT_INCR);
      wr_burst(4'h4, 32'h0000_0170, 8'd1, 3'd1, BT_INCR);   // 2 halves = 1 word
      rd_burst(4'h4, 32'h0000_0170, 8'd0, 3'd2, BT_INCR);
      // single narrow beats at each lane
      wr_burst(4'h5, 32'h0000_0181, 8'd0, 3'd0, BT_INCR);
      rd_burst(4'h5, 32'h0000_0181, 8'd0, 3'd0, BT_INCR);
      wr_burst(4'h6, 32'h0000_0183, 8'd0, 3'd0, BT_INCR);
      rd_burst(4'h6, 32'h0000_0183, 8'd0, 3'd0, BT_INCR);
      wr_burst(4'h7, 32'h0000_0186, 8'd0, 3'd1, BT_INCR);
      rd_burst(4'h7, 32'h0000_0186, 8'd0, 3'd1, BT_INCR);
    end
  endtask

  // errors: out-of-range bursts, and the partial-burst semantics of a straddle
  task test_errors;
    begin
      // entirely above MEM_BYTES -> SLVERR on write and on every read beat
      wr_burst(4'h1, 32'h0000_0C00, 8'd3, 3'd2, BT_INCR);
      rd_burst(4'h1, 32'h0000_0C00, 8'd3, 3'd2, BT_INCR);
      wr_burst(4'h2, 32'h0000_0F00, 8'd0, 3'd2, BT_INCR);
      rd_burst(4'h2, 32'h0000_0F00, 8'd0, 3'd2, BT_INCR);

      // establish a known value in the last in-range word
      wr_burst(4'h3, 32'h0000_0BFC, 8'd0, 3'd2, BT_INCR);
      rd_burst(4'h3, 32'h0000_0BFC, 8'd0, 3'd2, BT_INCR);

      // straddle 0xBFC -> 0xC04 : BRESP is SLVERR, but the in-range beat at
      // 0xBFC must still have been written (partial-burst semantics, F13)
      wr_burst(4'h4, 32'h0000_0BFC, 8'd2, 3'd2, BT_INCR);
      rd_burst(4'h4, 32'h0000_0BFC, 8'd0, 3'd2, BT_INCR);   // in-range readback
      // the straddling read returns a per-beat mix of OKAY and SLVERR
      rd_burst(4'h5, 32'h0000_0BFC, 8'd2, 3'd2, BT_INCR);

      // a narrow straddle behaves the same way
      wr_burst(4'h6, 32'h0000_0BFE, 8'd3, 3'd1, BT_INCR);   // 0xBFE,0xC00,..
      rd_burst(4'h6, 32'h0000_0BFE, 8'd3, 3'd1, BT_INCR);
    end
  endtask

  // boundary: bursts that end exactly on a significant offset
  task test_boundary;
    begin
      // ends at 0xFFC (last byte 0xFFF): top of the 4 KB window, all SLVERR
      wr_burst(4'h1, 32'h0000_0FF0, 8'd3, 3'd2, BT_INCR);
      rd_burst(4'h1, 32'h0000_0FF0, 8'd3, 3'd2, BT_INCR);
      // ends at 0xBFC (last in-range word): all OKAY
      wr_burst(4'h2, 32'h0000_0BF0, 8'd3, 3'd2, BT_INCR);
      rd_burst(4'h2, 32'h0000_0BF0, 8'd3, 3'd2, BT_INCR);
      // a long burst ending exactly at the top of the window
      wr_burst(4'h3, 32'h0000_0F00, 8'd63, 3'd2, BT_INCR);  // 0xF00..0xFFF
      rd_burst(4'h3, 32'h0000_0F00, 8'd63, 3'd2, BT_INCR);
      // and one ending exactly at the top of the OKAY region
      wr_burst(4'h4, 32'h0000_0B00, 8'd63, 3'd2, BT_INCR);  // 0xB00..0xBFF
      rd_burst(4'h4, 32'h0000_0B00, 8'd63, 3'd2, BT_INCR);
    end
  endtask

  // random: 100 legal random bursts, model-checked including per-beat responses
  task test_random;
    begin
      prefill_window;
      for (n = 0; n < 100; n = n + 1) begin
        r_id    = $urandom_range(0, 15);
        r_size  = $urandom_range(0, 2);
        r_burst = $urandom_range(0, 2);

        if (r_burst == 2) begin
          // WRAP: len in {1,3,7,15}; place the wrap region inside the window
          case ($urandom_range(0, 3))
            0: r_len = 1;
            1: r_len = 3;
            2: r_len = 7;
            default: r_len = 15;
          endcase
          r_total = (r_len + 1) * (1 << r_size);
          r_slots = 4096 / r_total;
          r_base  = $urandom_range(0, r_slots - 1) * r_total;
          r_addr  = r_base + $urandom_range(0, r_len) * (1 << r_size);
        end else if (r_burst == 1) begin
          // INCR: keep the whole burst inside the 4 KB window (PC11)
          r_len   = $urandom_range(0, 15);
          r_total = (r_len + 1) * (1 << r_size);
          r_addr  = $urandom_range(0, (4096 - r_total) >> r_size) * (1 << r_size);
        end else begin
          // FIXED: address never advances, only alignment matters
          r_len  = $urandom_range(0, 3);
          r_addr = $urandom_range(0, (4096 >> r_size) - 1) * (1 << r_size);
        end

        if ($urandom_range(0, 1) == 0)
          wr_burst(r_id, r_addr, r_len[7:0], r_size[2:0], r_burst[1:0]);
        else
          rd_burst(r_id, r_addr, r_len[7:0], r_size[2:0], r_burst[1:0]);

        if ((n % 25) == 24)
          $display("[TB] %0t random: %0d/100 bursts done (sb=%0d)",
                   $time, n + 1, sb_errors);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Verdict
  // ---------------------------------------------------------------------------
  task print_summary_fail;
    begin
      $display("=== TEST FAILED: %0s (sb=%0d pc=%0d bfm=%0d) ===",
               testname, sb_errors, u_pc.error_count, u_bfm.bfm_errors);
    end
  endtask

  task summary;
    begin
      if ((sb_errors == 0) && (u_pc.error_count == 0) && (u_bfm.bfm_errors == 0))
        $display("=== TEST PASSED: %0s ===", testname);
      else
        print_summary_fail;
      u_cov.print_coverage;
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
    if (!$value$plusargs("TEST=%s", testname)) testname = "smoke";
    seed = 1;
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    seed_req = seed;
    dummy    = $urandom(seed);   // seeds the stream; also overwrites `seed`
    if ($test$plusargs("DUMP")) begin
      $dumpfile("tb_axi4_mem_slave.vcd");
      $dumpvars(0, tb_axi4_mem_slave);
    end

    sb_errors = 0;
    for (i = 0; i < 1024; i = i + 1) begin
      model[i]    = 32'h0000_0000;
      mem_bval[i] = 4'h0;
    end

    @(posedge aresetn);
    repeat (2) @(posedge aclk);
    $display("[TB] %0t running TEST=%0s SEED=%0d", $time, testname, seed_req);

    if      (testname == "smoke")    test_smoke;
    else if (testname == "incr")     test_incr;
    else if (testname == "wrap")     test_wrap;
    else if (testname == "fixed")    test_fixed;
    else if (testname == "narrow")   test_narrow;
    else if (testname == "errors")   test_errors;
    else if (testname == "boundary") test_boundary;
    else if (testname == "random")   test_random;
    else begin
      $display("[TB] %0t unknown TEST=%0s", $time, testname);
      sb_errors = sb_errors + 1;
    end

    repeat (5) @(posedge aclk);
    summary;
  end

endmodule
