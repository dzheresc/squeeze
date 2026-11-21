// Stores received frames in DDR4 as a circular buffer of 64-byte slots, through the MIG native
// interface (ui_clk domain), and reads every slot back to check it.
//
// Slot n (byte address 64 * (n mod 2^SB)) holds, byte 0 at bit 0:
//   bytes  0..45  frame payload (frame bytes 14..59)
//   bytes 46..47  frame length in bytes after the SFD (FCS included)
//   bytes 48..51  slot index n (count of frames written before this one)
//   bytes 52..55  wrap count when it was written
//   bytes 56..59  zero
//   bytes 60..63  "DDR4"
// For each frame from the input FIFO: write both 32-byte words, wait WAIT cycles, read both
// back and compare them with what was written (rd_err counts bad words). Once LAG slots have
// been written it also reads the second word of slot n - LAG, written about LAG frames ago, and
// checks its index and magic (old_err): that catches address aliasing and lost data, which an
// immediate read-back of the same address cannot. led = low nibble of payload byte 0 as read
// back from DDR4.
`default_nettype none
module ddr_ring #(
  parameter integer SB   = 25,          // slot address bits: 2^25 x 64 B = 2 GB
  parameter integer LAG  = 1 << 20,     // distance of the old-slot check, in slots
  parameter integer WAIT = 256,         // ui_clk cycles between the writes and the read-back
  parameter integer MAW  = 29           // MIG app_addr width
) (
  input  wire           clk,
  input  wire           rst,            // MIG reset or not calibrated: stops everything
  input  wire           clr,            // clears counters and restarts at slot 0 (when idle)

  input  wire           in_valid,
  input  wire [383:0]   in_data,        // {len[15:0], payload[367:0]}
  output reg            in_pop = 1'b0,

  output wire           app_en,
  output wire [2:0]     app_cmd,
  output wire [MAW-1:0] app_addr,
  output wire           app_wdf_wren,
  output wire [255:0]   app_wdf_data,
  input  wire           app_rdy,
  input  wire           app_wdf_rdy,
  input  wire           rd_valid,
  input  wire [255:0]   rd_data,

  output reg  [31:0]    wr_cnt = 0,     // slots written
  output reg  [31:0]    wrap_cnt = 0,   // times the write pointer went past the last slot
  output reg  [31:0]    rd_cnt = 0,     // slots read back
  output reg  [31:0]    rd_err = 0,     // read-back words that differ from what was written
  output reg  [31:0]    old_cnt = 0,    // old-slot checks
  output reg  [31:0]    old_err = 0,    // old-slot checks with a wrong index or magic
  output reg  [3:0]     led = 4'h0
);
  localparam [31:0] MAGIC = {"4", "R", "D", "D"};   // bytes 60..63 read "DDR4"

  localparam [2:0] S_IDLE = 3'd0, S_WR0 = 3'd1, S_WR1 = 3'd2, S_WAIT = 3'd3,
                   S_RD0 = 3'd4, S_RD1 = 3'd5, S_RDO = 3'd6, S_RX = 3'd7;
  reg [2:0]    st = S_IDLE;
  reg [511:0]  slot_d = 0;
  reg [SB-1:0] wslot = 0;
  reg [31:0]   old_idx = 0;
  reg          do_old = 1'b0;
  reg          lag_ok = 1'b0;
  reg [$clog2(WAIT+1)-1:0] wcnt = 0;
  reg [1:0]    nrx = 0;               // read beats received for this slot

  wire wr_st = (st == S_WR0) || (st == S_WR1);
  wire rd_st = (st == S_RD0) || (st == S_RD1) || (st == S_RDO);
  wire half  = (st == S_WR1) || (st == S_RD1) || (st == S_RDO);
  wire [SB-1:0] aslot = (st == S_RDO) ? old_idx[SB-1:0] : wslot;
  assign app_en       = rd_st | (wr_st & app_wdf_rdy);
  assign app_cmd      = wr_st ? 3'd0 : 3'd1;
  assign app_addr     = {aslot, half, 3'b000};      // zero-extended; BL8 column step
  assign app_wdf_wren = wr_st & app_wdf_rdy & app_rdy;
  assign app_wdf_data = half ? slot_d[511:256] : slot_d[255:0];
  wire acc = app_en & app_rdy;

  // read-back pipeline: register, compare, count
  reg         rv = 1'b0, v2 = 1'b0;
  reg [1:0]   rb = 0, b2 = 0;
  reg [255:0] rq = 0;
  reg         eq0 = 1'b0, eq1 = 1'b0, oldok = 1'b0;

  always @(posedge clk) begin
    in_pop <= 1'b0;

    rv <= rd_valid;
    if (rd_valid) begin
      rq  <= rd_data;
      rb  <= nrx;
      nrx <= nrx + 1'b1;
    end
    v2    <= rv;
    b2    <= rb;
    eq0   <= (rq == slot_d[255:0]);
    eq1   <= (rq == slot_d[511:256]);
    oldok <= (rq[159:128] == old_idx) && (rq[255:224] == MAGIC);
    if (rv && rb == 2'd0) led <= rq[3:0];
    if (v2) begin
      case (b2)
        2'd0: if (!eq0) rd_err <= rd_err + 1'b1;
        2'd1: begin
          rd_cnt <= rd_cnt + 1'b1;
          if (!eq1) rd_err <= rd_err + 1'b1;
        end
        default: begin
          old_cnt <= old_cnt + 1'b1;
          if (!oldok) old_err <= old_err + 1'b1;
        end
      endcase
    end

    case (st)
      S_IDLE: begin
        nrx <= 0;
        if (clr) begin
          wr_cnt <= 0; wrap_cnt <= 0; rd_cnt <= 0; rd_err <= 0; old_cnt <= 0; old_err <= 0;
          lag_ok <= 1'b0;
        end else if (in_valid) begin
          slot_d  <= {MAGIC, 32'h0, wrap_cnt, wr_cnt, in_data};
          wslot   <= wr_cnt[SB-1:0];
          old_idx <= wr_cnt - LAG;
          do_old  <= lag_ok;
          in_pop  <= 1'b1;
          st      <= S_WR0;
        end
      end
      S_WR0: if (acc) st <= S_WR1;
      S_WR1: if (acc) begin
        wr_cnt <= wr_cnt + 1'b1;
        if (&wslot) wrap_cnt <= wrap_cnt + 1'b1;
        if (wr_cnt == LAG - 1) lag_ok <= 1'b1;
        wcnt <= 0;
        st   <= S_WAIT;
      end
      S_WAIT: begin
        wcnt <= wcnt + 1'b1;
        if (wcnt == WAIT - 1) st <= S_RD0;
      end
      S_RD0: if (acc) st <= S_RD1;
      S_RD1: if (acc) st <= do_old ? S_RDO : S_RX;
      S_RDO: if (acc) st <= S_RX;
      default: if (nrx == (do_old ? 2'd3 : 2'd2) && !rd_valid && !rv && !v2) st <= S_IDLE;
    endcase

    if (rst) begin
      st <= S_IDLE;
      rv <= 1'b0;
      v2 <= 1'b0;
      nrx <= 0;
    end
  end
endmodule
`default_nettype wire
