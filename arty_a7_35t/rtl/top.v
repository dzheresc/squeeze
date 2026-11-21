// Arty A7-35T starter: LED counter, RGB colour cycle, buttons/switches, 1 Hz UART heartbeat.
//   led[3:0]   binary counter, rate set by sw[1:0] (sw=0 slowest, 3 fastest)
//   led0..3 RGB  dim colour walk (PWM ~1/16 duty so it does not blind you)
//   btn[0]     holds the counter; ck_rst (red RESET button, active low) clears it
//   UART       "arty a7 up NNNNNNNN\r\n" once a second on the board USB serial port, 115200 8N1
`default_nettype none
module top #(
  parameter integer CLK_HZ = 100_000_000,
  parameter integer BAUD   = 115_200
) (
  input  wire       CLK100MHZ,
  input  wire       ck_rst,          // active low
  input  wire [3:0] sw,
  input  wire [3:0] btn,
  output wire [3:0] led,
  output wire [3:0] led_r,
  output wire [3:0] led_g,
  output wire [3:0] led_b,
  output wire       uart_rxd_out     // FPGA -> PC
);
  wire clk = CLK100MHZ;

  // reset synchroniser
  reg [2:0] rst_sr = 3'b111;
  always @(posedge clk) rst_sr <= {rst_sr[1:0], ~ck_rst};
  wire rst = rst_sr[2];

  // free-running counter drives LEDs and PWM
  reg [31:0] cnt = 0;
  reg [3:0]  hold_sr = 0;
  always @(posedge clk) hold_sr <= {hold_sr[2:0], btn[0]};
  always @(posedge clk)
    if (rst)             cnt <= 0;
    else if (!hold_sr[3]) cnt <= cnt + 1;

  // sw[1:0]: 0 -> bit 26 (~0.75 Hz LSB), 3 -> bit 23 (~6 Hz LSB)
  reg [3:0] led_q;
  always @(posedge clk)
    case (sw[1:0])
      2'd0: led_q <= cnt[29:26];
      2'd1: led_q <= cnt[28:25];
      2'd2: led_q <= cnt[27:24];
      2'd3: led_q <= cnt[26:23];
    endcase
  assign led = led_q;

  // RGB: each LED shows a 3-bit colour, rotating; dimmed with 1/16 PWM
  wire       pwm = (cnt[3:0] == 4'd0);
  wire [2:0] c0 = cnt[29:27] + 3'd0, c1 = cnt[29:27] + 3'd1,
             c2 = cnt[29:27] + 3'd2, c3 = cnt[29:27] + 3'd3;
  assign led_r = {c3[0], c2[0], c1[0], c0[0]} & {4{pwm}};
  assign led_g = {c3[1], c2[1], c1[1], c0[1]} & {4{pwm}};
  assign led_b = {c3[2], c2[2], c1[2], c0[2]} & {4{pwm}};

  // 1 Hz tick + seconds counter
  reg [26:0] sec_div = 0;
  reg [31:0] secs = 0;
  reg        tick = 0;
  always @(posedge clk) begin
    tick <= 1'b0;
    if (sec_div == CLK_HZ - 1) begin sec_div <= 0; secs <= secs + 1; tick <= 1'b1; end
    else sec_div <= sec_div + 1;
  end

  // message: "arty a7 up " + 8 hex digits + "\r\n" = 21 bytes
  localparam integer MSG_LEN = 21;
  reg  [4:0]  idx = 0;
  reg         busy = 0;
  reg  [31:0] snap = 0;
  wire        tx_ready;
  reg         tx_valid = 0;
  reg  [7:0]  tx_byte;

  function [7:0] hex(input [3:0] n);
    hex = (n < 10) ? 8'h30 + n : 8'h57 + n;   // '0'..'9','a'..'f'
  endfunction

  always @* begin
    case (idx)
      0: tx_byte = "a";  1: tx_byte = "r";  2: tx_byte = "t";  3: tx_byte = "y";
      4: tx_byte = " ";  5: tx_byte = "a";  6: tx_byte = "7";  7: tx_byte = " ";
      8: tx_byte = "u";  9: tx_byte = "p"; 10: tx_byte = " ";
      11: tx_byte = hex(snap[31:28]); 12: tx_byte = hex(snap[27:24]);
      13: tx_byte = hex(snap[23:20]); 14: tx_byte = hex(snap[19:16]);
      15: tx_byte = hex(snap[15:12]); 16: tx_byte = hex(snap[11:8]);
      17: tx_byte = hex(snap[7:4]);   18: tx_byte = hex(snap[3:0]);
      19: tx_byte = 8'h0d; default: tx_byte = 8'h0a;
    endcase
  end

  always @(posedge clk) begin
    tx_valid <= 1'b0;
    if (!busy) begin
      if (tick) begin busy <= 1'b1; idx <= 0; snap <= secs; end
    end else if (tx_ready && !tx_valid) begin
      tx_valid <= 1'b1;
    end else if (tx_valid) begin
      if (idx == MSG_LEN - 1) busy <= 1'b0;
      else idx <= idx + 1;
    end
  end

  uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
    .clk(clk), .valid(tx_valid), .data(tx_byte), .ready(tx_ready), .txd(uart_rxd_out)
  );
endmodule
`default_nettype wire
