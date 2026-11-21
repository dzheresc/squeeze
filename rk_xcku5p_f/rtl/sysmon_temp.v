// On-die temperature from the UltraScale+ SYSMONE4, as signed tenths of a degree Celsius.
// SYSMON runs in single-channel mode on the temperature sensor (internal reference, calibration on),
// continuously converting; this module reads status register 0x00 over the DRP about every 1 ms.
//   T[C] = code16 * 509.3140064 / 2^16 - 280.2308787        (UG580, SYSMONE4, internal reference)
//   tenths = (code16 * 5093 >> 16) - 2802
`default_nettype none
module sysmon_temp #(
  parameter integer CLK_HZ = 200_000_000     // DRP clock (DCLK), at most 250 MHz
) (
  input  wire               clk,
  output reg  signed [15:0] temp_x10 = 16'sd0,
  output reg  [15:0]        code = 16'd0,      // raw ADC result (10 valid bits in [15:6])
  output reg                valid = 1'b0,      // set after the first read
  output reg  [8*6-1:0]     ascii = "+000.0"  // temp_x10 as text: sign, 3 digits, ".", tenths
);
  // ADCCLK = DCLK / div must stay at or below 5.2 MHz
  localparam integer DIV = (CLK_HZ + 4_000_000 - 1) / 4_000_000;
  localparam [15:0]  CFG2 = {DIV[7:0], 8'h00};

  reg         den = 1'b0;
  wire        drdy;
  wire [15:0] dout;

  SYSMONE4 #(
    .INIT_40(16'h0000),            // channel 0 = temperature, continuous sampling, no averaging
    .INIT_41(16'h3FFF),            // single-channel mode, calibration on, alarms off
    .INIT_42(CFG2),                // ADC clock divider
    .SIM_DEVICE("ULTRASCALE_PLUS")
  ) u_sysmon (
    .DCLK(clk), .DEN(den), .DWE(1'b0), .DADDR(8'h00), .DI(16'h0000), .DO(dout), .DRDY(drdy),
    .RESET(1'b0), .CONVST(1'b0), .CONVSTCLK(1'b0),
    .VP(1'b0), .VN(1'b0), .VAUXP(16'h0000), .VAUXN(16'h0000),
    .ALM(), .OT(), .BUSY(), .CHANNEL(), .EOC(), .EOS(), .JTAGBUSY(), .JTAGLOCKED(), .JTAGMODIFIED(),
    .MUXADDR(), .ADC_DATA(), .I2C_SCLK(), .I2C_SDA(), .I2C_SCLK_TS(), .I2C_SDA_TS(), .SMBALERT_TS()
  );

  localparam integer MS = CLK_HZ / 1000;
  reg [$clog2(MS)-1:0] div = 0;
  reg [28:0]           prod = 0;
  reg                  have = 1'b0;
  always @(posedge clk) begin
    den <= 1'b0;
    if (div == MS - 1) begin
      div <= 0;
      den <= 1'b1;
    end else begin
      div <= div + 1'b1;
    end
    if (drdy) begin
      code <= dout;
      prod <= dout * 13'd5093;
      have <= 1'b1;
    end
    if (have) begin
      temp_x10 <= $signed({3'b000, prod[28:16]}) - 16'sd2802;
      valid    <= 1'b1;
    end
  end
  // decimal digits by repeated subtraction, restarted every 1 ms (takes < 40 cycles)
  reg  [10:0] m = 0;
  reg  [1:0]  k = 2'd3;
  reg  [3:0]  dg [0:2];
  reg         neg = 1'b0;
  wire [10:0] step = (k == 0) ? 11'd1000 : (k == 1) ? 11'd100 : 11'd10;
  always @(posedge clk) begin
    if (den) begin
      neg <= temp_x10 < 0;
      m   <= (temp_x10 < 0) ? -temp_x10[10:0] : temp_x10[10:0];
      k   <= 2'd0;
      dg[0] <= 4'd0;  dg[1] <= 4'd0;  dg[2] <= 4'd0;
    end else if (k != 2'd3) begin
      if (m >= step) begin
        m <= m - step;
        dg[k] <= dg[k] + 1'b1;
      end else if (k == 2'd2) begin
        ascii <= {neg ? "-" : "+", 8'h30 + dg[0], 8'h30 + dg[1], 8'h30 + dg[2], ".", 8'h30 + m[3:0]};
        k <= 2'd3;
      end else begin
        k <= k + 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
