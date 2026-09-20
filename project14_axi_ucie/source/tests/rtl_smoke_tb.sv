`timescale 1ns/1ps

module rtl_smoke_tb;
  import axi_ucie_pkg::*;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic [31:0] awaddr,wdata,araddr,rdata;
  logic [3:0] wstrb;
  logic awvalid,awready,wvalid,wready,bvalid,bready,arvalid,arready,rvalid,rready;
  logic [1:0] bresp,rresp;
  logic [127:0] tx_flit,rx_flit;
  logic tx_valid,tx_ready,rx_valid,rx_ready,protocol_error;

  axi_ucie_bridge dut(
    .aclk(clk),.aresetn(rst_n),.s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
    .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),.s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
    .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
    .ucie_tx_flit(tx_flit),.ucie_tx_valid(tx_valid),.ucie_tx_ready(tx_ready),.ucie_rx_flit(rx_flit),.ucie_rx_valid(rx_valid),.ucie_rx_ready(rx_ready),.protocol_error(protocol_error));

  ucie_responder_model remote_ep(.clk(clk),.rst_n(rst_n),.rx_flit(tx_flit),.rx_valid(tx_valid),.rx_ready(tx_ready),.tx_flit(rx_flit),.tx_valid(rx_valid),.tx_ready(rx_ready));

  task automatic axi_write(input logic[31:0] addr,input logic[31:0] data,input logic[3:0] strb,input logic[1:0] exp_resp,input integer aw_delay,input integer w_delay,input integer bready_delay);
    fork
      begin repeat(aw_delay) @(posedge clk); awaddr<=addr; awvalid<=1; do @(posedge clk); while(!awready); awvalid<=0; end
      begin repeat(w_delay) @(posedge clk); wdata<=data; wstrb<=strb; wvalid<=1; do @(posedge clk); while(!wready); wvalid<=0; end
    join
    repeat(bready_delay) @(posedge clk); bready<=1; do @(posedge clk); while(!bvalid);
    if(bresp!==exp_resp) begin $display("FAIL write addr=%08x exp_resp=%0b got=%0b",addr,exp_resp,bresp); $fatal(1); end
    @(posedge clk); bready<=0;
  endtask

  task automatic axi_read(input logic[31:0] addr,input logic[31:0] exp_data,input logic[1:0] exp_resp,input integer ar_delay,input integer rready_delay,input bit check_data);
    repeat(ar_delay) @(posedge clk); araddr<=addr; arvalid<=1; do @(posedge clk); while(!arready); arvalid<=0;
    repeat(rready_delay) @(posedge clk); rready<=1; do @(posedge clk); while(!rvalid);
    if(rresp!==exp_resp) begin $display("FAIL read addr=%08x exp_resp=%0b got=%0b",addr,exp_resp,rresp); $fatal(1); end
    if(check_data && rdata!==exp_data) begin $display("FAIL read addr=%08x exp_data=%08x got=%08x",addr,exp_data,rdata); $fatal(1); end
    @(posedge clk); rready<=0;
  endtask

  initial begin
    awaddr='0;awvalid=0;wdata='0;wstrb='0;wvalid=0;bready=0;araddr='0;arvalid=0;rready=0;
    repeat(5) @(posedge clk); rst_n<=1; repeat(2) @(posedge clk);
    axi_write(32'h00000010,32'h11223344,4'hF,2'b00,0,3,2);
    axi_read(32'h00000010,32'h11223344,2'b00,1,2,1);
    axi_write(32'h00000010,32'hAABBCCDD,4'b0101,2'b00,3,0,1);
    axi_read(32'h00000010,32'h11BB33DD,2'b00,0,3,1);
    axi_write(32'hF0000010,32'hDEADBEEF,4'hF,2'b10,1,2,0);
    axi_read(32'hF0000010,32'h0,2'b10,2,1,0);
    axi_read(32'h00000010,32'h11BB33DD,2'b00,0,0,1);
    if(protocol_error!==0) begin $display("FAIL protocol_error unexpectedly asserted"); $fatal(1); end
    $display("RTL_SMOKE_PASS"); $finish;
  end
  initial begin #200000; $display("FAIL timeout"); $fatal(1); end
endmodule
