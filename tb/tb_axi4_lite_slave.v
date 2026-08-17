// -----------------------------------------------------------------------------
// tb_axi4_lite_slave.v
// Self-checking testbench for axi4_lite_slave (SPEC.md sections 2, 10).
//
// Tests (+TEST=): smoke | strobes | errors | aliasing | random
// Options       : +SEED=<n> (default 1), +DUMP (VCD waves)
//
// Language subset (SPEC.md section 0): Verilog-2001 plus only
// $urandom / $urandom_range / $value$plusargs / $test$plusargs.
// All tasks are static; a single sequential test thread drives the BFM.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_axi4_lite_slave;

  // ---------------------------------------------------------------------------
  // Parameters / constants
  // ---------------------------------------------------------------------------
  localparam NUM_REGS    = 12;      // DUT valid word indices 0..11
  localparam RESP_OKAY   = 2'b00;
  localparam RESP_SLVERR = 2'b10;

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
  // AXI4-Lite interface (BFM master <-> DUT slave, observed by the checker)
  // ---------------------------------------------------------------------------
  wire [31:0] awaddr;
  wire [2:0]  awprot;
  wire        awvalid;
  wire        awready;
  wire [31:0] wdata;
  wire [3:0]  wstrb;
  wire        wvalid;
  wire        wready;
  wire [1:0]  bresp;
  wire        bvalid;
  wire        bready;
  wire [31:0] araddr;
  wire [2:0]  arprot;
  wire        arvalid;
  wire        arready;
  wire [31:0] rdata;
  wire [1:0]  rresp;
  wire        rvalid;
  wire        rready;

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  axi4_lite_slave #(
    .NUM_REGS (NUM_REGS)
  ) u_dut (
    .aclk          (aclk),
    .aresetn       (aresetn),
    .s_axi_awaddr  (awaddr),
    .s_axi_awprot  (awprot),
    .s_axi_awvalid (awvalid),
    .s_axi_awready (awready),
    .s_axi_wdata   (wdata),
    .s_axi_wstrb   (wstrb),
    .s_axi_wvalid  (wvalid),
    .s_axi_wready  (wready),
    .s_axi_bresp   (bresp),
    .s_axi_bvalid  (bvalid),
    .s_axi_bready  (bready),
    .s_axi_araddr  (araddr),
    .s_axi_arprot  (arprot),
    .s_axi_arvalid (arvalid),
    .s_axi_arready (arready),
    .s_axi_rdata   (rdata),
    .s_axi_rresp   (rresp),
    .s_axi_rvalid  (rvalid),
    .s_axi_rready  (rready)
  );

  // ---------------------------------------------------------------------------
  // Master BFM
  // ---------------------------------------------------------------------------
  axi4_lite_master_bfm u_bfm (
    .aclk          (aclk),
    .aresetn       (aresetn),
    .m_axi_awaddr  (awaddr),
    .m_axi_awprot  (awprot),
    .m_axi_awvalid (awvalid),
    .m_axi_awready (awready),
    .m_axi_wdata   (wdata),
    .m_axi_wstrb   (wstrb),
    .m_axi_wvalid  (wvalid),
    .m_axi_wready  (wready),
    .m_axi_bresp   (bresp),
    .m_axi_bvalid  (bvalid),
    .m_axi_bready  (bready),
    .m_axi_araddr  (araddr),
    .m_axi_arprot  (arprot),
    .m_axi_arvalid (arvalid),
    .m_axi_arready (arready),
    .m_axi_rdata   (rdata),
    .m_axi_rresp   (rresp),
    .m_axi_rvalid  (rvalid),
    .m_axi_rready  (rready)
  );

  // ---------------------------------------------------------------------------
  // Passive protocol checker on the same interface
  // ---------------------------------------------------------------------------
  axi4_lite_protocol_checker #(
    .NAME ("PC")
  ) u_pc (
    .aclk    (aclk),
    .aresetn (aresetn),
    .awaddr  (awaddr),
    .awprot  (awprot),
    .awvalid (awvalid),
    .awready (awready),
    .wdata   (wdata),
    .wstrb   (wstrb),
    .wvalid  (wvalid),
    .wready  (wready),
    .bresp   (bresp),
    .bvalid  (bvalid),
    .bready  (bready),
    .araddr  (araddr),
    .arprot  (arprot),
    .arvalid (arvalid),
    .arready (arready),
    .rdata   (rdata),
    .rresp   (rresp),
    .rvalid  (rvalid),
    .rready  (rready)
  );

  // ---------------------------------------------------------------------------
  // Test bookkeeping
  // ---------------------------------------------------------------------------
  reg [255:0] testname;
  integer     seed;
  integer     seed_req;   // requested seed; $urandom(seed) mutates its argument
  integer     dummy;
  integer     sb_errors;    // scoreboard mismatch counter
  integer     bfm_errors;   // lite BFM has no self-checks (SPEC section 6) -> stays 0
  integer     i;

  // Reference model: 16 words + per-byte valid flags. The DUT register file is
  // NOT initialized, so data is only compared on byte lanes the test has
  // actually written (write-before-read discipline, SPEC section 10).
  reg [31:0] model      [0:15];
  reg [3:0]  model_bval [0:15];

  // scratch for the random test
  reg [3:0]  r_idx;
  reg [31:0] r_data;
  reg [3:0]  r_strb;

  // ---------------------------------------------------------------------------
  // Scoreboarded operations
  // ---------------------------------------------------------------------------
  // Write via BFM, check BRESP against expected (SLVERR for index >= NUM_REGS,
  // model untouched; OKAY otherwise with strobe-merged model update).
  task do_write (input [31:0] addr, input [31:0] data, input [3:0] strb);
    reg [1:0] resp;
    reg [1:0] exp_resp;
    reg [3:0] idx;
    begin
      idx      = addr[5:2];
      exp_resp = (idx >= NUM_REGS) ? RESP_SLVERR : RESP_OKAY;
      u_bfm.axi_write(addr, data, strb, resp);
      if (resp !== exp_resp) begin
        sb_errors = sb_errors + 1;
        $display("[TB] %0t SB: BRESP mismatch addr=0x%08h exp=%b got=%b",
                 $time, addr, exp_resp, resp);
      end
      if (exp_resp == RESP_OKAY) begin
        if (strb[0]) begin model[idx][7:0]   = data[7:0];   model_bval[idx][0] = 1'b1; end
        if (strb[1]) begin model[idx][15:8]  = data[15:8];  model_bval[idx][1] = 1'b1; end
        if (strb[2]) begin model[idx][23:16] = data[23:16]; model_bval[idx][2] = 1'b1; end
        if (strb[3]) begin model[idx][31:24] = data[31:24]; model_bval[idx][3] = 1'b1; end
      end
    end
  endtask

  // Read via BFM, check RRESP; invalid index must return 32'h0000_0000;
  // valid index data is compared per byte lane against the model (only lanes
  // that have been written).
  task do_read (input [31:0] addr);
    reg [31:0] data;
    reg [1:0]  resp;
    reg [1:0]  exp_resp;
    reg [3:0]  idx;
    begin
      idx      = addr[5:2];
      exp_resp = (idx >= NUM_REGS) ? RESP_SLVERR : RESP_OKAY;
      u_bfm.axi_read(addr, data, resp);
      if (resp !== exp_resp) begin
        sb_errors = sb_errors + 1;
        $display("[TB] %0t SB: RRESP mismatch addr=0x%08h exp=%b got=%b",
                 $time, addr, exp_resp, resp);
      end
      if (idx >= NUM_REGS) begin
        if (data !== 32'h0000_0000) begin
          sb_errors = sb_errors + 1;
          $display("[TB] %0t SB: invalid-index read data addr=0x%08h exp=0x00000000 got=0x%08h",
                   $time, addr, data);
        end
      end else begin
        if (model_bval[idx][0] && (data[7:0] !== model[idx][7:0])) begin
          sb_errors = sb_errors + 1;
          $display("[TB] %0t SB: read data mismatch addr=0x%08h lane0 exp=0x%02h got=0x%02h",
                   $time, addr, model[idx][7:0], data[7:0]);
        end
        if (model_bval[idx][1] && (data[15:8] !== model[idx][15:8])) begin
          sb_errors = sb_errors + 1;
          $display("[TB] %0t SB: read data mismatch addr=0x%08h lane1 exp=0x%02h got=0x%02h",
                   $time, addr, model[idx][15:8], data[15:8]);
        end
        if (model_bval[idx][2] && (data[23:16] !== model[idx][23:16])) begin
          sb_errors = sb_errors + 1;
          $display("[TB] %0t SB: read data mismatch addr=0x%08h lane2 exp=0x%02h got=0x%02h",
                   $time, addr, model[idx][23:16], data[23:16]);
        end
        if (model_bval[idx][3] && (data[31:24] !== model[idx][31:24])) begin
          sb_errors = sb_errors + 1;
          $display("[TB] %0t SB: read data mismatch addr=0x%08h lane3 exp=0x%02h got=0x%02h",
                   $time, addr, model[idx][31:24], data[31:24]);
        end
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  // smoke: write then readback a few registers, full strobes
  task test_smoke;
    begin
      do_write(32'h0000_0000, 32'hA5A5_0001, 4'hF);   // idx 0
      do_write(32'h0000_0004, 32'h5A5A_0002, 4'hF);   // idx 1
      do_write(32'h0000_0008, 32'hDEAD_BEEF, 4'hF);   // idx 2
      do_write(32'h0000_001C, 32'hCAFE_F00D, 4'hF);   // idx 7
      do_write(32'h0000_002C, 32'h1234_5678, 4'hF);   // idx 11 (last valid)
      do_read (32'h0000_0000);
      do_read (32'h0000_0004);
      do_read (32'h0000_0008);
      do_read (32'h0000_001C);
      do_read (32'h0000_002C);
      // overwrite one register and read it back again
      do_write(32'h0000_0004, 32'h0BAD_F00D, 4'hF);
      do_read (32'h0000_0004);
    end
  endtask

  // strobes: all 16 strobe patterns on one register, merge checked vs model
  task test_strobes;
    begin
      // initialize the register with a full-strobe write first
      do_write(32'h0000_000C, 32'h0000_0000, 4'hF);   // idx 3
      do_read (32'h0000_000C);
      // every strobe pattern 0000..1111 with random data, readback after each
      for (i = 0; i < 16; i = i + 1) begin
        r_data = $urandom;
        do_write(32'h0000_000C, r_data, i[3:0]);
        do_read (32'h0000_000C);
      end
      // classic single-byte walk with known data
      do_write(32'h0000_000C, 32'h1122_3344, 4'b0001);
      do_read (32'h0000_000C);
      do_write(32'h0000_000C, 32'h5566_7788, 4'b0010);
      do_read (32'h0000_000C);
      do_write(32'h0000_000C, 32'h99AA_BBCC, 4'b0100);
      do_read (32'h0000_000C);
      do_write(32'h0000_000C, 32'hDDEE_FF00, 4'b1000);
      do_read (32'h0000_000C);
    end
  endtask

  // errors: indices 12..15 -> SLVERR, state untouched, invalid reads return 0
  task test_errors;
    begin
      // establish known-good state in valid registers
      do_write(32'h0000_0000, 32'h0123_4567, 4'hF);   // idx 0
      do_write(32'h0000_0028, 32'hFEDC_BA98, 4'hF);   // idx 10
      do_write(32'h0000_002C, 32'h89AB_CDEF, 4'hF);   // idx 11
      // writes to invalid indices 12..15 -> SLVERR, must not modify state
      do_write(32'h0000_0030, 32'hBAD0_0000, 4'hF);   // idx 12
      do_write(32'h0000_0034, 32'hBAD0_0001, 4'hF);   // idx 13
      do_write(32'h0000_0038, 32'hBAD0_0002, 4'b0101);// idx 14, partial strobe
      do_write(32'h0000_003C, 32'hBAD0_0003, 4'hF);   // idx 15
      // reads of invalid indices -> SLVERR and rdata == 0
      do_read (32'h0000_0030);
      do_read (32'h0000_0034);
      do_read (32'h0000_0038);
      do_read (32'h0000_003C);
      // valid registers must be unchanged
      do_read (32'h0000_0000);
      do_read (32'h0000_0028);
      do_read (32'h0000_002C);
    end
  endtask

  // aliasing: addr bits [31:6] and [1:0] ignored -> 64-byte window aliases
  task test_aliasing;
    begin
      // write via base 0x0000_0008 (idx 2), read back via aliases (SPEC s10)
      do_write(32'h0000_0008, 32'hA11A_5ED0, 4'hF);
      do_read (32'h0000_0048);   // +0x40   -> same register
      do_read (32'h0000_0F08);   // high in the 4 KB window -> same register
      do_read (32'h0000_000A);   // addr[1:0] ignored -> same register
      // write via an alias, read back via the base address
      do_write(32'h0000_0F49, 32'h0DD5_C0DE, 4'hF);   // 0xF49[5:2] = 2
      do_read (32'h0000_0008);
      // a different register through an alias: 0xFDC[5:2] = 7 -> base 0x1C
      do_write(32'h0000_0FDC, 32'h5EED_F00D, 4'hF);
      do_read (32'h0000_001C);
      do_read (32'h0000_0FDC);
    end
  endtask

  // random: 200 random ops, index 0..15, random data/strobes, model-checked
  task test_random;
    begin
      for (i = 0; i < 200; i = i + 1) begin
        r_idx = $urandom_range(0, 15);
        if ($urandom_range(0, 1) == 0) begin
          r_data = $urandom;
          r_strb = $urandom_range(0, 15);
          do_write({26'b0, r_idx, 2'b00}, r_data, r_strb);
        end else begin
          do_read({26'b0, r_idx, 2'b00});
        end
        if ((i % 50) == 49)
          $display("[TB] %0t random: %0d/200 ops done (sb=%0d)",
                   $time, i + 1, sb_errors);
      end
    end
  endtask

  // ---------------------------------------------------------------------------
  // Verdict
  // ---------------------------------------------------------------------------
  task print_summary_fail;
    begin
      $display("=== TEST FAILED: %0s (sb=%0d pc=%0d bfm=%0d) ===",
               testname, sb_errors, u_pc.error_count, bfm_errors);
    end
  endtask

  task summary;
    begin
      if ((sb_errors == 0) && (u_pc.error_count == 0) && (bfm_errors == 0))
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
    if (!$value$plusargs("TEST=%s", testname)) testname = "smoke";
    seed = 1;
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    seed_req = seed;
    dummy    = $urandom(seed);   // seeds the stream; also overwrites `seed`
    if ($test$plusargs("DUMP")) begin
      $dumpfile("tb_axi4_lite_slave.vcd");
      $dumpvars(0, tb_axi4_lite_slave);
    end

    sb_errors  = 0;
    bfm_errors = 0;
    for (i = 0; i < 16; i = i + 1) begin
      model[i]      = 32'h0000_0000;
      model_bval[i] = 4'h0;
    end

    @(posedge aresetn);
    repeat (2) @(posedge aclk);
    $display("[TB] %0t running TEST=%0s SEED=%0d", $time, testname, seed_req);

    if      (testname == "smoke")    test_smoke;
    else if (testname == "strobes")  test_strobes;
    else if (testname == "errors")   test_errors;
    else if (testname == "aliasing") test_aliasing;
    else if (testname == "random")   test_random;
    else begin
      $display("[TB] %0t unknown TEST=%0s", $time, testname);
      sb_errors = sb_errors + 1;
    end

    repeat (5) @(posedge aclk);
    summary;
  end

endmodule
