// Arty A7-35T starter top level at a scaled clock (CLK_HZ = 10 x BAUD, so a "second" is
// 1.152 M cycles). Decodes the UART and checks the heartbeat lines, the BTN0 hold and the
// active-low reset, and the LED counter bit select for every switch setting.
`timescale 1ns/1ps
`default_nettype none
module tb_top;
  localparam integer BAUD   = 115_200;
  localparam integer CLK_HZ = 10 * BAUD;
  localparam integer BIT    = CLK_HZ / BAUD;    // clocks per UART bit
  reg clk = 0;
  always #5 clk = ~clk;
  reg ck_rst = 1;
  reg [3:0] sw = 0, btn = 0;
  wire [3:0] led, led_r, led_g, led_b;
  wire txd;
  top #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
    .CLK100MHZ(clk), .ck_rst(ck_rst), .sw(sw), .btn(btn), .led(led),
    .led_r(led_r), .led_g(led_g), .led_b(led_b), .uart_rxd_out(txd));

  // ---------------------------------------------------------------- UART receiver
  reg [8*32-1:0] line = 0;
  integer nline = 0, nchar = 0, errors = 0, k;
  reg [7:0] ch;
  always begin
    @(negedge txd);
    repeat (BIT / 2) @(posedge clk);
    if (txd) begin $display("FAIL false start bit"); errors = errors + 1; end
    for (k = 0; k < 8; k = k + 1) begin repeat (BIT) @(posedge clk); ch[k] = txd; end
    repeat (BIT) @(posedge clk);
    if (!txd) begin $display("FAIL framing error"); errors = errors + 1; end
    line = {line[8*31-1:0], ch};
    nchar = nchar + 1;
    if (ch == 8'h0a) begin
      nline = nline + 1;
      $display("%0t uart: %0s", $time, line[8*21-1:16]);
      if (nchar != 21 || line[8*21-1:0] != {"arty a7 up ", hex8(nline), 8'h0d, 8'h0a}) begin
        $display("FAIL line %0d", nline); errors = errors + 1;
      end
      nchar = 0;
    end
  end
  function [63:0] hex8(input [31:0] v);
    integer i;
    reg [3:0] n;
    begin
      for (i = 0; i < 8; i = i + 1) begin
        n = v[4 * i +: 4];
        hex8[8 * i +: 8] = (n < 10) ? 8'h30 + n : 8'h57 + n;
      end
    end
  endfunction

  // ---------------------------------------------------------------- stimulus
  reg [31:0] c0;
  integer s;
  initial begin
    repeat (10) @(posedge clk);   // past the power-up reset synchroniser
    // LED bit select: sw 0..3 -> cnt[29:26] .. cnt[26:23]
    for (s = 0; s < 4; s = s + 1) begin
      sw = s;
      repeat (3) @(negedge clk);
      // led_q took cnt one edge ago, before cnt's own increment on that edge
      if (led !== (((dut.cnt - 32'd1) >> (26 - s)) & 32'hF)) begin
        $display("FAIL led sw=%0d", s); errors = errors + 1;
      end
    end
    // hold: cnt must not move while BTN0 is down (after the 4-flop synchroniser)
    btn[0] = 1;
    repeat (10) @(posedge clk);
    c0 = dut.cnt;
    repeat (1000) @(posedge clk);
    if (dut.cnt !== c0) begin $display("FAIL hold"); errors = errors + 1; end
    btn[0] = 0;
    repeat (10) @(posedge clk);
    if (dut.cnt == c0) begin $display("FAIL release"); errors = errors + 1; end
    // reset (active low) clears it
    ck_rst = 0;
    repeat (5) @(posedge clk);
    if (dut.cnt !== 0) begin $display("FAIL reset"); errors = errors + 1; end
    ck_rst = 1;
    // three heartbeat lines
    wait (nline == 3);
    repeat (BIT) @(posedge clk);
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
  initial begin
    #((4 * CLK_HZ) * 10.0);
    $display("FAIL timeout, %0d lines", nline);
    $finish;
  end
endmodule
`default_nettype wire
