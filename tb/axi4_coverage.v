`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axi4_coverage.v -- passive functional-coverage collector for one AXI4 iface
// Implements SPEC.md section 9.
//
// 35 bins, sampled at handshakes:
//    0.. 2  write burst type FIXED / INCR / WRAP
//    3.. 5  read  burst type FIXED / INCR / WRAP
//    6.. 8  write size 1B / 2B / 4B
//    9..11  read  size 1B / 2B / 4B
//   12..15  write INCR len {0, 1-3, 4-15, 16-255}
//   16..19  read  INCR len {0, 1-3, 4-15, 16-255}
//   20..23  write WRAP len {1, 3, 7, 15}
//   24..27  read  WRAP len {1, 3, 7, 15}
//   28..30  BRESP OKAY / SLVERR / DECERR
//   31..33  RRESP OKAY / SLVERR / DECERR   (sampled per beat)
//      34   a burst whose last byte lands exactly on offset 0xFFF
//
// AWBURST/ARBURST 2'b11 is counted as INCR, matching the slave's treatment
// (SPEC.md section 4). Bin 34 is evaluated for INCR bursts, the only type the
// boundary tests drive to the top of the 4 KB window.
//
// `task print_coverage;` prints the table and one aggregate COVERAGE line that
// the regression script greps.
//
// Language subset: Verilog-2001 (SPEC.md section 0).
//-----------------------------------------------------------------------------

module axi4_coverage #(
    parameter ID_WIDTH = 4,
    parameter NAME     = "CV"
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

    localparam NBINS = 35;

    integer cov [0:NBINS-1];
    reg [8*30-1:0] bin_name [0:NBINS-1];

    integer k;
    integer bytes;
    integer last_off;

    wire aw_hs = (awvalid === 1'b1) && (awready === 1'b1);
    wire b_hs  = (bvalid  === 1'b1) && (bready  === 1'b1);
    wire ar_hs = (arvalid === 1'b1) && (arready === 1'b1);
    wire r_hs  = (rvalid  === 1'b1) && (rready  === 1'b1);

    initial begin
        for (k = 0; k < NBINS; k = k + 1)
            cov[k] = 0;
        bin_name[0]  = "wr_burst_FIXED";
        bin_name[1]  = "wr_burst_INCR";
        bin_name[2]  = "wr_burst_WRAP";
        bin_name[3]  = "rd_burst_FIXED";
        bin_name[4]  = "rd_burst_INCR";
        bin_name[5]  = "rd_burst_WRAP";
        bin_name[6]  = "wr_size_1B";
        bin_name[7]  = "wr_size_2B";
        bin_name[8]  = "wr_size_4B";
        bin_name[9]  = "rd_size_1B";
        bin_name[10] = "rd_size_2B";
        bin_name[11] = "rd_size_4B";
        bin_name[12] = "wr_incr_len_0";
        bin_name[13] = "wr_incr_len_1_3";
        bin_name[14] = "wr_incr_len_4_15";
        bin_name[15] = "wr_incr_len_16_255";
        bin_name[16] = "rd_incr_len_0";
        bin_name[17] = "rd_incr_len_1_3";
        bin_name[18] = "rd_incr_len_4_15";
        bin_name[19] = "rd_incr_len_16_255";
        bin_name[20] = "wr_wrap_len_1";
        bin_name[21] = "wr_wrap_len_3";
        bin_name[22] = "wr_wrap_len_7";
        bin_name[23] = "wr_wrap_len_15";
        bin_name[24] = "rd_wrap_len_1";
        bin_name[25] = "rd_wrap_len_3";
        bin_name[26] = "rd_wrap_len_7";
        bin_name[27] = "rd_wrap_len_15";
        bin_name[28] = "bresp_OKAY";
        bin_name[29] = "bresp_SLVERR";
        bin_name[30] = "bresp_DECERR";
        bin_name[31] = "rresp_OKAY";
        bin_name[32] = "rresp_SLVERR";
        bin_name[33] = "rresp_DECERR";
        bin_name[34] = "burst_ends_at_0xFFF";
    end

    task hit;
        input integer b;
        begin
            cov[b] = cov[b] + 1;
        end
    endtask

    always @(posedge aclk) begin
        if (aresetn) begin
            //---------------- write address phase ---------------------------
            if (aw_hs) begin
                if (awburst == 2'b00)      hit(0);
                else if (awburst == 2'b10) hit(2);
                else                       hit(1);   // INCR, and 2'b11 as INCR

                if (awsize == 3'd0)      hit(6);
                else if (awsize == 3'd1) hit(7);
                else if (awsize == 3'd2) hit(8);

                if (awburst == 2'b01 || awburst == 2'b11) begin
                    if (awlen == 8'd0)       hit(12);
                    else if (awlen <= 8'd3)  hit(13);
                    else if (awlen <= 8'd15) hit(14);
                    else                     hit(15);

                    bytes    = (awlen + 1) << awsize;
                    last_off = (awaddr % 4096) + bytes - 1;
                    if (last_off == 4095) hit(34);
                end else if (awburst == 2'b10) begin
                    if (awlen == 8'd1)       hit(20);
                    else if (awlen == 8'd3)  hit(21);
                    else if (awlen == 8'd7)  hit(22);
                    else if (awlen == 8'd15) hit(23);
                end
            end

            //---------------- read address phase ----------------------------
            if (ar_hs) begin
                if (arburst == 2'b00)      hit(3);
                else if (arburst == 2'b10) hit(5);
                else                       hit(4);

                if (arsize == 3'd0)      hit(9);
                else if (arsize == 3'd1) hit(10);
                else if (arsize == 3'd2) hit(11);

                if (arburst == 2'b01 || arburst == 2'b11) begin
                    if (arlen == 8'd0)       hit(16);
                    else if (arlen <= 8'd3)  hit(17);
                    else if (arlen <= 8'd15) hit(18);
                    else                     hit(19);

                    bytes    = (arlen + 1) << arsize;
                    last_off = (araddr % 4096) + bytes - 1;
                    if (last_off == 4095) hit(34);
                end else if (arburst == 2'b10) begin
                    if (arlen == 8'd1)       hit(24);
                    else if (arlen == 8'd3)  hit(25);
                    else if (arlen == 8'd7)  hit(26);
                    else if (arlen == 8'd15) hit(27);
                end
            end

            //---------------- response phases -------------------------------
            if (b_hs) begin
                if (bresp == 2'b00)      hit(28);
                else if (bresp == 2'b10) hit(29);
                else if (bresp == 2'b11) hit(30);
            end
            if (r_hs) begin
                if (rresp == 2'b00)      hit(31);
                else if (rresp == 2'b10) hit(32);
                else if (rresp == 2'b11) hit(33);
            end
        end
    end

    //-------------------------------------------------------------------------
    // Coverage report. The regression script greps the final COVERAGE line.
    //-------------------------------------------------------------------------
    task print_coverage;
        integer i;
        integer nhit;
        begin
            nhit = 0;
            $display("[%0s] ---- functional coverage ----", NAME);
            for (i = 0; i < NBINS; i = i + 1) begin
                $display("[%0s]   %0s = %0d", NAME, bin_name[i], cov[i]);
                if (cov[i] > 0)
                    nhit = nhit + 1;
            end
            $display("COVERAGE %0s: %0d/%0d bins hit (%0d%%)",
                     NAME, nhit, NBINS, (nhit * 100) / NBINS);
        end
    endtask

endmodule
