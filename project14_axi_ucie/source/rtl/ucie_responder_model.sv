`timescale 1ns/1ps

module ucie_responder_model #(
  parameter int FLIT_W = 128,
  parameter int MEM_WORDS = 1024
)(
  input logic clk, input logic rst_n,
  input logic [FLIT_W-1:0] rx_flit, input logic rx_valid, output logic rx_ready,
  output logic [FLIT_W-1:0] tx_flit, output logic tx_valid, input logic tx_ready
);
  import axi_ucie_pkg::*;
  logic [31:0] mem [0:MEM_WORDS-1];
  logic [FLIT_W-1:0] rsp_q;
  logic rsp_pending, ready_q;
  integer stall_pct, seed, i;
  logic [31:0] prng_q;

  function automatic logic [31:0] xorshift32(input logic [31:0] x);
    logic [31:0] y;
    begin
      y = (x == 32'h0) ? 32'h1 : x;
      y ^= (y << 13); y ^= (y >> 17); y ^= (y << 5);
      return y;
    end
  endfunction

  initial begin
    stall_pct = 0; seed = 32'h1a2b3c4d;
    void'($value$plusargs("STALL_PCT=%d", stall_pct));
    void'($value$plusargs("SEED=%d", seed));
    if (stall_pct < 0) stall_pct = 0;
    if (stall_pct > 100) stall_pct = 100;
    for (i = 0; i < MEM_WORDS; i++) mem[i] = 32'h1000_0000 + i;
  end

  assign tx_flit = rsp_q;
  assign tx_valid = rsp_pending;
  assign rx_ready = !rsp_pending && ready_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_pending <= 1'b0; rsp_q <= '0; ready_q <= 1'b1;
      prng_q <= (seed == 0) ? 32'h1 : seed[31:0];
    end else begin
      if (!rsp_pending) begin
        prng_q <= xorshift32(prng_q);
        ready_q <= ((xorshift32(prng_q) % 100) >= stall_pct);
      end else ready_q <= 1'b0;

      if (tx_valid && tx_ready) rsp_pending <= 1'b0;
      if (rx_valid && rx_ready) begin
        logic [3:0] op;
        logic [31:0] addr, data;
        logic [3:0] strb;
        logic [7:0] tag;
        logic [1:0] resp;
        int unsigned idx;
        op=rx_flit[127:124]; addr=rx_flit[123:92]; data=rx_flit[91:60]; strb=rx_flit[59:56]; tag=rx_flit[53:46];
        idx=addr[11:2]; resp=(addr[31:28] == 4'hF) ? 2'b10 : 2'b00;
        if (op == UOP_WR_REQ) begin
          if (resp == 2'b00) begin
            if (strb[0]) mem[idx][7:0] <= data[7:0];
            if (strb[1]) mem[idx][15:8] <= data[15:8];
            if (strb[2]) mem[idx][23:16] <= data[23:16];
            if (strb[3]) mem[idx][31:24] <= data[31:24];
          end
          rsp_q <= pack_rsp(UOP_WR_RSP, '0, resp, tag); rsp_pending <= 1'b1;
        end else if (op == UOP_RD_REQ) begin
          rsp_q <= pack_rsp(UOP_RD_RSP, mem[idx], resp, tag); rsp_pending <= 1'b1;
        end
      end
    end
  end
endmodule
