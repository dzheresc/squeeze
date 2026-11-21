// Receives Ethernet frames from a 4-bit receive path (MII, or RGMII at 10/100 where each
// nibble is held for a whole RX clock), low nibble first, and checks the frames sent by
// arty_a7_35t_eth: EtherType 88B5, byte 14 = LED pattern, bytes 15..18 = sequence number.
// done pulses once per frame (when dv drops) with the results below valid.
`default_nettype none
module eth_rx_frame (
  input  wire        clk,
  input  wire        dv,
  input  wire [3:0]  rxd,
  output reg         done = 1'b0,
  output reg         crc_ok = 1'b0,    // FCS correct and at least 64 bytes
  output reg         ours = 1'b0,      // crc_ok and EtherType 88B5
  output reg  [3:0]  pattern = 4'h0,
  output reg  [31:0] seq = 0,
  output reg  [10:0] len = 0           // bytes after the SFD, FCS included
);
  localparam [1:0] S_IDLE = 2'd0, S_PRE = 2'd1, S_DATA = 2'd2, S_SKIP = 2'd3;
  reg [1:0]  st = S_IDLE;
  reg        hi = 1'b0;
  reg [3:0]  lo = 4'h0;
  reg [10:0] n = 0;
  reg [31:0] crc = 32'hFFFFFFFF;
  reg [15:0] etype = 0;
  reg [3:0]  pat = 0;
  reg [31:0] sq = 0;
  wire [7:0] byte_in = {rxd, lo};
  wire [31:0] crc_next;
  crc32_d8 u_crc (.crc(crc), .data(byte_in), .next(crc_next));

  always @(posedge clk) begin
    done <= 1'b0;
    case (st)
      S_IDLE: if (dv) st <= (rxd == 4'h5) ? S_PRE : S_SKIP;
      S_PRE: begin
        if (!dv)                 st <= S_IDLE;
        else if (rxd == 4'hD) begin st <= S_DATA; hi <= 1'b0; n <= 0; crc <= 32'hFFFFFFFF; end
        else if (rxd != 4'h5)    st <= S_SKIP;
      end
      S_DATA: begin
        if (!dv) begin
          done    <= 1'b1;
          len     <= n;
          crc_ok  <= !hi && n >= 64 && crc == 32'hDEBB20E3;
          ours    <= !hi && n >= 64 && crc == 32'hDEBB20E3 && etype == 16'h88B5;
          pattern <= pat;
          seq     <= sq;
          st      <= S_IDLE;
        end else if (!hi) begin
          lo <= rxd;
          hi <= 1'b1;
        end else begin
          hi  <= 1'b0;
          crc <= crc_next;
          if (n != 11'h7FF) n <= n + 1'b1;
          case (n)
            12: etype[15:8] <= byte_in;
            13: etype[7:0]  <= byte_in;
            14: pat         <= byte_in[3:0];
            15: sq[31:24]   <= byte_in;
            16: sq[23:16]   <= byte_in;
            17: sq[15:8]    <= byte_in;
            18: sq[7:0]     <= byte_in;
            default: ;
          endcase
        end
      end
      default: if (!dv) st <= S_IDLE;  // S_SKIP: wait for the end of a frame we cannot parse
    endcase
  end
endmodule
`default_nettype wire
