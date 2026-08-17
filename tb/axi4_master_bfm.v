// =============================================================================
// tb/axi4_master_bfm.v -- full AXI4 master BFM (SPEC.md section 7)
//
// Language subset: Verilog-2001 plus $urandom_range only. Tasks are STATIC
// (each BFM instance is driven by exactly one sequential test thread).
// Compiles under: iverilog -g2012  and  ModelSim ASE 10.5b vlog -sv.
//
// Per-beat addresses follow SPEC.md section 4 burst rules:
//   FIXED (2'b00): address constant every beat.
//   INCR  (2'b01): address += 2^size each beat (2'b11 treated as INCR).
//   WRAP  (2'b10): wrap boundary = (start addr aligned down to
//                  (len+1)*2^size) + (len+1)*2^size; address wraps to the
//                  aligned lower boundary when it reaches the upper boundary.
//
// Lane handling (32-bit bus), beat i at beat-address A:
//   L = A % 4
//   wdata = wbuf[i] << (8*L)
//   wstrb = ((1 << (1<<size)) - 1) << L
//   read:  rbuf[i] = (rdata >> (8*L)) & mask   (LSB-justified)
// =============================================================================

module axi4_master_bfm #(
    parameter ID_WIDTH = 4
)(
    input  wire                aclk,
    input  wire                aresetn,
    // write address channel
    output reg  [ID_WIDTH-1:0] m_axi_awid,
    output reg  [31:0]         m_axi_awaddr,
    output reg  [7:0]          m_axi_awlen,
    output reg  [2:0]          m_axi_awsize,
    output reg  [1:0]          m_axi_awburst,
    output reg  [2:0]          m_axi_awprot,
    output reg                 m_axi_awvalid,
    input  wire                m_axi_awready,
    // write data channel
    output reg  [31:0]         m_axi_wdata,
    output reg  [3:0]          m_axi_wstrb,
    output reg                 m_axi_wlast,
    output reg                 m_axi_wvalid,
    input  wire                m_axi_wready,
    // write response channel
    input  wire [ID_WIDTH-1:0] m_axi_bid,
    input  wire [1:0]          m_axi_bresp,
    input  wire                m_axi_bvalid,
    output reg                 m_axi_bready,
    // read address channel
    output reg  [ID_WIDTH-1:0] m_axi_arid,
    output reg  [31:0]         m_axi_araddr,
    output reg  [7:0]          m_axi_arlen,
    output reg  [2:0]          m_axi_arsize,
    output reg  [1:0]          m_axi_arburst,
    output reg  [2:0]          m_axi_arprot,
    output reg                 m_axi_arvalid,
    input  wire                m_axi_arready,
    // read data channel
    input  wire [ID_WIDTH-1:0] m_axi_rid,
    input  wire [31:0]         m_axi_rdata,
    input  wire [1:0]          m_axi_rresp,
    input  wire                m_axi_rlast,
    input  wire                m_axi_rvalid,
    output reg                 m_axi_rready
);

    // -------------------------------------------------------------------------
    // Public data buffers (TB reads/writes these hierarchically) -- SPEC §7
    // -------------------------------------------------------------------------
    reg [31:0] wbuf      [0:255];   // write payload, LSB-justified logical data
    reg [31:0] rbuf      [0:255];   // read results, LSB-justified per beat
    reg [1:0]  rresp_buf [0:255];   // per-beat read responses
    integer    max_delay;           // default 3 (TB may override hierarchically)
    integer    bfm_errors;          // BID/RID/RLAST self-check failure count

    // -------------------------------------------------------------------------
    // Idle / init values (all valids low; TB holds reset before calling tasks)
    // -------------------------------------------------------------------------
    initial begin
        max_delay     = 3;
        bfm_errors    = 0;
        m_axi_awid    = {ID_WIDTH{1'b0}};
        m_axi_awaddr  = 32'h0;
        m_axi_awlen   = 8'h0;
        m_axi_awsize  = 3'h0;
        m_axi_awburst = 2'h0;
        m_axi_awprot  = 3'b000;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0;
        m_axi_wstrb   = 4'h0;
        m_axi_wlast   = 1'b0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_arid    = {ID_WIDTH{1'b0}};
        m_axi_araddr  = 32'h0;
        m_axi_arlen   = 8'h0;
        m_axi_arsize  = 3'h0;
        m_axi_arburst = 2'h0;
        m_axi_arprot  = 3'b000;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;
    end

    // -------------------------------------------------------------------------
    // task axi_write_burst -- SPEC §7 exact signature (static task)
    // -------------------------------------------------------------------------
    task axi_write_burst (
        input  [ID_WIDTH-1:0] id,
        input  [31:0]         addr,
        input  [7:0]          len,
        input  [2:0]          size,
        input  [1:0]          burst,
        output [1:0]          resp
    );
        integer    i;
        integer    nbytes;
        integer    total;
        integer    lane;
        reg [31:0] wrap_lower;
        reg [31:0] wrap_upper;
        reg [31:0] beat_addr;
    begin
        nbytes     = (32'd1 << size);
        total      = (len + 32'd1) * nbytes;
        wrap_lower = (addr / total) * total;   // start aligned down to total
        wrap_upper = wrap_lower + total;       // wrap boundary
        beat_addr  = addr;

        // ---- AW phase (random start delay) ----
        repeat ($urandom_range(0, max_delay)) @(posedge aclk);
        m_axi_awid    <= id;
        m_axi_awaddr  <= addr;
        m_axi_awlen   <= len;
        m_axi_awsize  <= size;
        m_axi_awburst <= burst;
        m_axi_awprot  <= 3'b000;
        m_axi_awvalid <= 1'b1;
        @(posedge aclk);
        while (m_axi_awready !== 1'b1) @(posedge aclk);
        m_axi_awvalid <= 1'b0;

        // ---- W phase: len+1 beats, random inter-beat gaps ----
        for (i = 0; i <= len; i = i + 1) begin
            repeat ($urandom_range(0, max_delay)) @(posedge aclk);
            lane = beat_addr % 4;
            m_axi_wdata  <= wbuf[i] << (8 * lane);
            m_axi_wstrb  <= ((32'd1 << (32'd1 << size)) - 32'd1) << lane;
            m_axi_wlast  <= (i == len);   // wlast only on final beat
            m_axi_wvalid <= 1'b1;
            @(posedge aclk);
            while (m_axi_wready !== 1'b1) @(posedge aclk);
            m_axi_wvalid <= 1'b0;
            m_axi_wlast  <= 1'b0;
            // advance beat address per burst type
            if (burst != 2'b00) begin      // INCR / WRAP (2'b11 as INCR)
                beat_addr = beat_addr + nbytes;
                if (burst == 2'b10 && beat_addr >= wrap_upper)
                    beat_addr = wrap_lower;
            end
        end

        // ---- B phase (random bready delay) ----
        repeat ($urandom_range(0, max_delay)) @(posedge aclk);
        m_axi_bready <= 1'b1;
        @(posedge aclk);
        while (m_axi_bvalid !== 1'b1) @(posedge aclk);
        resp = m_axi_bresp;
        if (m_axi_bid !== id) begin
            bfm_errors = bfm_errors + 1;
            $display("[BFM] %0t axi_write_burst: BID mismatch exp=%0h got=%0h",
                     $time, id, m_axi_bid);
        end
        m_axi_bready <= 1'b0;
    end
    endtask

    // -------------------------------------------------------------------------
    // task axi_read_burst -- SPEC §7 exact signature (static task)
    // resp = worst rresp over the burst (numerically: 11 > 10 > 00)
    // -------------------------------------------------------------------------
    task axi_read_burst (
        input  [ID_WIDTH-1:0] id,
        input  [31:0]         addr,
        input  [7:0]          len,
        input  [2:0]          size,
        input  [1:0]          burst,
        output [1:0]          resp
    );
        integer    i;
        integer    nbytes;
        integer    total;
        integer    lane;
        reg [31:0] wrap_lower;
        reg [31:0] wrap_upper;
        reg [31:0] beat_addr;
        reg [31:0] mask;
        reg [1:0]  worst;
    begin
        nbytes     = (32'd1 << size);
        total      = (len + 32'd1) * nbytes;
        wrap_lower = (addr / total) * total;
        wrap_upper = wrap_lower + total;
        beat_addr  = addr;
        worst      = 2'b00;
        case (size)
            3'd0:    mask = 32'h0000_00FF;
            3'd1:    mask = 32'h0000_FFFF;
            default: mask = 32'hFFFF_FFFF;
        endcase

        // ---- AR phase (random start delay) ----
        repeat ($urandom_range(0, max_delay)) @(posedge aclk);
        m_axi_arid    <= id;
        m_axi_araddr  <= addr;
        m_axi_arlen   <= len;
        m_axi_arsize  <= size;
        m_axi_arburst <= burst;
        m_axi_arprot  <= 3'b000;
        m_axi_arvalid <= 1'b1;
        @(posedge aclk);
        while (m_axi_arready !== 1'b1) @(posedge aclk);
        m_axi_arvalid <= 1'b0;

        // ---- R phase: len+1 beats with random rready backpressure ----
        for (i = 0; i <= len; i = i + 1) begin
            repeat ($urandom_range(0, max_delay)) @(posedge aclk);
            m_axi_rready <= 1'b1;
            @(posedge aclk);
            while (m_axi_rvalid !== 1'b1) @(posedge aclk);
            lane         = beat_addr % 4;
            rbuf[i]      = (m_axi_rdata >> (8 * lane)) & mask;  // LSB-justify
            rresp_buf[i] = m_axi_rresp;
            if (m_axi_rresp > worst) worst = m_axi_rresp;
            // self-checks: RID reflection + RLAST position
            if (m_axi_rid !== id) begin
                bfm_errors = bfm_errors + 1;
                $display("[BFM] %0t axi_read_burst: RID mismatch on beat %0d exp=%0h got=%0h",
                         $time, i, id, m_axi_rid);
            end
            if ((i == len) && (m_axi_rlast !== 1'b1)) begin
                bfm_errors = bfm_errors + 1;
                $display("[BFM] %0t axi_read_burst: RLAST not asserted on final beat %0d",
                         $time, i);
            end
            if ((i != len) && (m_axi_rlast !== 1'b0)) begin
                bfm_errors = bfm_errors + 1;
                $display("[BFM] %0t axi_read_burst: RLAST asserted early on beat %0d of %0d",
                         $time, i, len);
            end
            m_axi_rready <= 1'b0;
            // advance beat address per burst type
            if (burst != 2'b00) begin      // INCR / WRAP (2'b11 as INCR)
                beat_addr = beat_addr + nbytes;
                if (burst == 2'b10 && beat_addr >= wrap_upper)
                    beat_addr = wrap_lower;
            end
        end
        resp = worst;
    end
    endtask

endmodule
