// mdio_rd against a minimal clause 22 PHY model that answers reads at address 1 with {11'h0, regad, regad}.
`timescale 1ns/1ps
`default_nettype none
module tb_mdio;
  reg clk = 0;
  always #5 clk = ~clk;  // 100 MHz
  reg start = 0;
  reg [4:0] phyad = 1, regad = 0;
  wire busy, done, mdc, mo, moe;
  wire [15:0] data;
  wire mdio;
  reg phy_drive = 0, phy_bit = 1;
  assign mdio = moe ? mo : (phy_drive ? phy_bit : 1'b1);  // pull-up
  mdio_rd #(.CLK_HZ(100_000_000), .MDC_HZ(2_500_000)) dut (
    .clk(clk), .start(start), .phyad(phyad), .regad(regad), .busy(busy), .done(done),
    .data(data), .mdc(mdc), .mdio_o(mo), .mdio_oe(moe), .mdio_i(mdio));
  // PHY model: shift in on rising MDC, drive out after rising MDC
  reg [13:0] hdr = 0;
  integer cnt = 0, ones = 0;
  reg [15:0] resp;
  always @(posedge mdc) begin
    if (cnt == 0) begin
      if (mdio) ones = ones + 1;
      else if (ones >= 32) begin cnt = 1; hdr = 14'b0; hdr[0] = 0; end
      else ones = 0;
    end else if (cnt < 14) begin
      hdr = {hdr[12:0], mdio}; cnt = cnt + 1;
      if (cnt == 14) begin
        // hdr = ST[0] OP PHYAD REGAD (13 bits after the first ST bit)
        resp = {11'h0, hdr[4:0]} | {hdr[4:0], 11'h0};
      end
    end else if (cnt == 14) begin
      #100 phy_drive = (hdr[9:5] == 5'd1); phy_bit = 0; cnt = 15;  // after TA bit 1: drive TA bit 2 = 0
    end else if (cnt < 31) begin
      #100 phy_bit = resp[15 - (cnt - 15)]; cnt = cnt + 1;
    end else begin
      #100 phy_drive = 0; cnt = 0; ones = 0;
    end
  end
  integer errors = 0;
  task rd(input [4:0] a, input [4:0] r, input [15:0] exp);
    begin
      @(posedge clk); phyad <= a; regad <= r; start <= 1; @(posedge clk); start <= 0;
      wait (done); @(posedge clk);
      $display("read ad=%0d reg=%0d -> %04x (expect %04x)", a, r, data, exp);
      if (data !== exp) errors = errors + 1;
      repeat (50) @(posedge clk);
    end
  endtask
  initial begin
    rd(1, 5'h02, 16'h1002);
    rd(1, 5'h1f, 16'hf81f);
    rd(3, 5'h02, 16'hffff);
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
endmodule
`default_nettype wire
