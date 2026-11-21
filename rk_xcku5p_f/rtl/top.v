// RK-XCKU5P-F starter: LED counter, keys, 1 Hz UART heartbeat.
//   LED1..4   binary counter; KEY1 steps its speed 0..3 (0 slowest), wraps after 3
//   KEY2      holds the counter while pressed
//   KEY3      clears the counter
//   KEY4      lamp test: all LEDs on while pressed
//   UART      "ku5p-f up SSSSSSSS speed N keys K temp +TTT.TC\r\n" once a second, 115200 8N1
//             (FT2232H channel B); S = seconds since load, N = speed, K = pressed keys
//             (bit 0 = KEY1), all hex; temp = FPGA die temperature from the SYSMON, deg C
// Clock: 200 MHz differential oscillator (the DDR4 system clock, T24/U24). The board's 50 MHz
// PL_CLK on AC13 does not toggle on this board (checked 2026-11-21), so it is not used.
// Keys pull up to 3.3 V and short to ground when pressed.
`default_nettype none
module top #(
  parameter integer CLK_HZ = 200_000_000,
  parameter integer BAUD   = 115_200
) (
  input  wire       sys_clk_p,     // 200 MHz
  input  wire       sys_clk_n,
  input  wire [3:0] key_n,          // KEY1..KEY4, low = pressed
  output wire [3:0] led,            // LED1..LED4, high = on
  output wire       uart_tx
);
  wire clk_ibuf, clk;
  IBUFDS u_ibufds (.I(sys_clk_p), .IB(sys_clk_n), .O(clk_ibuf));
  BUFG   u_bufg   (.I(clk_ibuf), .O(clk));

  // ---------------------------------------------------------------- temperature
  wire [8*6-1:0] temp_ascii;
  sysmon_temp #(.CLK_HZ(CLK_HZ)) u_temp (.clk(clk), .temp_x10(), .code(), .valid(), .ascii(temp_ascii));

  // ---------------------------------------------------------------- keys
  // 2-flop synchroniser, then sampled every 1 ms: a key counts as pressed after two equal samples
  (* ASYNC_REG = "TRUE" *) reg [3:0] key_s0 = 4'h0, key_s1 = 4'h0;
  always @(posedge clk) begin
    key_s0 <= ~key_n;
    key_s1 <= key_s0;
  end
  localparam integer MS = CLK_HZ / 1000;
  reg [$clog2(MS)-1:0] ms_div = 0;
  reg [3:0] key_a = 4'h0, keys = 4'h0, keys_q = 4'h0;
  always @(posedge clk) begin
    keys_q <= keys;
    if (ms_div == MS - 1) begin
      ms_div <= 0;
      key_a  <= key_s1;
      if (key_a == key_s1) keys <= key_s1;
    end else begin
      ms_div <= ms_div + 1'b1;
    end
  end
  wire [3:0] key_press = keys & ~keys_q;

  // ---------------------------------------------------------------- LED counter
  reg [1:0]  speed = 2'd0;
  reg [31:0] cnt = 0;
  always @(posedge clk) begin
    if (key_press[0]) speed <= speed + 1'b1;
    if (keys[2])       cnt <= 0;
    else if (!keys[1]) cnt <= cnt + 1'b1;
  end
  // speed 0 -> cnt[30:27] (LSB ~0.75 Hz) .. speed 3 -> cnt[27:24] (LSB ~6 Hz)
  reg [3:0] led_q = 4'h0;
  always @(posedge clk) begin
    case (speed)
      2'd0: led_q <= cnt[30:27];
      2'd1: led_q <= cnt[29:26];
      2'd2: led_q <= cnt[28:25];
      2'd3: led_q <= cnt[27:24];
    endcase
    if (keys[3]) led_q <= 4'hF;
  end
  assign led = led_q;

  // ---------------------------------------------------------------- 1 Hz UART heartbeat
  reg [$clog2(CLK_HZ)-1:0] sec_div = 0;
  reg [31:0] secs = 0;
  reg        tick = 1'b0;
  always @(posedge clk) begin
    tick <= 1'b0;
    if (sec_div == CLK_HZ - 1) begin
      sec_div <= 0;
      secs    <= secs + 1'b1;
      tick    <= 1'b1;
    end else begin
      sec_div <= sec_div + 1'b1;
    end
  end

  function [7:0] hex(input [3:0] n);
    hex = (n < 10) ? 8'h30 + n : 8'h57 + n;   // '0'..'9', 'a'..'f'
  endfunction
  function [63:0] hex8(input [31:0] v);
    integer i;
    begin
      for (i = 0; i < 8; i = i + 1) hex8[8 * i +: 8] = hex(v[4 * i +: 4]);
    end
  endfunction

  // "ku5p-f up " 8 " speed " 1 " keys " 1 " temp " 6 "C" "\r\n"
  localparam integer LMAX = 48;
  reg  [8*LMAX-1:0] line = 0;
  reg  [5:0]        nleft = 0;
  reg               tx_valid = 1'b0;
  wire              tx_ready;
  always @(posedge clk) begin
    tx_valid <= 1'b0;
    if (nleft == 0) begin
      if (tick) begin
        line  <= {"ku5p-f up ", hex8(secs), " speed ", hex({2'b00, speed}), " keys ", hex(keys),
                  " temp ", temp_ascii, "C", 8'h0d, 8'h0a};
        nleft <= LMAX;
      end
    end else if (tx_ready && !tx_valid) begin
      tx_valid <= 1'b1;
    end else if (tx_valid) begin
      line  <= line << 8;
      nleft <= nleft - 1'b1;
    end
  end

  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
    .clk(clk), .valid(tx_valid), .data(line[8*LMAX-1 -: 8]), .ready(tx_ready), .txd(uart_tx)
  );
endmodule
`default_nettype wire
