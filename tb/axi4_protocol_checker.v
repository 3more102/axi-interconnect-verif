`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axi4_protocol_checker.v -- passive full-AXI4 legality monitor
// Implements SPEC.md section 8 (full-AXI4 half).
//
// Instantiated on one AXI4 interface; every port is an input. Zero tolerance:
// any violation increments the public `error_count`, which the TB folds into
// its PASS/FAIL verdict.
//
//   PC01 AW | PC02 W | PC03 AR | PC04 B | PC05 R
//        VALID must stay high with a stable payload until its READY handshake.
//   PC06 no X/Z on any VALID once reset has deasserted.
//   PC07 no X/Z on a channel's payload while its VALID is high.
//   PC08 WLAST lands on exactly the (AWLEN+1)-th W beat.
//   PC09 per-ID RLAST lands on exactly the (ARLEN+1)-th R beat of that ID,
//        and no R beat may appear for an ID with no outstanding AR.
//   PC10 WRAP bursts have len in {1,3,7,15} and an address aligned to 2^size.
//   PC11 no burst crosses a 4 KB boundary.
//   PC12 all VALIDs low while aresetn == 0 (sampled on posedge).
//   PC13 no B response for an ID with no outstanding write.
//
// Outstanding-transaction tracking is bounded (depth 4 per queue, IDs 0..31);
// overflowing that bound is itself reported, so the checker can never go
// quietly blind.
//
// Language subset: Verilog-2001 (SPEC.md section 0).
//-----------------------------------------------------------------------------

module axi4_protocol_checker #(
    parameter ID_WIDTH = 4,
    parameter NAME     = "PC"
)(
    input wire                aclk,
    input wire                aresetn,
    input wire [ID_WIDTH-1:0] awid,
    input wire [31:0]         awaddr,
    input wire [7:0]          awlen,
    input wire [2:0]          awsize,
    input wire [1:0]          awburst,
    input wire [2:0]          awprot,
    input wire                awvalid,
    input wire                awready,
    input wire [31:0]         wdata,
    input wire [3:0]          wstrb,
    input wire                wlast,
    input wire                wvalid,
    input wire                wready,
    input wire [ID_WIDTH-1:0] bid,
    input wire [1:0]          bresp,
    input wire                bvalid,
    input wire                bready,
    input wire [ID_WIDTH-1:0] arid,
    input wire [31:0]         araddr,
    input wire [7:0]          arlen,
    input wire [2:0]          arsize,
    input wire [1:0]          arburst,
    input wire [2:0]          arprot,
    input wire                arvalid,
    input wire                arready,
    input wire [ID_WIDTH-1:0] rid,
    input wire [31:0]         rdata,
    input wire [1:0]          rresp,
    input wire                rlast,
    input wire                rvalid,
    input wire                rready
);

    localparam NIDS  = 32;    // per-ID tracking capacity (IDs 0..31)
    localparam DEPTH = 4;     // outstanding transactions tracked per queue

    integer error_count;

    // zero-extended IDs, so a 4-bit and a 5-bit interface index the same tables
    wire [4:0] awid_x = awid;
    wire [4:0] bid_x  = bid;
    wire [4:0] arid_x = arid;
    wire [4:0] rid_x  = rid;

    wire aw_hs = (awvalid === 1'b1) && (awready === 1'b1);
    wire w_hs  = (wvalid  === 1'b1) && (wready  === 1'b1);
    wire b_hs  = (bvalid  === 1'b1) && (bready  === 1'b1);
    wire ar_hs = (arvalid === 1'b1) && (arready === 1'b1);
    wire r_hs  = (rvalid  === 1'b1) && (rready  === 1'b1);

    integer k;

    function is_xz1;
        input v;
        begin
            is_xz1 = (v !== 1'b0) && (v !== 1'b1);
        end
    endfunction

    task viol;
        input [8*56-1:0] msg;
        begin
            $display("[%0s] %0t %0s", NAME, $time, msg);
            error_count = error_count + 1;
        end
    endtask

    task violn;
        input [8*56-1:0] msg;
        input integer    v0;
        input integer    v1;
        begin
            $display("[%0s] %0t %0s (got %0d, expected %0d)", NAME, $time,
                     msg, v0, v1);
            error_count = error_count + 1;
        end
    endtask

    //=========================================================================
    // PC01-PC07, PC12 : handshake legality, X/Z hygiene, reset behavior
    //=========================================================================
    reg               aw_v_q, aw_r_q;
    reg [ID_WIDTH-1:0] aw_id_q;
    reg [31:0]        aw_addr_q;
    reg [7:0]         aw_len_q;
    reg [2:0]         aw_size_q;
    reg [1:0]         aw_burst_q;
    reg [2:0]         aw_prot_q;
    reg               w_v_q, w_r_q;
    reg [31:0]        w_data_q;
    reg [3:0]         w_strb_q;
    reg               w_last_q;
    reg               b_v_q, b_r_q;
    reg [ID_WIDTH-1:0] b_id_q;
    reg [1:0]         b_resp_q;
    reg               ar_v_q, ar_r_q;
    reg [ID_WIDTH-1:0] ar_id_q;
    reg [31:0]        ar_addr_q;
    reg [7:0]         ar_len_q;
    reg [2:0]         ar_size_q;
    reg [1:0]         ar_burst_q;
    reg [2:0]         ar_prot_q;
    reg               r_v_q, r_r_q;
    reg [ID_WIDTH-1:0] r_id_q;
    reg [31:0]        r_data_q;
    reg [1:0]         r_resp_q;
    reg               r_last_q;
    reg               seen_reset;
    reg               aresetn_q;   // aresetn as sampled at the previous posedge

    initial begin
        error_count = 0;
        aresetn_q = 1'bx;
        aw_v_q = 1'b0; aw_r_q = 1'b0;
        w_v_q  = 1'b0; w_r_q  = 1'b0;
        b_v_q  = 1'b0; b_r_q  = 1'b0;
        ar_v_q = 1'b0; ar_r_q = 1'b0;
        r_v_q  = 1'b0; r_r_q  = 1'b0;
        seen_reset = 1'b0;
    end

    always @(posedge aclk) begin
        aresetn_q <= aresetn;
        if (!aresetn) begin
            seen_reset <= 1'b1;
            // Reset is synchronous (SPEC.md section 0), so it takes effect ON
            // the edge: the value sampled at the first in-reset edge is the
            // pre-reset one. Only edges where reset was already low count.
            if (aresetn_q === 1'b0) begin
            if (awvalid !== 1'b0) viol("PC12: AWVALID asserted during reset");
            if (wvalid  !== 1'b0) viol("PC12: WVALID asserted during reset");
            if (bvalid  !== 1'b0) viol("PC12: BVALID asserted during reset");
            if (arvalid !== 1'b0) viol("PC12: ARVALID asserted during reset");
            if (rvalid  !== 1'b0) viol("PC12: RVALID asserted during reset");
            end
        end else begin
            // ---- PC06 ------------------------------------------------------
            if (seen_reset) begin
                if (is_xz1(awvalid)) viol("PC06: AWVALID is X/Z");
                if (is_xz1(wvalid))  viol("PC06: WVALID is X/Z");
                if (is_xz1(bvalid))  viol("PC06: BVALID is X/Z");
                if (is_xz1(arvalid)) viol("PC06: ARVALID is X/Z");
                if (is_xz1(rvalid))  viol("PC06: RVALID is X/Z");
            end

            // ---- PC07 ------------------------------------------------------
            if (awvalid === 1'b1 &&
                (^{awid, awaddr, awlen, awsize, awburst, awprot} === 1'bx))
                viol("PC07: AW payload has X/Z while AWVALID high");
            if (wvalid === 1'b1 && (^{wdata, wstrb, wlast} === 1'bx))
                viol("PC07: W payload has X/Z while WVALID high");
            if (bvalid === 1'b1 && (^{bid, bresp} === 1'bx))
                viol("PC07: B payload has X/Z while BVALID high");
            if (arvalid === 1'b1 &&
                (^{arid, araddr, arlen, arsize, arburst, arprot} === 1'bx))
                viol("PC07: AR payload has X/Z while ARVALID high");
            if (rvalid === 1'b1 && (^{rid, rdata, rresp, rlast} === 1'bx))
                viol("PC07: R payload has X/Z while RVALID high");

            // ---- PC01..PC05 : stability across a stall ---------------------
            if (aw_v_q === 1'b1 && aw_r_q !== 1'b1) begin
                if (awvalid !== 1'b1)
                    viol("PC01: AWVALID deasserted before AWREADY");
                else if (awid !== aw_id_q || awaddr !== aw_addr_q ||
                         awlen !== aw_len_q || awsize !== aw_size_q ||
                         awburst !== aw_burst_q || awprot !== aw_prot_q)
                    viol("PC01: AW payload changed while stalled");
            end
            if (w_v_q === 1'b1 && w_r_q !== 1'b1) begin
                if (wvalid !== 1'b1)
                    viol("PC02: WVALID deasserted before WREADY");
                else if (wdata !== w_data_q || wstrb !== w_strb_q ||
                         wlast !== w_last_q)
                    viol("PC02: W payload changed while stalled");
            end
            if (ar_v_q === 1'b1 && ar_r_q !== 1'b1) begin
                if (arvalid !== 1'b1)
                    viol("PC03: ARVALID deasserted before ARREADY");
                else if (arid !== ar_id_q || araddr !== ar_addr_q ||
                         arlen !== ar_len_q || arsize !== ar_size_q ||
                         arburst !== ar_burst_q || arprot !== ar_prot_q)
                    viol("PC03: AR payload changed while stalled");
            end
            if (b_v_q === 1'b1 && b_r_q !== 1'b1) begin
                if (bvalid !== 1'b1)
                    viol("PC04: BVALID deasserted before BREADY");
                else if (bid !== b_id_q || bresp !== b_resp_q)
                    viol("PC04: B payload changed while stalled");
            end
            if (r_v_q === 1'b1 && r_r_q !== 1'b1) begin
                if (rvalid !== 1'b1)
                    viol("PC05: RVALID deasserted before RREADY");
                else if (rid !== r_id_q || rdata !== r_data_q ||
                         rresp !== r_resp_q || rlast !== r_last_q)
                    viol("PC05: R payload changed while stalled");
            end
        end

        if (!aresetn) begin
            aw_v_q <= 1'b0; aw_r_q <= 1'b0;
            w_v_q  <= 1'b0; w_r_q  <= 1'b0;
            b_v_q  <= 1'b0; b_r_q  <= 1'b0;
            ar_v_q <= 1'b0; ar_r_q <= 1'b0;
            r_v_q  <= 1'b0; r_r_q  <= 1'b0;
        end else begin
            aw_v_q <= awvalid; aw_r_q <= awready;
            w_v_q  <= wvalid;  w_r_q  <= wready;
            b_v_q  <= bvalid;  b_r_q  <= bready;
            ar_v_q <= arvalid; ar_r_q <= arready;
            r_v_q  <= rvalid;  r_r_q  <= rready;
        end
        aw_id_q <= awid; aw_addr_q <= awaddr; aw_len_q <= awlen;
        aw_size_q <= awsize; aw_burst_q <= awburst; aw_prot_q <= awprot;
        w_data_q <= wdata; w_strb_q <= wstrb; w_last_q <= wlast;
        b_id_q <= bid; b_resp_q <= bresp;
        ar_id_q <= arid; ar_addr_q <= araddr; ar_len_q <= arlen;
        ar_size_q <= arsize; ar_burst_q <= arburst; ar_prot_q <= arprot;
        r_id_q <= rid; r_data_q <= rdata; r_resp_q <= rresp; r_last_q <= rlast;
    end

    //=========================================================================
    // PC08, PC09, PC10, PC11, PC13 : transaction tracking
    //
    // Blocking assignments and a fixed evaluation order (AW push -> W beat,
    // AR push -> R beat) so that a burst whose address phase and first data
    // beat land in the same cycle is tracked correctly.
    //=========================================================================

    // PC08: FIFO of accepted AWLENs (write data is never interleaved in AXI4,
    // so W beats always belong to the oldest outstanding AW)
    reg [7:0]  awlen_fifo [0:DEPTH-1];
    reg [2:0]  awlen_cnt;
    reg [1:0]  awlen_head;
    reg [8:0]  w_beat;

    // PC09: per-ID AR queues, flattened as [id*DEPTH + slot]
    reg [7:0]  arq_len  [0:NIDS*DEPTH-1];
    reg [2:0]  arq_cnt  [0:NIDS-1];
    reg [1:0]  arq_head [0:NIDS-1];
    reg [8:0]  r_beat   [0:NIDS-1];

    // PC13: per-ID outstanding write counters
    reg [2:0]  aw_out   [0:NIDS-1];

    integer bytes;
    integer align_mask;
    integer exp_len;

    initial begin
        awlen_cnt  = 3'd0;
        awlen_head = 2'd0;
        w_beat     = 9'd0;
        for (k = 0; k < NIDS; k = k + 1) begin
            arq_cnt[k]  = 3'd0;
            arq_head[k] = 2'd0;
            r_beat[k]   = 9'd0;
            aw_out[k]   = 3'd0;
        end
        for (k = 0; k < NIDS*DEPTH; k = k + 1)
            arq_len[k] = 8'd0;
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            awlen_cnt  = 3'd0;
            awlen_head = 2'd0;
            w_beat     = 9'd0;
            for (k = 0; k < NIDS; k = k + 1) begin
                arq_cnt[k]  = 3'd0;
                arq_head[k] = 2'd0;
                r_beat[k]   = 9'd0;
                aw_out[k]   = 3'd0;
            end
        end else begin
            //---------------------------------------------------------------
            // AW handshake: PC10, PC11, push PC08 FIFO, bump PC13 counter
            //---------------------------------------------------------------
            if (aw_hs) begin
                if (awburst == 2'b10) begin
                    if (awlen != 8'd1 && awlen != 8'd3 &&
                        awlen != 8'd7 && awlen != 8'd15)
                        viol("PC10: WRAP AWLEN not in {1,3,7,15}");
                    align_mask = (1 << awsize) - 1;
                    if ((awaddr & align_mask) != 0)
                        viol("PC10: WRAP AWADDR not aligned to 2^AWSIZE");
                end
                if (awburst == 2'b01 || awburst == 2'b11) begin
                    bytes = (awlen + 1) << awsize;
                    if ((awaddr % 4096) + bytes > 4096)
                        viol("PC11: write burst crosses a 4KB boundary");
                end

                if (awlen_cnt >= DEPTH)
                    viol("PC08: more than 4 outstanding writes, cannot track");
                else begin
                    awlen_fifo[(awlen_head + awlen_cnt) % DEPTH] = awlen;
                    awlen_cnt = awlen_cnt + 1;
                end

                if (aw_out[awid_x] >= DEPTH)
                    viol("PC13: more than 4 outstanding writes for one ID");
                else
                    aw_out[awid_x] = aw_out[awid_x] + 1;
            end

            //---------------------------------------------------------------
            // W beat: PC08
            //---------------------------------------------------------------
            if (w_hs) begin
                w_beat = w_beat + 1;
                if (wlast === 1'b1) begin
                    if (awlen_cnt == 0)
                        viol("PC08: WLAST with no outstanding AW");
                    else begin
                        exp_len = awlen_fifo[awlen_head] + 1;
                        if (w_beat != exp_len)
                            violn("PC08: WLAST on wrong beat", w_beat, exp_len);
                        awlen_head = (awlen_head + 1) % DEPTH;
                        awlen_cnt  = awlen_cnt - 1;
                    end
                    w_beat = 0;
                end else if (awlen_cnt != 0 &&
                             w_beat > awlen_fifo[awlen_head]) begin
                    // already past the final beat and WLAST never came
                    violn("PC08: WLAST missing on final beat", w_beat,
                          awlen_fifo[awlen_head] + 1);
                    awlen_head = (awlen_head + 1) % DEPTH;
                    awlen_cnt  = awlen_cnt - 1;
                    w_beat     = 0;
                end
            end

            //---------------------------------------------------------------
            // B handshake: PC13
            //---------------------------------------------------------------
            if (b_hs) begin
                if (aw_out[bid_x] == 0)
                    violn("PC13: B response for ID with no outstanding write",
                          bid_x, 0);
                else
                    aw_out[bid_x] = aw_out[bid_x] - 1;
            end

            //---------------------------------------------------------------
            // AR handshake: PC10, PC11, push that ID's queue
            //---------------------------------------------------------------
            if (ar_hs) begin
                if (arburst == 2'b10) begin
                    if (arlen != 8'd1 && arlen != 8'd3 &&
                        arlen != 8'd7 && arlen != 8'd15)
                        viol("PC10: WRAP ARLEN not in {1,3,7,15}");
                    align_mask = (1 << arsize) - 1;
                    if ((araddr & align_mask) != 0)
                        viol("PC10: WRAP ARADDR not aligned to 2^ARSIZE");
                end
                if (arburst == 2'b01 || arburst == 2'b11) begin
                    bytes = (arlen + 1) << arsize;
                    if ((araddr % 4096) + bytes > 4096)
                        viol("PC11: read burst crosses a 4KB boundary");
                end

                if (arq_cnt[arid_x] >= DEPTH)
                    viol("PC09: more than 4 outstanding reads for one ID");
                else begin
                    arq_len[arid_x*DEPTH +
                            ((arq_head[arid_x] + arq_cnt[arid_x]) % DEPTH)]
                        = arlen;
                    arq_cnt[arid_x] = arq_cnt[arid_x] + 1;
                end
            end

            //---------------------------------------------------------------
            // R beat: PC09
            //---------------------------------------------------------------
            if (r_hs) begin
                if (arq_cnt[rid_x] == 0)
                    violn("PC09: R beat for ID with no outstanding AR",
                          rid_x, 0);
                else begin
                    r_beat[rid_x] = r_beat[rid_x] + 1;
                    exp_len = arq_len[rid_x*DEPTH + arq_head[rid_x]] + 1;
                    if (rlast === 1'b1) begin
                        if (r_beat[rid_x] != exp_len)
                            violn("PC09: RLAST on wrong beat",
                                  r_beat[rid_x], exp_len);
                        arq_head[rid_x] = (arq_head[rid_x] + 1) % DEPTH;
                        arq_cnt[rid_x]  = arq_cnt[rid_x] - 1;
                        r_beat[rid_x]   = 0;
                    end else if (r_beat[rid_x] >= exp_len) begin
                        violn("PC09: RLAST missing on final beat",
                              r_beat[rid_x], exp_len);
                        arq_head[rid_x] = (arq_head[rid_x] + 1) % DEPTH;
                        arq_cnt[rid_x]  = arq_cnt[rid_x] - 1;
                        r_beat[rid_x]   = 0;
                    end
                end
            end
        end
    end

endmodule
