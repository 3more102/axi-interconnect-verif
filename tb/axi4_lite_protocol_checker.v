`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axi4_lite_protocol_checker.v -- passive AXI4-Lite legality monitor
// Implements SPEC.md section 8 (lite half).
//
// Instantiated on one AXI4-Lite interface; every port is an input. Zero
// tolerance: any violation increments the public `error_count`, which the TB
// folds into its PASS/FAIL verdict.
//
//   PC01 AW  |  PC02 W  |  PC03 AR  |  PC04 B  |  PC05 R
//        once VALID is high it must stay high, and the payload must be
//        stable, until the READY handshake completes.
//   PC06 no X/Z on any VALID once reset has deasserted.
//   PC07 no X/Z on a channel's payload while its VALID is high.
//   PC12 all VALIDs low while aresetn == 0 (sampled on posedge).
//
// Language subset: Verilog-2001 (SPEC.md section 0).
//-----------------------------------------------------------------------------

module axi4_lite_protocol_checker #(
    parameter NAME = "PC"
)(
    input wire        aclk,
    input wire        aresetn,
    input wire [31:0] awaddr,
    input wire [2:0]  awprot,
    input wire        awvalid,
    input wire        awready,
    input wire [31:0] wdata,
    input wire [3:0]  wstrb,
    input wire        wvalid,
    input wire        wready,
    input wire [1:0]  bresp,
    input wire        bvalid,
    input wire        bready,
    input wire [31:0] araddr,
    input wire [2:0]  arprot,
    input wire        arvalid,
    input wire        arready,
    input wire [31:0] rdata,
    input wire [1:0]  rresp,
    input wire        rvalid,
    input wire        rready
);

    integer error_count;

    // previous-cycle history, used for the stability checks
    reg        aw_v_q, aw_r_q;
    reg [31:0] aw_addr_q;
    reg [2:0]  aw_prot_q;
    reg        w_v_q, w_r_q;
    reg [31:0] w_data_q;
    reg [3:0]  w_strb_q;
    reg        ar_v_q, ar_r_q;
    reg [31:0] ar_addr_q;
    reg [2:0]  ar_prot_q;
    reg        b_v_q, b_r_q;
    reg [1:0]  b_resp_q;
    reg        r_v_q, r_r_q;
    reg [31:0] r_data_q;
    reg [1:0]  r_resp_q;

    reg        seen_reset;      // aresetn has been low at least once
    reg        aresetn_q;       // aresetn as sampled at the previous posedge

    initial begin
        error_count = 0;
        aresetn_q = 1'bx;
        aw_v_q = 1'b0; aw_r_q = 1'b0;
        w_v_q  = 1'b0; w_r_q  = 1'b0;
        ar_v_q = 1'b0; ar_r_q = 1'b0;
        b_v_q  = 1'b0; b_r_q  = 1'b0;
        r_v_q  = 1'b0; r_r_q  = 1'b0;
        seen_reset = 1'b0;
    end

    // A 1-bit signal that is neither 0 nor 1 is X or Z.
    function is_xz1;
        input v;
        begin
            is_xz1 = (v !== 1'b0) && (v !== 1'b1);
        end
    endfunction

    task viol;
        input [8*48-1:0] msg;
        begin
            $display("[%0s] %0t %0s", NAME, $time, msg);
            error_count = error_count + 1;
        end
    endtask

    always @(posedge aclk) begin
        aresetn_q <= aresetn;
        if (!aresetn) begin
            seen_reset <= 1'b1;
            // ---- PC12: no VALID may be asserted while in reset --------------
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
            // ---- PC06: VALIDs must be driven to a known value ---------------
            if (seen_reset) begin
                if (is_xz1(awvalid)) viol("PC06: AWVALID is X/Z");
                if (is_xz1(wvalid))  viol("PC06: WVALID is X/Z");
                if (is_xz1(bvalid))  viol("PC06: BVALID is X/Z");
                if (is_xz1(arvalid)) viol("PC06: ARVALID is X/Z");
                if (is_xz1(rvalid))  viol("PC06: RVALID is X/Z");
            end

            // ---- PC07: payload must be known while VALID is high ------------
            if (awvalid === 1'b1 && (^{awaddr, awprot} === 1'bx))
                viol("PC07: AW payload has X/Z while AWVALID high");
            if (wvalid === 1'b1 && (^{wdata, wstrb} === 1'bx))
                viol("PC07: W payload has X/Z while WVALID high");
            if (bvalid === 1'b1 && (^bresp === 1'bx))
                viol("PC07: B payload has X/Z while BVALID high");
            if (arvalid === 1'b1 && (^{araddr, arprot} === 1'bx))
                viol("PC07: AR payload has X/Z while ARVALID high");
            if (rvalid === 1'b1 && (^{rdata, rresp} === 1'bx))
                viol("PC07: R payload has X/Z while RVALID high");

            // ---- PC01..PC05: VALID/payload stability across a stall ---------
            // "stalled last cycle" == VALID was high and READY was not.
            if (aw_v_q === 1'b1 && aw_r_q !== 1'b1) begin
                if (awvalid !== 1'b1)
                    viol("PC01: AWVALID deasserted before AWREADY");
                else if (awaddr !== aw_addr_q || awprot !== aw_prot_q)
                    viol("PC01: AW payload changed while stalled");
            end
            if (w_v_q === 1'b1 && w_r_q !== 1'b1) begin
                if (wvalid !== 1'b1)
                    viol("PC02: WVALID deasserted before WREADY");
                else if (wdata !== w_data_q || wstrb !== w_strb_q)
                    viol("PC02: W payload changed while stalled");
            end
            if (ar_v_q === 1'b1 && ar_r_q !== 1'b1) begin
                if (arvalid !== 1'b1)
                    viol("PC03: ARVALID deasserted before ARREADY");
                else if (araddr !== ar_addr_q || arprot !== ar_prot_q)
                    viol("PC03: AR payload changed while stalled");
            end
            if (b_v_q === 1'b1 && b_r_q !== 1'b1) begin
                if (bvalid !== 1'b1)
                    viol("PC04: BVALID deasserted before BREADY");
                else if (bresp !== b_resp_q)
                    viol("PC04: B payload changed while stalled");
            end
            if (r_v_q === 1'b1 && r_r_q !== 1'b1) begin
                if (rvalid !== 1'b1)
                    viol("PC05: RVALID deasserted before RREADY");
                else if (rdata !== r_data_q || rresp !== r_resp_q)
                    viol("PC05: R payload changed while stalled");
            end
        end

        // ---- history update (cleared in reset so no stale stall is seen) ----
        if (!aresetn) begin
            aw_v_q <= 1'b0; aw_r_q <= 1'b0;
            w_v_q  <= 1'b0; w_r_q  <= 1'b0;
            ar_v_q <= 1'b0; ar_r_q <= 1'b0;
            b_v_q  <= 1'b0; b_r_q  <= 1'b0;
            r_v_q  <= 1'b0; r_r_q  <= 1'b0;
        end else begin
            aw_v_q <= awvalid; aw_r_q <= awready;
            w_v_q  <= wvalid;  w_r_q  <= wready;
            ar_v_q <= arvalid; ar_r_q <= arready;
            b_v_q  <= bvalid;  b_r_q  <= bready;
            r_v_q  <= rvalid;  r_r_q  <= rready;
        end
        aw_addr_q <= awaddr; aw_prot_q <= awprot;
        w_data_q  <= wdata;  w_strb_q  <= wstrb;
        ar_addr_q <= araddr; ar_prot_q <= arprot;
        b_resp_q  <= bresp;
        r_data_q  <= rdata;  r_resp_q  <= rresp;
    end

endmodule
