// Stores received frames in DDR4 as a circular buffer of 128-byte slots that fills the whole
// memory, through the MIG native interface (ui_clk domain), and reads every slot back to check it.
//
// Slot n (byte address 128 * (n mod 2^SB)) holds, byte 0 at bit 0:
//   bytes   0..63   the frame: the first 64 bytes after the SFD (a whole minimum frame, FCS included)
//   bytes  64..65   frame length in bytes after the SFD (FCS included)
//   bytes  66..67   zero
//   bytes  68..71   slot index n (count of frames written before this one)
//   bytes  72..75   wrap count when it was written
//   bytes  76..91   zero
//   bytes  92..95   "DDR4"
//   bytes  96..127  zero
// For each frame from the input FIFO: write the four 32-byte words, wait WAIT cycles, read them
// back and compare them with what was written (rd_err counts bad words). Once LAG slots have
// been written it also reads the metadata word of slot n - LAG and checks its index and magic
// (old_err): that catches address aliasing and lost data, which an immediate read-back of the
// same address cannot. led = low nibble of frame byte 14 (the first payload byte) as read back
// from DDR4.
`default_nettype none
module ddr_ring #(
  parameter integer SB   = 24,          // slot address bits: 2^24 x 128 B = 2 GB
  parameter integer LAG  = 16,          // distance of the old-slot check, in slots
  parameter integer WAIT = 256,         // ui_clk cycles between the writes and the read-back
  parameter integer MAW  = 29           // MIG app_addr width
) (
  input  wire           clk,
  input  wire           rst,            // MIG reset or not calibrated: stops everything
  input  wire           clr,            // clears counters and restarts at slot 0 (when idle)

  input  wire           in_valid,
  input  wire [527:0]   in_data,        // {len[15:0], frame[511:0]}
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
  localparam [31:0] MAGIC = {"4", "R", "D", "D"};   // bytes 92..95 read "DDR4"

  localparam [2:0] S_IDLE = 3'd0, S_WR = 3'd1, S_WAIT = 3'd2, S_RD = 3'd3, S_RDO = 3'd4,
                   S_RX = 3'd5;
  reg [2:0]    st = S_IDLE;
  reg [255:0]  w [0:3];                 // the slot being written
  reg [1:0]    wi = 0;                  // word being written / read
  reg [SB-1:0] wslot = 0;
  reg [31:0]   old_idx = 0;
  reg          do_old = 1'b0;
  reg          lag_ok = 1'b0;
  reg [$clog2(WAIT+1)-1:0] wcnt = 0;
  reg [2:0]    nrx = 0;                 // read beats received for this slot

  wire [SB-1:0] aslot = (st == S_RDO) ? old_idx[SB-1:0] : wslot;
  wire [1:0]    aword = (st == S_RDO) ? 2'd2 : wi;
  wire wr_st = (st == S_WR);
  wire rd_st = (st == S_RD) || (st == S_RDO);
  assign app_en       = rd_st | (wr_st & app_wdf_rdy);
  assign app_cmd      = wr_st ? 3'd0 : 3'd1;
  assign app_addr     = {aslot, aword, 3'b000};     // zero-extended; BL8 column step
  assign app_wdf_wren = wr_st & app_wdf_rdy & app_rdy;
  assign app_wdf_data = w[wi];
  wire acc = app_en & app_rdy;

  // read-back pipeline: register data + expected word, compare, count
  reg         rv = 1'b0, v2 = 1'b0;
  reg [2:0]   rb = 0, b2 = 0;
  reg [255:0] rq = 0, rexp = 0;
  reg         eq = 1'b0, oldok = 1'b0;

  integer i;
  always @(posedge clk) begin
    in_pop <= 1'b0;

    rv <= rd_valid;
    if (rd_valid) begin
      rq   <= rd_data;
      rexp <= w[nrx[1:0]];
      rb   <= nrx;
      nrx  <= nrx + 1'b1;
    end
    v2    <= rv;
    b2    <= rb;
    eq    <= (rq == rexp);
    oldok <= (rq[63:32] == old_idx) && (rq[255:224] == MAGIC);
    if (rv && rb == 3'd0) led <= rq[115:112];
    if (v2) begin
      if (b2 == 3'd4) begin
        old_cnt <= old_cnt + 1'b1;
        if (!oldok) old_err <= old_err + 1'b1;
      end else begin
        if (b2 == 3'd3) rd_cnt <= rd_cnt + 1'b1;
        if (!eq) rd_err <= rd_err + 1'b1;
      end
    end

    case (st)
      S_IDLE: begin
        nrx <= 0;
        wi  <= 0;
        if (clr) begin
          wr_cnt <= 0; wrap_cnt <= 0; rd_cnt <= 0; rd_err <= 0; old_cnt <= 0; old_err <= 0;
          lag_ok <= 1'b0;
        end else if (in_valid) begin
          w[0] <= in_data[255:0];
          w[1] <= in_data[511:256];
          w[2] <= {MAGIC, 128'h0, wrap_cnt, wr_cnt, 16'h0, in_data[527:512]};
          w[3] <= 256'h0;
          wslot   <= wr_cnt[SB-1:0];
          old_idx <= wr_cnt - LAG;
          do_old  <= lag_ok;
          in_pop  <= 1'b1;
          st      <= S_WR;
        end
      end
      S_WR: if (acc) begin
        wi <= wi + 1'b1;
        if (wi == 2'd3) begin
          wr_cnt <= wr_cnt + 1'b1;
          if (&wslot) wrap_cnt <= wrap_cnt + 1'b1;
          if (wr_cnt == LAG - 1) lag_ok <= 1'b1;
          wcnt <= 0;
          st   <= S_WAIT;
        end
      end
      S_WAIT: begin
        wcnt <= wcnt + 1'b1;
        if (wcnt == WAIT - 1) st <= S_RD;
      end
      S_RD: if (acc) begin
        wi <= wi + 1'b1;
        if (wi == 2'd3) st <= do_old ? S_RDO : S_RX;
      end
      S_RDO: if (acc) st <= S_RX;
      default: if (nrx == (do_old ? 3'd5 : 3'd4) && !rd_valid && !rv && !v2) st <= S_IDLE;
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
