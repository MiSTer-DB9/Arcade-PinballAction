//============================================================================
// Pinball Action (Tehkan 1985) - MiSTer FPGA Core
//
// Copyright (C) 2024
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation; either version 2 of the License, or (at your option)
// any later version
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: USER_OSD + per-pin push-pull mask, USER_IO widened to 8 bits
	output        USER_OSD,
	output  [7:0] USER_PP,
	input   [7:0] USER_IN,
	output  [7:0] USER_OUT,
	// [MiSTer-DB9 END]

	input         OSD_STATUS
);

//////////////////////////////////////////////////////////////////
// Unused framework ports - tie off cleanly
//////////////////////////////////////////////////////////////////

assign    ADC_BUS        = 'Z;
// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: USER_PP driven by wrapper; USER_OUT driven by joydb (USER_OUT_DRIVE) below
assign USER_PP = USER_PP_DRIVE;
// [MiSTer-DB9 END]
assign    {UART_RTS, UART_TXD, UART_DTR}   =  0;
assign    {SD_SCK, SD_MOSI, SD_CS}         =  'Z;
assign    {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
          SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
          SDRAM_nRAS, SDRAM_nCS}        = 'Z;
// assign    {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN,
//           DDRAM_BE, DDRAM_RD, DDRAM_WE}  = '0;
// DDRAM driven by screen_rotate

// assign VGA_SL           = 0;
// VGA_SL driven by arcade_video
assign VGA_F1           = 0;
assign VGA_SCALER       = 0;
assign VGA_DISABLE      = 0;
assign HDMI_FREEZE      = 0;
assign HDMI_BLACKOUT    = 0;
assign HDMI_BOB_DEINT   = 0;

assign LED_DISK         = 0;
assign LED_POWER        = 0;
assign BUTTONS          = 0;

//////////////////////////////////////////////////////////////////
// OSD / HPS configuration string
//
// ROM loading layout (ioctl_index values):
//   0x00 - Main CPU ROM  (maincpu, up to 40KB: 0000-9FFF)
//   0x01 - Audio CPU ROM (audiocpu, 8KB)
//   0x02 - FG chars      (fgchars, 24KB: three 8KB ROMs)
//   0x03 - BG chars      (bgchars, 64KB: four 16KB ROMs)
//   0x04 - Sprites       (sprites, 24KB: three 8KB ROMs)
//
// MRA file will map MAME ROM regions to these indices
//////////////////////////////////////////////////////////////////

`include "build_id.v"

localparam CONF_STR = {
    "PinballAction;;",
     "-;",
    "O2,Flip,Off,On;",
    "OFG,Rotate,None,CW 90,180,CCW 90;",
    "OU,Flippers,Normal,Split Controllers;",
    "-;",
    "O48,Analog HPos,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
    "O9D,Analog VPos,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
    "-;",
    // [MiSTer-DB9-Pro BEGIN] - Saturn-first joy_type (canonical bit notation)
    "O[127:126],UserIO Joystick,Off,Saturn,DB9MD,DB15;",
    "O[125],UserIO Players, 1 Player,2 Players;",
    // [MiSTer-DB9-Pro END]
    "DIP;",
    "OJK,Lives,3,4,5,2;",
    "OL,Cabinet,Upright,Cocktail;",
    "OE,Demo Sounds,On,Off;",
    "OMO,Bonus Life,70k 200k,70k 200k 1000k,100k,100k 300k,100k 300k 1000k,200k,200k 1000k,None;",
    "OP,Extra,Easy,Hard;",
    "OQR,Difficulty Flippers,Easy,Medium,Hard,Hardest;",
    "OST,Difficulty Outlanes,Easy,Medium,Hard,Hardest;",
    "-;",
    "R0,Reset;",
    "J1,Flipper L,Flipper R,Nudge,Launch,Start 1P,Start 2P,Coin,Pause;",
    "jn,A,B,X,Y,Start,Select,R,L;",
    "V,v",`BUILD_DATE
};

//////////////////////////////////////////////////////////////////
// HPS Interface
//////////////////////////////////////////////////////////////////

wire  [1:0]    buttons;
wire  [127:0]  status;
wire  [10:0]   ps2_key;
wire           forced_scandoubler;

function signed [8:0] status_s5_to_s9(input [4:0] v);
begin
   status_s5_to_s9 = {{4{v[4]}}, v};
end
endfunction

