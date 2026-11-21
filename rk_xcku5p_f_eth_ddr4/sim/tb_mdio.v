// mdio_rw frame check: a write must drive all 64 bits (preamble, 01, 01, PHYAD, REGAD, 10, data);
// a read must drive the first 46 bits (preamble, 01, 10, PHYAD, REGAD) and then release MDIO,
// and return the 16 bits the PHY puts on the line after the turnaround.
`timescale 1ns/1ps
`default_nettype none
module tb_mdio;
  reg clk = 0;
  always #5 clk = ~clk;  // 100 MHz
  reg start = 0, wr = 0;
  reg [4:0] phyad = 0, regad = 0;
  reg [15:0] wdata = 0;
  wire busy, done, mdc, mo, moe;
  wire [15:0] data;
  reg [15:0] phy_val = 16'hA5C3;
  integer nb = 0, nd = 0;            // bits seen, bits driven by the master
  reg [63:0] seen = 0;
  // PHY model: after the master releases MDIO (TA bit 1) it drives 0, then phy_val, MSB first
  wire phy_bit = (nb <= 47) ? 1'b0 : phy_val[15 - (nb - 48)];
  wire mdio = moe ? mo : (nb >= 46 && nb < 64 ? phy_bit : 1'b1);
  mdio_rw #(.CLK_HZ(100_000_000), .MDC_HZ(2_500_000)) dut (
    .clk(clk), .start(start), .wr(wr), .phyad(phyad), .regad(regad), .wdata(wdata),
    .busy(busy), .done(done), .data(data), .mdc(mdc), .mdio_o(mo), .mdio_oe(moe), .mdio_i(mdio));
  always @(posedge mdc) begin
    seen = {seen[62:0], mdio};
    if (moe) nd = nd + 1;
    #1 nb = nb + 1;
  end
  integer errors = 0;
  task xfer(input w, input [4:0] r, input [15:0] d);
    begin
      @(posedge clk); nb = 0; nd = 0; wr <= w; regad <= r; wdata <= d; start <= 1;
      @(posedge clk); start <= 0;
      wait (done); @(posedge clk);
    end
  endtask
  initial begin
    xfer(1, 5'd9, 16'h0000);
    $display("write reg 9: frame %016x, driven %0d", seen, nd);
    if (seen !== {32'hFFFFFFFF, 2'b01, 2'b01, 5'd0, 5'd9, 2'b10, 16'h0000} || nd != 64) errors = errors + 1;
    xfer(1, 5'd0, 16'h1200);
    $display("write reg 0: frame %016x, driven %0d", seen, nd);
    if (seen !== {32'hFFFFFFFF, 2'b01, 2'b01, 5'd0, 5'd0, 2'b10, 16'h1200} || nd != 64) errors = errors + 1;
    xfer(0, 5'd1, 16'h0000);
    $display("read reg 1: data %04x, driven %0d", data, nd);
    if (data !== phy_val || nd != 46) errors = errors + 1;
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
endmodule
`default_nettype wire
