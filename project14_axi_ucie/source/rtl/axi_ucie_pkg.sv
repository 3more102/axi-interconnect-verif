package axi_ucie_pkg;
  localparam int FLIT_W = 128;

  typedef enum logic [3:0] {
    UOP_WR_REQ = 4'h1,
    UOP_RD_REQ = 4'h2,
    UOP_WR_RSP = 4'h9,
    UOP_RD_RSP = 4'hA
  } ucie_opcode_e;

  function automatic logic [FLIT_W-1:0] pack_req(
      input ucie_opcode_e op,
      input logic [31:0] addr,
      input logic [31:0] data,
      input logic [3:0]  strb,
      input logic [7:0]  tag
  );
    logic [FLIT_W-1:0] f;
    f = '0;
    f[127:124] = op;
    f[123:92]  = addr;
    f[91:60]   = data;
    f[59:56]   = strb;
    f[53:46]   = tag;
    return f;
  endfunction

  function automatic logic [FLIT_W-1:0] pack_rsp(
      input ucie_opcode_e op,
      input logic [31:0] data,
      input logic [1:0]  resp,
      input logic [7:0]  tag
  );
    logic [FLIT_W-1:0] f;
    f = '0;
    f[127:124] = op;
    f[91:60]   = data;
    f[55:54]   = resp;
    f[53:46]   = tag;
    return f;
  endfunction

endpackage
