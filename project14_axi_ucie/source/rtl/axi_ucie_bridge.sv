`timescale 1ns/1ps

module axi_ucie_bridge #(
  parameter int ADDR_W = 32,
  parameter int DATA_W = 32,
  parameter int FLIT_W = 128
)(
  input  logic                  aclk,
  input  logic                  aresetn,

  input  logic [ADDR_W-1:0]     s_axi_awaddr,
  input  logic                  s_axi_awvalid,
  output logic                  s_axi_awready,
  input  logic [DATA_W-1:0]     s_axi_wdata,
  input  logic [(DATA_W/8)-1:0] s_axi_wstrb,
  input  logic                  s_axi_wvalid,
  output logic                  s_axi_wready,
  output logic [1:0]            s_axi_bresp,
  output logic                  s_axi_bvalid,
  input  logic                  s_axi_bready,
  input  logic [ADDR_W-1:0]     s_axi_araddr,
  input  logic                  s_axi_arvalid,
  output logic                  s_axi_arready,
  output logic [DATA_W-1:0]     s_axi_rdata,
  output logic [1:0]            s_axi_rresp,
  output logic                  s_axi_rvalid,
  input  logic                  s_axi_rready,
  output logic [FLIT_W-1:0]     ucie_tx_flit,
  output logic                  ucie_tx_valid,
  input  logic                  ucie_tx_ready,
  input  logic [FLIT_W-1:0]     ucie_rx_flit,
  input  logic                  ucie_rx_valid,
  output logic                  ucie_rx_ready,
  output logic                  protocol_error
);
  import axi_ucie_pkg::*;

  typedef enum logic [2:0] { ST_IDLE, ST_SEND_WR, ST_WAIT_WR, ST_SEND_RD, ST_WAIT_RD, ST_BRESP, ST_RRESP } state_e;
  state_e state;
  logic aw_hold, w_hold, ar_hold;
  logic [ADDR_W-1:0] awaddr_q, araddr_q;
  logic [DATA_W-1:0] wdata_q;
  logic [(DATA_W/8)-1:0] wstrb_q;
  logic [7:0] tag_ctr, active_tag;
  logic [3:0] rx_opcode;
  logic [7:0] rx_tag;

  assign rx_opcode = ucie_rx_flit[127:124];
  assign rx_tag    = ucie_rx_flit[53:46];

  always_comb begin
    s_axi_awready = (state == ST_IDLE) && !aw_hold;
    s_axi_wready  = (state == ST_IDLE) && !w_hold;
    s_axi_arready = (state == ST_IDLE) && !ar_hold;
    ucie_tx_valid = 1'b0;
    ucie_tx_flit  = '0;
    ucie_rx_ready = 1'b0;
    case (state)
      ST_SEND_WR: begin
        ucie_tx_valid = 1'b1;
        ucie_tx_flit  = pack_req(UOP_WR_REQ, awaddr_q, wdata_q, wstrb_q, active_tag);
      end
      ST_WAIT_WR: ucie_rx_ready = 1'b1;
      ST_SEND_RD: begin
        ucie_tx_valid = 1'b1;
        ucie_tx_flit  = pack_req(UOP_RD_REQ, araddr_q, '0, '0, active_tag);
      end
      ST_WAIT_RD: ucie_rx_ready = 1'b1;
      default: ;
    endcase
  end

  always_ff @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      state <= ST_IDLE;
      aw_hold <= 1'b0; w_hold <= 1'b0; ar_hold <= 1'b0;
      awaddr_q <= '0; araddr_q <= '0; wdata_q <= '0; wstrb_q <= '0;
      tag_ctr <= '0; active_tag <= '0;
      s_axi_bresp <= 2'b00; s_axi_bvalid <= 1'b0;
      s_axi_rdata <= '0; s_axi_rresp <= 2'b00; s_axi_rvalid <= 1'b0;
      protocol_error <= 1'b0;
    end else begin
      if (s_axi_awready && s_axi_awvalid) begin awaddr_q <= s_axi_awaddr; aw_hold <= 1'b1; end
      if (s_axi_wready && s_axi_wvalid) begin wdata_q <= s_axi_wdata; wstrb_q <= s_axi_wstrb; w_hold <= 1'b1; end
      if (s_axi_arready && s_axi_arvalid) begin araddr_q <= s_axi_araddr; ar_hold <= 1'b1; end

      case (state)
        ST_IDLE: begin
          if (aw_hold && w_hold) begin active_tag <= tag_ctr; tag_ctr <= tag_ctr + 8'd1; state <= ST_SEND_WR; end
          else if (ar_hold) begin active_tag <= tag_ctr; tag_ctr <= tag_ctr + 8'd1; state <= ST_SEND_RD; end
        end
        ST_SEND_WR: if (ucie_tx_valid && ucie_tx_ready) begin aw_hold <= 1'b0; w_hold <= 1'b0; state <= ST_WAIT_WR; end
        ST_WAIT_WR: if (ucie_rx_valid && ucie_rx_ready) begin
          if ((rx_opcode != UOP_WR_RSP) || (rx_tag != active_tag)) protocol_error <= 1'b1;
          s_axi_bresp <= ucie_rx_flit[55:54]; s_axi_bvalid <= 1'b1; state <= ST_BRESP;
        end
        ST_BRESP: if (s_axi_bvalid && s_axi_bready) begin s_axi_bvalid <= 1'b0; state <= ST_IDLE; end
        ST_SEND_RD: if (ucie_tx_valid && ucie_tx_ready) begin ar_hold <= 1'b0; state <= ST_WAIT_RD; end
        ST_WAIT_RD: if (ucie_rx_valid && ucie_rx_ready) begin
          if ((rx_opcode != UOP_RD_RSP) || (rx_tag != active_tag)) protocol_error <= 1'b1;
          s_axi_rdata <= ucie_rx_flit[91:60]; s_axi_rresp <= ucie_rx_flit[55:54]; s_axi_rvalid <= 1'b1; state <= ST_RRESP;
        end
        ST_RRESP: if (s_axi_rvalid && s_axi_rready) begin s_axi_rvalid <= 1'b0; state <= ST_IDLE; end
        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
