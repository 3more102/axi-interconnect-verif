`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// axi4_lite_master_bfm.v -- AXI4-Lite master bus-functional model (SPEC.md #6)
//
// Static tasks axi_write / axi_read drive one AXI4-Lite master interface.
// Each BFM instance is driven by exactly one sequential test thread, so
// static task locals are safe (SPEC.md #0). All valid/addr/data outputs are
// reg-driven with nonblocking assignments issued on posedge aclk edges.
// Every random gap is: repeat ($urandom_range(0, max_delay)) @(posedge aclk);
//
// Language subset: Verilog-2001 + $urandom_range only (dual-simulator:
// iverilog -g2012 and ModelSim ASE vlog -sv).
//-----------------------------------------------------------------------------

module axi4_lite_master_bfm (
    input  wire        aclk,
    input  wire        aresetn,
    // write address channel
    output reg  [31:0] m_axi_awaddr,
    output reg  [2:0]  m_axi_awprot,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    // write data channel
    output reg  [31:0] m_axi_wdata,
    output reg  [3:0]  m_axi_wstrb,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,
    // write response channel
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,
    // read address channel
    output reg  [31:0] m_axi_araddr,
    output reg  [2:0]  m_axi_arprot,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    // read data channel
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output reg         m_axi_rready
);

    // Maximum random inter-phase delay in cycles; TB may override
    // hierarchically (e.g. u_bfm.max_delay = 0;).
    integer max_delay;

    // Idle drive from time zero. Tasks are only called after reset
    // deassertion, so all outputs (valids = 0) stay idle through reset.
    initial begin
        max_delay     = 3;
        m_axi_awaddr  = 32'h0000_0000;
        m_axi_awprot  = 3'b000;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0000_0000;
        m_axi_wstrb   = 4'b0000;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = 32'h0000_0000;
        m_axi_arprot  = 3'b000;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;
    end

    //-------------------------------------------------------------------------
    // axi_write: fork three independent threads --
    //   (a) random delay, drive AW until awready handshake
    //   (b) random delay, drive W  until wready handshake
    //   (c) random delay, assert bready, wait bvalid && bready, capture
    //       bresp, drop bready
    // join. AWPROT driven 3'b000. Task is static (not automatic).
    //-------------------------------------------------------------------------
    task axi_write (input [31:0] addr, input [31:0] data, input [3:0] strb,
                    output [1:0] resp);
        begin
            fork
                // (a) write address phase
                begin
                    repeat ($urandom_range(0, max_delay)) @(posedge aclk);
                    m_axi_awaddr  <= addr;
                    m_axi_awprot  <= 3'b000;
                    m_axi_awvalid <= 1'b1;
                    @(posedge aclk);
                    while (!(m_axi_awvalid === 1'b1 && m_axi_awready === 1'b1))
                        @(posedge aclk);
                    m_axi_awvalid <= 1'b0;
                end
                // (b) write data phase
                begin
                    repeat ($urandom_range(0, max_delay)) @(posedge aclk);
                    m_axi_wdata  <= data;
                    m_axi_wstrb  <= strb;
                    m_axi_wvalid <= 1'b1;
                    @(posedge aclk);
                    while (!(m_axi_wvalid === 1'b1 && m_axi_wready === 1'b1))
                        @(posedge aclk);
                    m_axi_wvalid <= 1'b0;
                end
                // (c) write response phase
                begin
                    repeat ($urandom_range(0, max_delay)) @(posedge aclk);
                    m_axi_bready <= 1'b1;
                    @(posedge aclk);
                    while (!(m_axi_bvalid === 1'b1 && m_axi_bready === 1'b1))
                        @(posedge aclk);
                    resp = m_axi_bresp;
                    m_axi_bready <= 1'b0;
                end
            join
        end
    endtask

    //-------------------------------------------------------------------------
    // axi_read: random delay, drive AR until arready handshake; then random
    // delay, assert rready, capture rdata/rresp at rvalid && rready, drop
    // rready. ARPROT driven 3'b000. Task is static (not automatic).
    //-------------------------------------------------------------------------
    task axi_read (input [31:0] addr, output [31:0] data, output [1:0] resp);
        begin
            // read address phase
            repeat ($urandom_range(0, max_delay)) @(posedge aclk);
            m_axi_araddr  <= addr;
            m_axi_arprot  <= 3'b000;
            m_axi_arvalid <= 1'b1;
            @(posedge aclk);
            while (!(m_axi_arvalid === 1'b1 && m_axi_arready === 1'b1))
                @(posedge aclk);
            m_axi_arvalid <= 1'b0;
            // read data phase
            repeat ($urandom_range(0, max_delay)) @(posedge aclk);
            m_axi_rready <= 1'b1;
            @(posedge aclk);
            while (!(m_axi_rvalid === 1'b1 && m_axi_rready === 1'b1))
                @(posedge aclk);
            data = m_axi_rdata;
            resp = m_axi_rresp;
            m_axi_rready <= 1'b0;
        end
    endtask

endmodule