wire  signed   [8:0] h_pos_adj_osd = status_s5_to_s9(status[8:4]);
wire  signed   [8:0] v_pos_adj_osd = status_s5_to_s9(status[13:9]);

wire  osd_flip = status[2];
wire  split_flippers = status[30];
wire  [1:0] rotate_osd = status[16:15];

// Rotation decode:
//   00 = None:   no_rotate=1, rotate_ccw=x, flip=0
//   01 = CW 90:  no_rotate=0, rotate_ccw=0, flip=0
//   10 = 180:    no_rotate=1, rotate_ccw=x, flip=1
//   11 = CCW 90: no_rotate=0, rotate_ccw=1, flip=0
wire rotate_no     = (rotate_osd == 2'b00) || (rotate_osd == 2'b10);
wire rotate_ccw    = (rotate_osd == 2'b11);
wire rotate_flip   = (rotate_osd == 2'b10);

// Layer alignment baselines
// Flip and non-flip modes require different offsets to keep
// foreground, background and sprite layers aligned

localparam signed [8:0] FLIP_FG_X_BASELINE      =  9'sd0;
localparam signed [8:0] FLIP_FG_Y_BASELINE      =  9'sd0;
localparam signed [8:0] FLIP_BG_X_BASELINE      =  9'sd0;
localparam signed [8:0] FLIP_BG_Y_BASELINE      =  9'sd0;
localparam signed [8:0] FLIP_SPR_X_BASELINE     =  -9'sd1;
localparam signed [8:0] FLIP_SPR_Y_BASELINE     =  9'sd0;

localparam signed [8:0] NONFLIP_FG_X_BASELINE   =  9'sd0;
localparam signed [8:0] NONFLIP_FG_Y_BASELINE   =  -9'sd2;
localparam signed [8:0] NONFLIP_BG_X_BASELINE   =  9'sd0;
localparam signed [8:0] NONFLIP_BG_Y_BASELINE   =  -9'sd2;
localparam signed [8:0] NONFLIP_SPR_X_BASELINE  =  9'sd16;
localparam signed [8:0] NONFLIP_SPR_Y_BASELINE  =  -9'sd2;

wire signed [8:0] fg_x_adj    = osd_flip ? FLIP_FG_X_BASELINE  : NONFLIP_FG_X_BASELINE;
wire signed [8:0] fg_y_adj    = osd_flip ? FLIP_FG_Y_BASELINE  : NONFLIP_FG_Y_BASELINE;

wire signed [8:0] bg_x_adj    = osd_flip ? FLIP_BG_X_BASELINE  : NONFLIP_BG_X_BASELINE;
wire signed [8:0] bg_y_adj    = osd_flip ? FLIP_BG_Y_BASELINE  : NONFLIP_BG_Y_BASELINE;

wire signed [8:0] spr_x_adj   = osd_flip ? FLIP_SPR_X_BASELINE : NONFLIP_SPR_X_BASELINE;
wire signed [8:0] spr_y_adj   = osd_flip ? FLIP_SPR_Y_BASELINE : NONFLIP_SPR_Y_BASELINE;

// Joystick inputs - 6-button layout
wire [31:0] joy0, joy1;

// IOCTL - ROM loading from HPS
wire           ioctl_download;
wire  [7:0]    ioctl_index;
wire           ioctl_wr;
wire  [24:0]   ioctl_addr;
wire  [7:0]    ioctl_dout;

// DIP switches are implemented through CONF_STR status bits
// rather than MRA <switches> entries. The game reads:
//
//   E604 = DSW1
//   E605 = DSW2
//
// Status bit mapping:
//
//   status[20:19] = Lives
//   status[21]    = Cabinet
//   status[14]    = Demo Sounds
//   status[24:22] = Bonus Life
//   status[25]    = Extra
//   status[27:26] = Flipper Difficulty
//   status[29:28] = Outlane Difficulty

wire [1:0]  dip_lives         = status[20:19];
wire        dip_cabinet       = status[21];
wire        dip_demo_sounds   = status[14];

wire [2:0]  dip_bonus_life    = status[24:22];
wire        dip_extra         = status[25];
wire [1:0]  dip_diff_flip     = status[27:26];
wire [1:0]  dip_diff_outlane  = status[29:28];

// Fixed coinage

wire [1:0]  dip_coin_a = 2'b00; // fixed 1C/1C candidate
wire [1:0]  dip_coin_b = 2'b00; // fixed 1C/1C candidate

// DSW1 layout:
//   bits 1:0 = Coin A
//   bits 3:2 = Coin B
//   bits 5:4 = Lives
//   bit  6   = Cabinet
//   bit  7   = Demo Sounds
//
// Demo Sounds OSD string is "On,Off":
//   status[14] = 0 -> On
//   status[14] = 1 -> Off
wire [7:0] dip_sw1_core = {
    dip_demo_sounds,
    dip_cabinet,
    dip_lives,
    dip_coin_b,
    dip_coin_a
};

// DSW2 layout:
//   bits 2:0 = Bonus Life
//   bit  3   = Extra
//   bits 5:4 = Difficulty Flippers
//   bits 7:6 = Difficulty Outlanes
wire [7:0] dip_sw2_core = {
    dip_diff_outlane,
    dip_diff_flip,
    dip_extra,
    dip_bonus_life
};

wire [15:0] dip_sw = {dip_sw2_core, dip_sw1_core};

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joydb wrapper
wire         CLK_JOY = CLK_50M;                 // Assign clock between 40-50Mhz
wire   [1:0] joy_type_raw    = status[127:126]; // 0=Off, 1=Saturn, 2=DB9MD, 3=DB15
wire         joy_2p          = status[125];
// SNAC cores: replace 1'b0 with the core's SNAC enable expression so SNAC
// preempts the joydb wrapper on shared USER_IO pins. Default 1'b0 is no-op.
wire         snac_active     = 1'b0;
// MT32-pi cores on primary USER_IO: replace 1'b0 with the core's MT32-active
// expression (e.g. `mt32_use` under `ifndef SECOND_MT32`, `~mt32_disable` for
// TRS-80's inverted polarity). Suppresses the OSD-open autodetect probe so it
// doesn't read the RPi's I2C master traffic as a ghost Saturn signature.
wire         mt32_primary_active = 1'b0;
wire   [1:0] joy_type        = snac_active ? 2'd0 : joy_type_raw;
wire         joy_db9md_en    = (joy_type == 2'd2);
wire         joy_db15_en     = (joy_type == 2'd3);
wire         joy_any_en      = |joy_type;
// [MiSTer-DB9 END]

// [MiSTer-DB9-Pro BEGIN] - Saturn key gate
wire         saturn_unlocked;                   // driven by hps_io UIO_DB9_KEY (0xFE)
// [MiSTer-DB9-Pro END]

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joydb wrapper wires + instance
wire   [7:0] USER_OUT_DRIVE;
wire   [7:0] USER_PP_DRIVE;
wire  [15:0] joydb_1, joydb_2;
wire         joydb_1ena, joydb_2ena;
wire  [15:0] joy_raw_payload;
// Programmable-remap matrix (joydb_remap inside joydb): clk_sys carries the
// 0xFD selector load (HPS-bus domain). joydb_*_mapped are the MiSTer-standard
// joystick words the core consumes at its joy0_USB merge point. db9_remap_*
// are driven by the hps_io instance (see the .db9_remap_* bindings there).
// Until a core consumes joydb_*_mapped (Layer B), the matrix stays at identity
// and synthesis prunes it -- binding these is dormant + fleet-safe.
wire  [15:0] joydb_1_mapped, joydb_2_mapped;
wire         db9_remap_cmd;
wire   [5:0] db9_remap_byte_cnt;
wire  [15:0] db9_remap_din;

// [MiSTer-DB9 BEGIN] - DB9 remap factory default (used until Main_MiSTer streams UIO 0xFD)
// Derived from CONF_STR J1, same rule as db9_map.cpp; lets the core work on a stock MiSTer binary.
// DB15:  Flipper L=A, Flipper R=B, Nudge=C, Launch=D, Start 1P=START, Start 2P=E, Coin=SELECT, Pause=F
// DB9MD: Flipper L=A, Flipper R=B, Nudge=C, Launch=X, Start 1P=START, Start 2P=Y, Coin=MODE, Pause=Z
wire  [35:0] db9_remap_default_db15  = 36'hF9B8A7654;
wire  [35:0] db9_remap_default_db9md = 36'hF9B8A7654;
// [MiSTer-DB9 END]
joydb joydb (
  .clk             ( CLK_JOY         ),
  .clk_sys         ( clk_sys            ),
  .USER_IN         ( USER_IN         ),
  .OSD_STATUS          ( OSD_STATUS          ),
  .snac_active         ( snac_active         ),
  .mt32_primary_active ( mt32_primary_active ),
  .joy_type        ( joy_type        ),
  .joy_2p          ( joy_2p          ),
  .saturn_unlocked ( saturn_unlocked ),
  .USER_OUT_DRIVE  ( USER_OUT_DRIVE  ),
  .USER_PP_DRIVE   ( USER_PP_DRIVE   ),
  .USER_OSD        ( USER_OSD        ),
  .joydb_1         ( joydb_1         ),
  .joydb_2         ( joydb_2         ),
  .joydb_1ena      ( joydb_1ena      ),
  .joydb_2ena      ( joydb_2ena      ),
  .remap_cmd       ( db9_remap_cmd      ),
  .remap_byte_cnt  ( db9_remap_byte_cnt ),
  .remap_din       ( db9_remap_din      ),
  .remap_default_db15  ( db9_remap_default_db15  ),
  .remap_default_db9md ( db9_remap_default_db9md ),
  .joydb_1_mapped  ( joydb_1_mapped     ),
  .joydb_2_mapped  ( joydb_2_mapped     ),
  .joy_raw         ( joy_raw_payload )
);

assign USER_OUT = USER_OUT_DRIVE;
// [MiSTer-DB9 END]

// [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: rename USB joystick wires
wire [31:0] joystick_0_USB, joystick_1_USB;
// [MiSTer-DB9 END]

hps_io #(
    .CONF_STR(CONF_STR),
    .PS2DIV(1000),
    .WIDE(0)
) hps_io (
    .clk_sys    (clk_sys),
    .HPS_BUS    (HPS_BUS),
    .buttons    (buttons),
    .status     (status),
    .status_menumask(0),

    .forced_scandoubler(forced_scandoubler),

    .ps2_key    (ps2_key),

    .joystick_0  (joystick_0_USB),
    .joystick_1  (joystick_1_USB),

    .ioctl_download   (ioctl_download),
    .ioctl_index      (ioctl_index),
    .ioctl_wr         (ioctl_wr),
    .ioctl_addr       (ioctl_addr),
    .ioctl_dout       (ioctl_dout),

    .status_in   ({status[127:1], 1'b0}),
    .status_set  (1'b0),
    // [MiSTer-DB9 BEGIN] - DB9/SNAC8 support: joy_raw
    .joy_raw(joy_raw_payload),
    // programmable remap matrix selector load (UIO_DB9_MAP 0xFD)
    .db9_remap_cmd(db9_remap_cmd),
    .db9_remap_byte_cnt(db9_remap_byte_cnt),
    .db9_remap_din(db9_remap_din),
    // [MiSTer-DB9 END]
    // [MiSTer-DB9-Pro BEGIN] - Saturn key gate
    .saturn_unlocked(saturn_unlocked)
    // [MiSTer-DB9-Pro END]
);

// [MiSTer-DB9-Pro BEGIN] - DB controllers muted while OSD is open
// joydb_*_mapped is already in MiSTer-standard J1 order, identical to the USB
// joystick word, so it replaces the USB input as-is.
assign joy0 = joydb_1ena ? (OSD_STATUS ? 16'b0 : joydb_1_mapped) : joystick_0_USB;
assign joy1 = joydb_2ena ? (OSD_STATUS ? 16'b0 : joydb_2_mapped) : joydb_1ena ? joystick_0_USB : joystick_1_USB;
// [MiSTer-DB9-Pro END]

//////////////////////////////////////////////////////////////////
// Clocks
//////////////////////////////////////////////////////////////////

wire clk_sys;   // System clock
wire clk_vid;   // Video clock
wire pll_locked;

pll pll (
    .refclk   (CLK_50M),
    .rst    (0),
    .outclk_0 (clk_sys),
    .outclk_1 (clk_vid),
    .locked   (pll_locked)
);

//////////////////////////////////////////////////////////////////
// Reset
//////////////////////////////////////////////////////////////////

reg [15:0] reset_counter;
wire reset_req = RESET | status[0] | buttons[1] | ~pll_locked | ioctl_download;

always @(posedge clk_sys) begin
    if (reset_req)
        reset_counter <= 16'hFFFF;
    else if (reset_counter != 0)
        reset_counter <= reset_counter - 1'd1;
end

wire reset = (reset_counter != 0);

//////////////////////////////////////////////////////////////////
// ROM write routing
//////////////////////////////////////////////////////////////////

wire rom_wr = ioctl_wr & ioctl_download;

wire rom_maincpu_wr     = rom_wr & (ioctl_index == 8'h00);
wire rom_audiocpu_wr    = rom_wr & (ioctl_index == 8'h01);
wire rom_fgchars_wr     = rom_wr & (ioctl_index == 8'h02);
wire rom_bgchars_wr     = rom_wr & (ioctl_index == 8'h03);
wire rom_sprites_wr     = rom_wr & (ioctl_index == 8'h04);

//////////////////////////////////////////////////////////////////
// Video signals from core
//////////////////////////////////////////////////////////////////

wire ce_pix;
wire HBlank, VBlank, HSync, VSync;
wire [3:0] R, G, B;

//////////////////////////////////////////////////////////////////
// Audio from core
//////////////////////////////////////////////////////////////////

wire [15:0] audio_l, audio_r;

//////////////////////////////////////////////////////////////////
// MiSTer input mapping
//
// Normal mode:
//   Controller 1 controls P1
//   Controller 2 controls P2
//
// Split Controllers mode:
//   Controller 1 controls the left flipper
//   Controller 2 controls the right flipper
//   Launch and nudge can be triggered from either controller
//////////////////////////////////////////////////////////////////

wire p1_flipper_l = joy0[4];
wire p1_flipper_r = split_flippers ? joy1[5] : joy0[5];
wire p1_launch    = split_flippers ? (joy0[6] | joy1[6]) : joy0[6];
wire p1_nudge     = split_flippers ? (joy0[7] | joy1[7]) : joy0[7];

wire p2_flipper_l = joy1[4];
wire p2_flipper_r = joy1[5];
wire p2_launch    = joy1[6];
wire p2_nudge     = joy1[7];

wire p1_start     = joy0[8]  | joy1[8];
wire p2_start     = joy0[9]  | joy1[9];

wire coin1        = joy0[10] | joy1[10];
wire pause_btn    = joy0[11] | joy1[11];

//////////////////////////////////////////////////////////////////
// Pause
//////////////////////////////////////////////////////////////////

reg pause_btn_prev;
reg paused;

always @(posedge clk_sys) begin
    if (reset) begin
        paused         <= 1'b0;
        pause_btn_prev <= 1'b0;
    end else begin
        pause_btn_prev <= pause_btn;
    if (pause_btn && !pause_btn_prev)
        paused <= ~paused;
    end
end

//////////////////////////////////////////////////////////////////
// Core instantiation
//////////////////////////////////////////////////////////////////

pbaction pbaction (
    .clk_sys    (clk_sys),
    .reset      (reset),

    // ROM download
    .ioctl_addr       (ioctl_addr[15:0]),
    .ioctl_data       (ioctl_dout),
    .rom_maincpu_wr   (rom_maincpu_wr),
    .rom_audiocpu_wr  (rom_audiocpu_wr),
    .rom_fgchars_wr   (rom_fgchars_wr),
    .rom_bgchars_wr   (rom_bgchars_wr),
    .rom_sprites_wr   (rom_sprites_wr),

    // Video outputs
    .ce_pix        (ce_pix),
    .HBlank        (HBlank),
    .VBlank        (VBlank),
    .HSync         (HSync),
    .VSync         (VSync),
    .R             (R),
    .G             (G),
    .B             (B),

    // Audio outputs
    .audio_l       (audio_l),
    .audio_r       (audio_r),

    // Inputs
    .p1_flipper_l  (p1_flipper_l),
    .p1_flipper_r  (p1_flipper_r),
    .p1_nudge      (p1_nudge),
    .p1_launch     (p1_launch),

    .p2_flipper_l  (p2_flipper_l),
    .p2_flipper_r  (p2_flipper_r),
    .p2_nudge      (p2_nudge),
    .p2_launch     (p2_launch),

    .p1_start      (p1_start),
    .p2_start      (p2_start),
    .coin1         (coin1),

    // DIP switches (from OSD/MRA)
    .dip_sw1       (dip_sw[7:0]),
    .dip_sw2       (dip_sw[15:8]),

    // Flip
    .flip          (status[2]),
    
    .fg_x_adj      (fg_x_adj),
    .fg_y_adj      (fg_y_adj),
    .bg_x_adj      (bg_x_adj),
    .bg_y_adj      (bg_y_adj),
    .spr_x_adj     (spr_x_adj),
    .spr_y_adj     (spr_y_adj),

    .h_pos_adj     (h_pos_adj_osd),
    .v_pos_adj     (v_pos_adj_osd),

    .paused        (paused)
);

//////////////////////////////////////////////////////////////////
// MiSTer Video Output
//////////////////////////////////////////////////////////////////

// Intermediate wires between arcade_video and screen_rotate
wire        av_clk_video;
wire        av_ce_pixel;
wire  [7:0] av_vga_r, av_vga_g, av_vga_b;
wire        av_vga_hs, av_vga_vs, av_vga_de;
wire  [1:0] av_vga_sl;

arcade_video #(.WIDTH(256), .DW(12)) arcade_video (
    .clk_video        (clk_vid),
    .ce_pix           (ce_pix),
    .RGB_in           ({R, G, B}),
    .HBlank           (HBlank),
    .VBlank           (VBlank),
    .HSync            (HSync),
    .VSync            (VSync),
    .CLK_VIDEO        (av_clk_video),
    .CE_PIXEL         (av_ce_pixel),
    .VGA_R            (av_vga_r),
    .VGA_G            (av_vga_g),
    .VGA_B            (av_vga_b),
    .VGA_HS           (av_vga_hs),
    .VGA_VS           (av_vga_vs),
    .VGA_DE           (av_vga_de),
    .VGA_SL           (av_vga_sl),
    .fx               (3'b000),
    .forced_scandoubler(forced_scandoubler),
    .gamma_bus        ()
);

wire video_rotated;

screen_rotate screen_rotate (
    .CLK_VIDEO        (av_clk_video),
    .CE_PIXEL         (av_ce_pixel),
    .VGA_R            (av_vga_r),
    .VGA_G            (av_vga_g),
    .VGA_B            (av_vga_b),
    .VGA_HS           (av_vga_hs),
    .VGA_VS           (av_vga_vs),
    .VGA_DE           (av_vga_de),
    .rotate_ccw       (rotate_ccw),
    .no_rotate        (rotate_no),
    .flip             (rotate_flip),
    .video_rotated    (video_rotated),
    .FB_EN            (FB_EN),
    .FB_FORMAT        (FB_FORMAT),
    .FB_WIDTH         (FB_WIDTH),
    .FB_HEIGHT        (FB_HEIGHT),
    .FB_BASE          (FB_BASE),
    .FB_STRIDE        (FB_STRIDE),
    .FB_VBL           (FB_VBL),
    .FB_LL            (FB_LL),
    .DDRAM_CLK        (DDRAM_CLK),
    .DDRAM_BUSY       (DDRAM_BUSY),
    .DDRAM_BURSTCNT   (DDRAM_BURSTCNT),
    .DDRAM_ADDR       (DDRAM_ADDR),
    .DDRAM_DIN        (DDRAM_DIN),
    .DDRAM_BE         (DDRAM_BE),
    .DDRAM_WE         (DDRAM_WE),
    .DDRAM_RD         (DDRAM_RD)
);

assign CLK_VIDEO = av_clk_video;
assign CE_PIXEL  = av_ce_pixel;
assign VGA_R     = av_vga_r;
assign VGA_G     = av_vga_g;
assign VGA_B     = av_vga_b;
assign VGA_HS    = av_vga_hs;
assign VGA_VS    = av_vga_vs;
assign VGA_DE    = av_vga_de;
assign VGA_SL    = av_vga_sl;

//////////////////////////////////////////////////////////////////
// MiSTer Audio Output
//////////////////////////////////////////////////////////////////

assign AUDIO_S    = 1;        // signed audio
assign AUDIO_L    = audio_l;
assign AUDIO_R    = audio_r;
assign AUDIO_MIX  = 0;

//////////////////////////////////////////////////////////////////
// Aspect ratio
// Vertical game displayed in 3:4 portrait aspect ratio
//////////////////////////////////////////////////////////////////

// Aspect ratio depends on rotation state
// No rotation / 180: portrait game, 3:4 width:height
// CW90 / CCW90: screen_rotate outputs landscape, 4:3
wire rotate_active = (rotate_osd == 2'b01) || (rotate_osd == 2'b11);
assign VIDEO_ARX  = rotate_active ? 13'd3 : 13'd4;
assign VIDEO_ARY  = rotate_active ? 13'd4 : 13'd3;

//////////////////////////////////////////////////////////////////
// Activity LED
//////////////////////////////////////////////////////////////////

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0]
                              : act_cnt[25:18] <= act_cnt[7:0];

endmodule
