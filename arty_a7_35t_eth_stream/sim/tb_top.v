// Arty A7-35T stream sender, whole top level (MMCM, ODDR, clock crossings, MDIO, UART) with
// scaled rates: CLK_HZ = 11.52 MHz worth of "second" on the 100 MHz board clock and
// TX_HZ = 250 kHz worth on the 25 MHz MII TX_CLK, so one design second is 11.52 M / 250 k cycles.
// The bench decodes every MII frame (preamble, addresses, EtherType, payload, FCS) and checks:
//   - eth_rstn stays low for the first 10 ms and no frame leaves before the 120 ms PHY wait
//   - frames carry seq 1, 2, 3 ... and the one-hot pattern 0001, 0010, 0100, 1000, 0001 ...
//   - the start-to-start spacing is TX_HZ / 4 (SW = 00), TX_HZ / 100 (01) and 168 cycles (11)
//   - the UART line reports fps = 4 for a whole second at SW = 00
// SW = 10 (10k/s) is left out: at the scaled TX_HZ its period (25 cycles) is shorter than a frame.
// The MDIO line only has its pull-up, so BMSR and PHYSTS read back ffff.
`timescale 1ns/1ps
`default_nettype none
module tb_top;
  localparam integer BAUD   = 115_200;
  localparam integer CLK_HZ = 100 * BAUD;      // 11.52 MHz: UART divider 100, MDC divider 5
  localparam integer TX_HZ  = 250_000;
  reg clk = 0, tx_clk = 0;
  always #5 clk = ~clk;                         // 100 MHz board oscillator
  always #20.003 tx_clk = ~tx_clk;              // PHY TX_CLK, not locked to the oscillator
  reg ck_rst = 1;
  reg [1:0] sw = 2'b00;
  wire [3:0] led, led_g, txd;
  wire uart, ref_clk, rstn, tx_en, mdc, mdio;
  pullup (mdio);
  top #(.CLK_HZ(CLK_HZ), .TX_HZ(TX_HZ), .BAUD(BAUD)) dut (
    .CLK100MHZ(clk), .ck_rst(ck_rst), .sw(sw), .led(led), .led_g(led_g), .uart_rxd_out(uart),
    .eth_ref_clk(ref_clk), .eth_rstn(rstn), .eth_tx_clk(tx_clk), .eth_txd(txd), .eth_tx_en(tx_en),
    .eth_mdc(mdc), .eth_mdio(mdio));

  integer errors = 0;
  task fail(input [8*48-1:0] what);
    begin $display("%0t FAIL %0s", $time, what); errors = errors + 1; end
  endtask

  // ---------------------------------------------------------------- PHY reset timing
  realtime t_rstn = 0;
  always @(posedge rstn) if (t_rstn == 0) t_rstn = $realtime;
  always @(posedge tx_en)
    if (!rstn || $realtime - t_rstn < 110.0 * 10.0 * CLK_HZ / 1000) fail("frame before the PHY wait");

  // ---------------------------------------------------------------- MII frame decoder
  reg  [7:0]  fb [0:127];
  integer     nb = 0, nib = 0;
  reg  [3:0]  lo;
  integer     nframes = 0, gap = 0, last_start = -1, cyc = 0;
  reg  [31:0] exp_seq = 1;
  reg  [3:0]  exp_pat = 4'b0001;
  integer     spacing = 0;
  reg  [31:0] c;
  reg  [31:0] cn;
  reg         prev_en = 0;
  integer     i;
  function [31:0] crc8(input [31:0] cin, input [7:0] d);
    integer b;
    reg [31:0] x;
    begin
      x = cin;
      for (b = 0; b < 8; b = b + 1) x = (x[0] ^ d[b]) ? (x >> 1) ^ 32'hEDB88320 : x >> 1;
      crc8 = x;
    end
  endfunction
  always @(posedge tx_clk) begin
    cyc = cyc + 1;
    if (tx_en) begin
      if (!prev_en) begin
        spacing = (last_start < 0) ? 0 : cyc - last_start;
        last_start = cyc;
        nb = 0;  nib = 0;
      end
      if (nib == 0) lo = txd;
      else begin fb[nb] = {txd, lo}; nb = nb + 1; end
      nib = 1 - nib;
    end else if (prev_en) begin
      // frame ended: 8 preamble/SFD + 60 data + 4 FCS
      nframes = nframes + 1;
      c = 32'hFFFFFFFF;
      for (i = 8; i < 72; i = i + 1) c = crc8(c, fb[i]);
      if (nb != 72 || nib != 0) fail("frame length");
      for (i = 0; i < 7; i = i + 1) if (fb[i] != 8'h55) fail("preamble");
      if (fb[7] != 8'hD5) fail("SFD");
      for (i = 8; i < 14; i = i + 1) if (fb[i] != 8'hFF) fail("dst");
      if ({fb[14], fb[15], fb[16], fb[17], fb[18], fb[19]} != 48'h0200_0000_A735) fail("src");
      if ({fb[20], fb[21]} != 16'h88B5) fail("EtherType");
      if (fb[22] != {4'h0, exp_pat}) fail("pattern");
      if ({fb[23], fb[24], fb[25], fb[26]} != exp_seq) fail("seq");
      if ({fb[27], fb[28], fb[29], fb[30], fb[31], fb[32], fb[33]} != "SQUEEZE") fail("magic");
      for (i = 34; i < 68; i = i + 1) if (fb[i] != exp_seq[7:0] + (i - 22)) fail("payload");
      if (c != 32'hDEBB20E3) fail("FCS");
      exp_seq = exp_seq + 1;
      exp_pat = {exp_pat[2:0], exp_pat[3]};
    end
    prev_en = tx_en;
  end

  // ---------------------------------------------------------------- UART receiver
  localparam integer LEN = 21 + 8 + 5 + 8 + 5 + 1 + 4 + 1 + 6 + 4 + 8 + 4 + 2;
  localparam integer BIT = CLK_HZ / BAUD;
  reg [8*LEN-1:0] line = 0;
  integer nline = 0, nchar = 0, k;
  reg [7:0] ch;
  reg [8*LEN-1:0] last_line = 0;
  always begin
    @(negedge uart);
    repeat (BIT / 2) @(posedge clk);
    for (k = 0; k < 8; k = k + 1) begin repeat (BIT) @(posedge clk); ch[k] = uart; end
    repeat (BIT) @(posedge clk);
    line = {line[8*(LEN-1)-1:0], ch};
    nchar = nchar + 1;
    if (ch == 8'h0a) begin
      nline = nline + 1;
      $display("%0t uart: %0s", $time, line[8*LEN-1:16]);
      if (nchar != LEN || line[8*LEN-1 -: 8*21] != "arty eth stream sent " ||
          line[8*24-1:0] != {" bmsr ffff physts ffff", 8'h0d, 8'h0a})
        fail("uart line format");
      last_line = line;
      nchar = 0;
    end
  end

  // ---------------------------------------------------------------- stimulus
  task expect_spacing(input integer n, input integer period, input [8*16-1:0] what);
    integer f0, bad;
    begin
      f0 = nframes;
      bad = 0;
      wait (nframes == f0 + 1);              // the first gap after a switch change can be short
      while (nframes < f0 + n) begin
        @(negedge tx_en);
        if (spacing != period) bad = bad + 1;
      end
      $display("%0t %0s: %0d frames, last spacing %0d cycles (expect %0d)", $time, what, n, spacing, period);
      if (bad) fail(what);
    end
  endtask
  integer n0;
  initial begin
    wait (nframes == 1);
    $display("%0t first frame; eth_rstn rose at %0t", $time, t_rstn);
    expect_spacing(3, TX_HZ / 4, "SW=00 4/s");
    // a whole second at 4/s: the next report must say fps 00000004
    wait (nline >= 1);
    n0 = nline;
    wait (nline == n0 + 1);
    if (last_line[8*(LEN-34)-1 -: 8*8] != "00000004") fail("fps at SW=00");
    sw = 2'b01;
    expect_spacing(6, TX_HZ / 100, "SW=01 100/s");
    sw = 2'b11;
    expect_spacing(40, 168, "SW=11 line rate");
    // reset: the stream restarts from seq 1 after the PHY wait
    ck_rst = 0;
    #20_000;                  // lets a frame already on the wire finish
    ck_rst = 1;
    exp_seq = 1;
    exp_pat = 4'b0001;
    t_rstn = 0;
    n0 = nframes;
    wait (nframes == n0 + 3);
    $display("%0t restarted after reset, %0d frames in all", $time, nframes);
    if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
    $finish;
  end
  initial begin
    #200_000_000;
    $display("FAIL timeout, %0d frames, %0d uart lines", nframes, nline);
    $finish;
  end
endmodule
`default_nettype wire
