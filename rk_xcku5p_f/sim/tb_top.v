// RK-XCKU5P-F starter top level at a scaled clock (CLK_HZ = 10 x BAUD, so a "second" is
// 1.152 M cycles), with the UNISIM SYSMONE4 model reading 45.0 C from design.txt (sim.ps1 writes it).
// Decodes the UART and checks every heartbeat line: seconds, speed, keys and temperature.
// KEY1 is tapped once (speed 0 -> 1), KEY2 is held over the second tick, KEY3 clears the counter,
// KEY4 lights all LEDs.
`timescale 1ns/1ps
`default_nettype none
module tb_top;
  localparam integer BAUD   = 115_200;
  localparam integer CLK_HZ = 10 * BAUD;
  localparam integer BIT    = CLK_HZ / BAUD;
  localparam integer MS     = CLK_HZ / 1000;    // the design's key sample period
  reg clk = 0;
  always #5 clk = ~clk;
  reg [3:0] key_n = 4'hF;
  wire [3:0] led;
  wire txd;
  top #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
    .sys_clk_p(clk), .sys_clk_n(~clk), .key_n(key_n), .led(led), .uart_tx(txd));

  // ---------------------------------------------------------------- UART receiver
  localparam integer LEN = 48;
  reg [8*LEN-1:0] line = 0;
  integer nline = 0, nchar = 0, errors = 0, k;
  reg [7:0] ch;
  reg [7:0] exp_speed [1:3];
  reg [7:0] exp_keys  [1:3];
  initial begin
    exp_speed[1] = "1";  exp_keys[1] = "0";   // KEY1 tapped before the first tick
    exp_speed[2] = "1";  exp_keys[2] = "2";   // KEY2 held over the second tick
    exp_speed[3] = "1";  exp_keys[3] = "0";
  end
  always begin
    @(negedge txd);
    repeat (BIT / 2) @(posedge clk);
    for (k = 0; k < 8; k = k + 1) begin repeat (BIT) @(posedge clk); ch[k] = txd; end
    repeat (BIT) @(posedge clk);
    if (!txd) begin $display("FAIL framing error"); errors = errors + 1; end
    line = {line[8*(LEN-1)-1:0], ch};
    nchar = nchar + 1;
    if (ch == 8'h0a) begin
      nline = nline + 1;
      $display("%0t uart: %0s", $time, line[8*LEN-1:16]);
      // "ku5p-f up SSSSSSSS speed N keys K temp +TTT.TC\r\n"; temperature 44.5 .. 45.5 C
      if (nchar != LEN ||
          line[8*LEN-1 -: 8*18] != {"ku5p-f up ", hex8(nline)} ||
          line[8*30-1 -: 8*15] != {" speed ", exp_speed[nline], " keys ", exp_keys[nline]} ||
          line[8*15-1 -: 8*8] != " temp +0" ||
          !(line[8*7-1 -: 8*4] == "44.5" || line[8*7-1 -: 8*4] == "44.6" || line[8*7-1 -: 8*4] == "44.7" ||
            line[8*7-1 -: 8*4] == "44.8" || line[8*7-1 -: 8*4] == "44.9" || line[8*7-1 -: 16] == "45") ||
          line[8*3-1:0] != {"C", 8'h0d, 8'h0a}) begin
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
  initial begin
    repeat (2 * MS) @(posedge clk);
    key_n[0] = 0;  repeat (5 * MS) @(posedge clk);  key_n[0] = 1;      // KEY1 tap
    repeat (5 * MS) @(posedge clk);
    if (dut.speed !== 2'd1) begin $display("FAIL speed after KEY1"); errors = errors + 1; end
    key_n[2] = 0;  repeat (5 * MS) @(posedge clk);                      // KEY3 clears
    if (dut.cnt !== 0) begin $display("FAIL KEY3 clear"); errors = errors + 1; end
    key_n[2] = 1;
    key_n[3] = 0;  repeat (5 * MS) @(posedge clk);                      // KEY4 lamp test
    if (led !== 4'hF) begin $display("FAIL KEY4 lamp test"); errors = errors + 1; end
    key_n[3] = 1;
    wait (nline == 1);
    key_n[1] = 0;                                                       // KEY2 hold
    repeat (5 * MS) @(posedge clk);
    c0 = dut.cnt;
    repeat (1000) @(posedge clk);
    if (dut.cnt !== c0) begin $display("FAIL KEY2 hold"); errors = errors + 1; end
    wait (nline == 2);
    key_n[1] = 1;
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
