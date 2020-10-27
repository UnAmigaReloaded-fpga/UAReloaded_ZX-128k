//============================================================================
// Sinclair ZX Spectrum host board
// 
//  Port to MIST board. 
//  Copyright (C) 2015 Sorgelig
//
//  Based on sample ZX Spectrum code by Goran Devic
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

//============================================================================
//
//  Multicore 2 Top by Victor Trucco
//
//============================================================================

`default_nettype none

module zxspectrum
(
  // Clocks
	input wire	clock_50_i,

	// Buttons
	input wire [4:1]	btn_n_i,

	// SRAMs (AS7C34096)
	output wire	[18:0]sram_addr_o  = 19'b00000000000000000000,
	inout wire	[7:0]sram_data_io	= 8'bzzzzzzzz,
	output wire	sram_we_n_o		= 1'b1,
	output wire	sram_oe_n_o		= 1'b1,
		
	// SDRAM	(H57V256)
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQMH,
	output        SDRAM_DQML,
	output        SDRAM_CKE,
	output        SDRAM_nCS,
	output        SDRAM_nWE,
	output        SDRAM_nRAS,
	output        SDRAM_nCAS,
	output        SDRAM_CLK,

	// PS2
	inout wire	ps2_clk_io			= 1'bz,
	inout wire	ps2_data_io			= 1'bz,
	inout wire	ps2_mouse_clk_io  = 1'bz,
	inout wire	ps2_mouse_data_io = 1'bz,

	// SD Card
	output wire	sd_cs_n_o			= 1'b1,
	output wire	sd_sclk_o			= 1'b0,
	output wire	sd_mosi_o			= 1'b0,
	input wire	sd_miso_i,

	// Joysticks
	input wire	joy1_up_i,
	input wire	joy1_down_i,
	input wire	joy1_left_i,
	input wire	joy1_right_i,
	input wire	joy1_p6_i,
	input wire	joy1_p9_i,
	input wire	joy2_up_i,
	input wire	joy2_down_i,
	input wire	joy2_left_i,
	input wire	joy2_right_i,
	input wire	joy2_p6_i,
	input wire	joy2_p9_i,
	output wire	joyX_p7_o			= 1'b1,

	// Audio
	input wire	ear_i,
	input  wire  ear_maxduino,
	output wire	mic_o					= 1'b0,
   // SONIDO I2S
   output wire SDIN,
   output wire SCLK,
   output wire LRCLK,
   output wire MCLK                    = 1'bz,

		// VGA
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
   output        VGA_CLOCK,
	output        VGA_BLANK,

	//STM32
	input wire	stm_tx_i,
	output wire	stm_rx_o,
	output wire	stm_rst_o			= 1'bz, // '0' to hold the microcontroller reset line, to free the SD card
		
	inout wire	stm_b8_io, 
	inout wire	stm_b9_io,
	input wire	stm_a15_i,


	input         SPI_SCK,
	output        SPI_DO,
	input         SPI_DI,
	input         SPI_SS2,
	
	output        LED
);

assign stm_rst_o			= 1'bz;
assign sd_cs_n_o			= 1'bz;
assign sd_sclk_o			= 1'bz;
assign sd_mosi_o			= 1'bz;

//assign sram_addr_o[20]  = 1'b0;
//assign sram_addr_o[19]  = 1'b0;


assign LED = ~(ioctl_download | tape_led);

localparam CONF_BDI   = "(BDI)";
localparam CONF_PLUSD = "(+D) ";

localparam CONF_STR = {
	"P,Spectrum.dat;", //15
	"S,TAP/CSW/TZX,Load *.TAP.CSW.TZX;", //33
	//"S,TRD/IMG/DSK/MGT,Load *.TRD.IMG.DSK.MGT;", //41
	"O6,Fast tape load,On,Off;", //25
	"O7,Joystick,J1 K J2 S,J1 S J2 K;", //32
	"O89,Video timings,ULA-128,ULA-48,Pentagon;", //42
	"OFG,Scandoubler Fx,None,HQ2x,25%,50%;", //37
	"OAC,Memory,128K,Pentagon,Profi,48K,+2A +3;", //42
	"ODE,Features,ULA+ & Timex,ULA+,Timex,None;", //42
//	"OHI,MMC Card,Off,divMMC,ZXMMC;", //30
	"T0,Reset;", //9
	"V,v3.40." //8
};

localparam STRLEN = 15 + 33 + 25 + 32 + 42 + 37 + 42 + 42 + 9 + 8;

////////////////////   CLOCKS   ///////////////////
wire clk_sys;
wire locked;

pll pll
(
	.inclk0(clock_50_i),
	.c0(clk_sys),
	.c1(SDRAM_CLK),
	.c2(clk_56),
	.locked(locked)
);

reg  ce_psg;  //1.75MHz
reg  ce_7mp;
reg  ce_7mn;
reg  ce_28m;
wire clk_56;

reg  pause;
reg  cpu_en = 1;
reg  ce_cpu_tp;
reg  ce_cpu_tn;

wire ce_cpu_p = cpu_en & cpu_p;
wire ce_cpu_n = cpu_en & cpu_n;
wire ce_cpu   = cpu_en & ce_cpu_tp;
wire ce_wd1793 = ce_cpu;
wire ce_u765 = ce_cpu;
wire ce_tape = ce_cpu;

wire cpu_p = ~&turbo ? ce_cpu_tp : ce_cpu_sp;
wire cpu_n = ~&turbo ? ce_cpu_tn : ce_cpu_sn;

always @(posedge clk_sys) begin
	reg [5:0] counter = 0;

	counter <=  counter + 1'd1;

	ce_28m  <= !counter[1:0];
	ce_7mp  <= !counter[3] & !counter[2:0];
	ce_7mn  <=  counter[3] & !counter[2:0];
	ce_psg  <= !counter[5:0] & ~pause;

	ce_cpu_tp <= !(counter & turbo);
	ce_cpu_tn <= !((counter & turbo) ^ turbo ^ turbo[4:1]);
end

reg [4:0] turbo = 5'b11111, turbo_key = 5'b11111;
always @(posedge clk_sys) begin
	reg [9:4] old_Fn;
	old_Fn <= Fn[9:4];

	if(reset) pause <= 0;

	if(!mod) begin
		if(~old_Fn[4] & Fn[4]) turbo_key <= 5'b11111; //3.5
		if(~old_Fn[5] & Fn[5]) turbo_key <= 5'b01111; //7
		if(~old_Fn[6] & Fn[6]) turbo_key <= 5'b00111; //14
		if(~old_Fn[7] & Fn[7]) turbo_key <= 5'b00011; //28
		if(~old_Fn[8] & Fn[8]) turbo_key <= 5'b00001; //56
		if(~old_Fn[9] & Fn[9]) pause <= ~pause;
	end
end

wire [4:0] turbo_req = (tape_active & ~status[6]) ? 5'b00001 : turbo_key;
always @(posedge clk_sys) begin
	reg [1:0] timeout;

	if(cpu_n) begin
		if(timeout) timeout <= timeout + 1'd1;
		if(turbo != turbo_req) begin
			cpu_en  <= 0;
			timeout <= 1;
			turbo   <= turbo_req;
		end else if(!cpu_en & !timeout & ram_ready) begin
			cpu_en  <= ~pause;
		end else if(!turbo[4:3] & !ram_ready) begin // SDRAM wait for 14MHz/28MHz/56MHz turbo

			cpu_en  <= 0;
		end else if(cpu_en & pause) begin
			cpu_en  <= 0;
		end
	end
end


//////////////////   MIST ARM I/O   ///////////////////
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire  [7:0] joystick_0;
wire  [7:0] joystick_1;
wire  [7:0] joy0 = status[7] ? ~{joy2_s[7:4], joy2_s[0], joy2_s[1], joy2_s[2], joy2_s[3]} : ~{joy1_s[7:4], joy1_s[0], joy1_s[1], joy1_s[2], joy1_s[3]}; // Kempston
wire  [7:0] joy1 = status[7] ? ~{joy1_s[7:4], joy1_s[0], joy1_s[1], joy1_s[2], joy1_s[3]} : ~{joy2_s[7:4], joy2_s[0], joy2_s[1], joy2_s[2], joy2_s[3]}; // Sinclair

//-- joy_s format MXYZ SACB RLDU

wire  [1:0] buttons;
wire  [1:0] switches;
wire        scandoubler_disable;
wire        ypbpr;
wire [31:0] status;

wire 			sd_rd_plus3;
wire 			sd_wr_plus3;
wire [31:0] sd_lba_plus3;
wire [7:0]  sd_buff_din_plus3;

wire 			sd_rd_wd;
wire 			sd_wr_wd;
wire [31:0] sd_lba_wd;
wire [7:0]  sd_buff_din_wd;

wire        sd_busy_mmc;
wire        sd_rd_mmc;
wire        sd_wr_mmc;
wire [31:0] sd_lba_mmc;
wire  [7:0] sd_buff_din_mmc;

wire [31:0] sd_lba = sd_busy_mmc ? sd_lba_mmc : (plus3_fdd_ready ? sd_lba_plus3 : sd_lba_wd);
wire  [1:0] sd_rd = { sd_rd_plus3 | sd_rd_wd, sd_rd_mmc };
wire  [1:0] sd_wr = { sd_wr_plus3 | sd_wr_wd, sd_wr_mmc };

wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din = sd_busy_mmc ? sd_buff_din_mmc : (plus3_fdd_ready ? sd_buff_din_plus3 : sd_buff_din_wd);
wire        sd_buff_wr;
wire  [1:0] img_mounted;
wire [31:0] img_size;

wire        sd_ack_conf;
wire        sd_conf;
wire        sd_sdhc;

wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_download;
wire  [7:0] ioctl_index;

wire osd_enable;

/*
mist_io #(.STRLEN(STRLEN+5)) mist_io
(
	.*,
	.clk_sys(clk_sys),

	.SPI_SCK(SPI_SCK),
	.SPI_SS2(SPI_SS2),
	.SPI_DO(SPI_DO),
	.SPI_DI(SPI_DI),
	.CONF_DATA0(0),
		
	.data_in( osd_s ),
	
	.ioctl_ce(1),
	.conf_str({CONF_STR, plusd_en ? CONF_PLUSD : CONF_BDI}),

	// unused
	.ps2_kbd_clk(),
	.ps2_kbd_data(),
	.ps2_mouse_clk(),
	.ps2_mouse_data(),
	.joystick_analog_0(),
	.joystick_analog_1()
);
*/

data_io #(.STRLEN( STRLEN + 5 )) data_io(
	.clk_sys       ( clk_sys      ),
	.SPI_SCK       ( SPI_SCK      ),
	.SPI_SS2       ( SPI_SS2      ),
	.SPI_DI        ( SPI_DI       ),
	.SPI_DO        ( SPI_DO       ),
	
	.data_in		 	( osd_s & keys_s ),
	.conf_str({CONF_STR, plusd_en ? CONF_PLUSD : CONF_BDI}),
	.status			( status ),
	
	.img_mounted	( img_mounted ),
	.img_size		( img_size ),   // size of image in bytes
	
	.ioctl_download( ioctl_download  ),
	.ioctl_index   ( ioctl_index  ),
	.ioctl_wr      ( ioctl_wr     ),
	.ioctl_addr    ( ioctl_addr   ),
	.ioctl_dout    ( ioctl_dout   )
);


///////////////////   CPU   ///////////////////
wire [15:0] addr;
wire  [7:0] cpu_din;
wire  [7:0] cpu_dout;
wire        nM1;
wire        nMREQ;
wire        nIORQ;
wire        nRD;
wire        nWR;
wire        nRFSH;
wire        nBUSACK;
wire        nINT;
wire        nBUSRQ = ~ioctl_download;

wire        io_wr = ~nIORQ & ~nWR & nM1;
wire        io_rd = ~nIORQ & ~nRD & nM1;
wire        m1    = ~nM1 & ~nMREQ;

wire[211:0]	cpu_reg;  // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
wire [15:0] reg_DE  = cpu_reg[111:96];
wire  [7:0] reg_A   = cpu_reg[7:0];


T80pa cpu
(
	.RESET_n(~reset),
	.CLK(clk_sys),
	.CEN_p(ce_cpu_p),
	.CEN_n(ce_cpu_n),
	.WAIT_n(1),
	.INT_n(nINT),
	.NMI_n(~NMI),
	.BUSRQ_n(nBUSRQ),
	.M1_n(nM1),
	.MREQ_n(nMREQ),
	.IORQ_n(nIORQ),
	.RD_n(nRD),
	.WR_n(nWR),
	.RFSH_n(nRFSH),
	.HALT_n(1),
	.BUSAK_n(nBUSACK),
	.A(addr),
	.DO(cpu_dout),
	.DI(cpu_din),
	.REG(cpu_reg)
);


always_comb begin
	casex({nMREQ, tape_dout_en, ~nM1 | nIORQ | nRD, fdd_sel | fdd_sel2 | plus3_fdd, mf3_port, mmc_sel, addr[5:0]==8'h1F, portBF, addr[0], psg_enable, ulap_sel})
		'b00XXXXXXXXX: cpu_din = ram_dout;
		'b01XXXXXXXXX: cpu_din = tape_dout;
		'b1X01XXXXXXX: cpu_din = fdd_dout;
		'b1X001XXXXXX: cpu_din = (addr[14:13] == 2'b11 ? page_reg : page_reg_plus3);
		'b1X0001XXXXX: cpu_din = mmc_dout;
		'b1X00001XXXX: cpu_din = mouse_sel ? mouse_data : {2'b00, joy0[5:0]};
		'b1X000001XXX: cpu_din = {page_scr_copy, 7'b1111111};
		'b1X00000011X: cpu_din = (addr[14] ? sound_data : 8'hFF);
		'b1X000000101: cpu_din = ulap_dout;
		'b1X000000100: cpu_din = port_ff;
		'b1X0000000XX: cpu_din = {1'b1, ~tape_in, 1'b1, key_data[4:0] & ({5{addr[12]}} | ~{joy1[1:0], joy1[2], joy1[3], joy1[4]})};
		'b1X1XXXXXXXX: cpu_din = 8'hFF;
	endcase
end

reg init_reset = 1;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= ioctl_download;
	if(old_download & ~ioctl_download) init_reset <= 0;
end

reg  NMI;
reg  reset;
reg  cold_reset_btn;
reg  warm_reset_btn;
reg  shdw_reset_btn;
wire cold_reset = cold_reset_btn | init_reset;
wire warm_reset = warm_reset_btn;
wire shdw_reset = shdw_reset_btn & ~plus3;

always @(posedge clk_sys) begin
	reg old_F11;

	old_F11 <= Fn[11];

	reset <= ~btn_n_i[1] | status[0] | cold_reset | warm_reset | shdw_reset | Fn[10];

	if(reset | ~Fn[11] | (m1 & (addr == 'h66))) NMI <= 0;
	else if(~old_F11 & Fn[11] & (mod[2:1] == 0)) NMI <= 1;

	cold_reset_btn <= (mod[2:1] == 1) & Fn[11];
	warm_reset_btn <= (mod[2:1] == 2) & Fn[11];
	shdw_reset_btn <= (mod[2:1] == 3) & Fn[11];
end


//////////////////   MEMORY   //////////////////
wire        dma = (reset | ~nBUSACK) & ~nBUSRQ;
reg  [24:0] sdram_addr;
reg  [20:0] ram_addr;
reg   [7:0] ram_din;
reg         ram_we;
reg         ram_rd;
wire  [7:0] ram_dout;
wire        ram_ready;

always_comb begin
	casex({page_special, addr[15:14]})
		'b0_00: ram_addr = { 3'b101, page_rom,    addr[13:0]}; //ROM
		'b0_01: ram_addr = {        3'd5,         addr[13:0]}; //Non-special page modes
		'b0_10: ram_addr = {        3'd2,         addr[13:0]};
		'b0_11: ram_addr = {    page_ram,         addr[13:0]};
		'b1_00: ram_addr = { |page_reg_plus3[2:1],                      2'b00, addr[13:0]}; //Special page modes
		'b1_01: ram_addr = { |page_reg_plus3[2:1], &page_reg_plus3[2:1], 1'b1, addr[13:0]};
		'b1_10: ram_addr = { |page_reg_plus3[2:1],                      2'b10, addr[13:0]};
		'b1_11: ram_addr = { ~page_reg_plus3[2] & page_reg_plus3[1],    2'b11, addr[13:0]};
	endcase

	casex({dma, tape_req})
		'b1X: sdram_addr = ioctl_addr;
		'b01: sdram_addr = tape_addr;
		'b00: sdram_addr = ram_addr;
	endcase;

	casex({dma, tape_req})
		'b1X: ram_din = ioctl_dout;
		'b01: ram_din = 0;
		'b00: ram_din = cpu_dout;
	endcase

	casex({dma, tape_req})
		'b1X: ram_rd = 0;
		'b01: ram_rd = ~nMREQ;
		'b00: ram_rd = ~nMREQ & ~nRD;
	endcase

	casex({dma, tape_req})
		'b1X: ram_we = ioctl_wr;
		'b01: ram_we = 0;
		'b00: ram_we = (page_special | addr[15] | addr[14] | ((plusd_mem | mf128_mem) & addr[13])) & ~nMREQ & ~nWR;
	endcase
end

sdram ram
(
	.*,
	.init(~locked), //~locked
	.clk(clk_sys),
	.dout(ram_dout),
	.din (ram_din),
	.addr(sdram_addr),
	.wtbt(0),
	.we(ram_we),
	.rd(ram_rd),
	.ready(ram_ready)
);

wire vram_sel = (ram_addr[20:16] == 1) & ram_addr[14] & ~dma & ~tape_req;
vram vram
(
    .clock(clk_sys),

    .wraddress({ram_addr[15], ram_addr[13:0]}),
    .data(ram_din),
    .wren(ram_we & vram_sel),

    .rdaddress(vram_addr),
    .q(vram_dout)
);

(* maxfan = 10 *) reg	zx48;
(* maxfan = 10 *) reg	p1024;
(* maxfan = 10 *) reg	pf1024;
(* maxfan = 10 *) reg	plus3;
reg        page_scr_copy;
reg        shadow_rom;
reg  [7:0] page_reg;
reg  [7:0] page_reg_plus3;
reg  [7:0] page_reg_p1024;
wire       page_disable = zx48 | (~p1024 & page_reg[5]) | (p1024 & page_reg_p1024[2] & page_reg[5]);
wire       page_scr     = page_reg[3];
wire [5:0] page_ram     = {page_128k, page_reg[2:0]};
wire       page_write   = ~addr[15] & ~addr[1] & (addr[14] | ~plus3) & ~page_disable; //7ffd
wire       page_write_plus3 = ~addr[1] & addr[12] & ~addr[13] & ~addr[14] & ~addr[15] & plus3 & ~page_disable; //1ffd
wire       page_special = page_reg_plus3[0];
wire       motor_plus3 = page_reg_plus3[3];
wire       page_p1024 = addr[15] & addr[14] & addr[13] & ~addr[12] & ~addr[3]; //eff7
reg  [2:0] page_128k;

reg  [3:0] page_rom;
wire       active_48_rom = zx48 | (page_reg[4] & ~plus3) | (plus3 & page_reg[4] & page_reg_plus3[2] & ~page_special);

always_comb begin
	casex({shadow_rom, trdos_en, plusd_mem, mf128_mem, plus3})
		'b1XXXX: page_rom <= 4'b0100; //shadow
		'b01XXX: page_rom <= 4'b0101; //trdos
		'b001XX: page_rom <= 4'b1100; //plusd
		'b0001X: page_rom <= { 2'b11, plus3, ~plus3 }; //MF128/+3
		'b00001: page_rom <= { 2'b10, page_reg_plus3[2], page_reg[4] }; //+3
		'b00000: page_rom <= { zx48, 2'b11, zx48 | page_reg[4] }; //up to +2
	endcase
end

always @(posedge clk_sys) begin
	reg old_wr, old_m1, old_reset;
	reg [2:0] rmod;

	old_wr <= io_wr;
	old_m1 <= m1;
	
	old_reset <= reset;
	if(~old_reset & reset) rmod <= mod;

	if(reset) begin
		page_scr_copy <= 0;
		page_reg    <= 0;
		page_reg_plus3 <= 0; 
		page_reg_p1024 <= 0;
		page_128k   <= 0;
		page_reg[4] <= Fn[10];
		page_reg_plus3[2] <= Fn[10];
		shadow_rom <= shdw_reset & ~plusd_en;
		if(Fn[10] && (rmod == 1)) begin
			p1024  <= 0;
			pf1024 <= 0;
			zx48   <= ~plus3;
		end else begin
			p1024 <= (status[12:10] == 1);
			pf1024<= (status[12:10] == 2);
			zx48  <= (status[12:10] == 3);
			plus3 <= (status[12:10] == 4);
		end
	end else begin
		if(m1 && ~old_m1 && addr[15:14]) shadow_rom <= 0;
		if(m1 && ~old_m1 && ~plusd_en && ~mod[0] && (addr == 'h66) && ~plus3) shadow_rom <= 1; 

		if(io_wr & ~old_wr) begin
			if(page_write) begin
				page_reg  <= cpu_dout;
				if(p1024 & ~page_reg_p1024[2])	page_128k[2:0] <= { cpu_dout[5], cpu_dout[7:6] };
				if(~plusd_mem) page_scr_copy <= cpu_dout[3];
			end else if (page_write_plus3) begin
				page_reg_plus3 <= cpu_dout; 
			end
			if(pf1024 & (addr == 'hDFFD)) page_128k <= cpu_dout[2:0];
			if(p1024 & page_p1024) page_reg_p1024 <= cpu_dout;
		end
	end
end


////////////////////  ULA PORT  ///////////////////
reg [2:0] border_color;
reg       ear_out;
reg       mic_out;

wire ula_we = ~addr[0] & ~nIORQ & ~nWR & nM1;
always @(posedge clk_sys) begin
	reg old_we;
	old_we <= ula_we;

	if(reset) {ear_out, mic_out} <= 2'b00;
	else if(ula_we & ~old_we) begin
		border_color <= cpu_dout[2:0];
		ear_out <= cpu_dout[4]; 
		mic_out <= cpu_dout[3];
	end
end


////////////////////   AUDIO   ///////////////////
wire [7:0] sound_data;
wire [7:0] psg_ch_a;
wire [7:0] psg_ch_b;
wire [7:0] psg_ch_c;
wire       psg_enable = addr[0] & addr[15] & ~addr[1];
wire       psg_we     = psg_enable & ~nIORQ & ~nWR & nM1;
reg        psg_reset;


(* direct_enable *) reg  ce_ym;  //3.5MHz
always @(posedge clk_56) begin
	reg [3:0] counter = 0;
	reg p1,p2,p3;
	
	p1 <= pause;
	p2 <= p1;
	p3 <= p2;

	counter <=  counter + 1'd1;
	ce_ym   <= !counter & ~p3;
end

wire [15:0] ts_l, ts_r;

// Turbosound FM: dual YM2203 chips
turbosoundFM turbosoundFM
(
	.RESET(reset | psg_reset),
	.CLK(clk_56),
	.CE(ce_ym),
	.BDIR(psg_we),
	.BC(addr[14]),
	.DI(cpu_dout),
	.DO(sound_data),
	.CHANNEL_L(ts_l),
	.CHANNEL_R(ts_r)
);

//sigma_delta_dac #(11) dac_l
//(
//	.CLK(clk_sys),
//	.RESET(reset),
//	.DACin({ts_l} + {3'b000, ear_out, mic_out, tape_in, 6'b000000}),
//	.DACout(AUDIO_L)
//);
//
//sigma_delta_dac #(11) dac_r
//(
//	.CLK(clk_sys),
//	.RESET(reset),
//	.DACin({ts_r + {3'b000, ear_out, mic_out, tape_in, 6'b000000}}),
//	.DACout(AUDIO_R)
//);


assign MCLK = clock_50_i;
audio_out audio_out
(
        .reset                  (reset),
        .clk                    (clock_50_i),
        .sample_rate    (0),  // 0 is 48 KHz , 1 is 96 Khz
        .left_in                ({ts_l} + {3'b000, ear_out, mic_out, tape_in, 10'b0000000000}),
        .right_in               ({ts_r} + {3'b000, ear_out, mic_out, tape_in, 10'b0000000000}),
        .i2s_bclk               (SCLK),
        .i2s_lrclk              (LRCLK),
        .i2s_data               (SDIN)
); 



////////////////////   VIDEO   ///////////////////
(* maxfan = 10 *) wire        ce_cpu_sn;
(* maxfan = 10 *) wire        ce_cpu_sp;
wire [14:0] vram_addr;
wire  [7:0] vram_dout;
wire  [7:0] port_ff;
wire        ulap_sel;
wire  [7:0] ulap_dout;
wire  [1:0] ulap_tmx_ena = {~status[13], ~status[14]} & {~trdos_en, ~trdos_en};

reg mZX, m128;
always_comb begin
	case(status[9:8])
		      1: {mZX, m128} <= 2'b10;
		      0: {mZX, m128} <= 2'b11;
		default: {mZX, m128} <= 2'b00;
	endcase
end

wire[5:0] vga_r_s;
wire[5:0] vga_g_s;
wire[5:0] vga_b_s;
wire vga_hs_s;
wire vga_vs_s;

video video
(
	.*, 
	
	.SPI_SCK(SPI_SCK),
	.SPI_SS3(SPI_SS2),
	.SPI_DI(SPI_DI),
	
	.din(cpu_dout), 
	.page_ram(page_ram[2:0]), 
	.scale(status[16:15]),
	.VGA_R(vga_r_s),
	.VGA_G(vga_g_s),
	.VGA_B(vga_b_s),
	.VGA_VS(vga_vs_s),
	.VGA_HS(vga_hs_s)
);

assign VGA_R = {vga_r_s[5:4],vga_r_s[5:0]};
assign VGA_G = {vga_g_s[5:4],vga_g_s[5:0]};
assign VGA_B = {vga_b_s[5:4],vga_b_s[5:0]};
assign VGA_HS = vga_hs_s;
assign VGA_VS = vga_vs_s;
assign VGA_CLOCK = clk_sys;
assign VGA_BLANK= 1'b1;



////////////////////   HID   ////////////////////
wire [11:1] Fn;
wire  [2:0] mod;
wire  [4:0] key_data;
wire  [7:0] keys_s;

//keyboard kbd( .* );
keyboard keyboard
(
		.CLK			( clk_sys ),
		.nRESET		( ~reset ),

		.PS2_CLK		( ps2_clk_io ),
		.PS2_DATA	( ps2_data_io ),

		.rows			( addr[15:8] ),

		.cols			( key_data ),
		.teclasF		( Fn ),
		.mod_o		( mod ),
		
		.osd_enable ( osd_enable ),
		.osd_o		( keys_s )
				
	);

reg         mouse_sel;
wire  [7:0] mouse_data;

mouse mouse( .*, .reset(cold_reset), .addr(addr[10:8]), .sel(), .dout(mouse_data));

always @(posedge clk_sys) begin
	reg old_status = 0;
	old_status <= ps2_mouse[24];

	if(joy0[5:0]) mouse_sel <= 0;
	if(old_status != ps2_mouse[24]) mouse_sel <= 1;
end


//////////////////   MF128   ///////////////////
reg         mf128_mem;
reg         mf128_en; // enable MF128 page-in from NMI till reset (or soft off)
wire        mf128_port = ~addr[6] & addr[5] & addr[4] & addr[1];
// read paging registers saved in MF3 (7f3f, 1f3f)
wire        mf3_port = mf128_port & ~addr[7] & (addr[12:8] == 'h1f) & plus3 & mf128_en;


always @(posedge clk_sys) begin
	reg old_m1, old_rd, old_wr;

	old_rd <= io_rd;
	old_wr <= io_wr;
	if(reset) {mf128_mem, mf128_en} <= 0;
	else if(~old_rd & io_rd) begin
		//page in/out for port IN
		if(mf128_port) mf128_mem <= (addr[7] ^ plus3) & mf128_en;
	end else if(~old_wr & io_wr) begin
		//Soft hide
		if(mf128_port) mf128_en <= addr[7] & mf128_en;
	end

	old_m1 <= m1;
	if(~old_m1 & m1 & mod[0] & (addr == 'h66)) {mf128_mem, mf128_en} <= 2'b11;
end

//////////////////   MMC   //////////////////
wire        mmc_sel;
wire  [7:0] mmc_dout;

wire        spi_ss;
wire        spi_clk;
wire        spi_di;
wire        spi_do;

divmmc divmmc
(
    .*,
    .enable(1),
    .mode(status[18:17]), //00-off, 01-divmmc, 10-zxmmc
    .din(cpu_dout),
    .dout(mmc_dout),
    .active_io(mmc_sel)
);

sd_card sd_card
(
    .*,
    .img_mounted(img_mounted[0]), //first slot for SD-card emulation
    .sd_busy(sd_busy_mmc),
    .sd_rd(sd_rd_mmc),
    .sd_wr(sd_wr_mmc),
    .sd_lba(sd_lba_mmc),
    .sd_buff_din(sd_buff_din_mmc),
    .allow_sdhc(1),
    .sd_cs(spi_ss),
    .sd_sck(spi_clk),
    .sd_sdi(spi_do),
    .sd_sdo(spi_di)
);

///////////////////   FDC   ///////////////////
reg         plusd_en;
reg         plusd_mem;
wire        plusd_ena = plusd_stealth ? plusd_mem : plusd_en;
wire        fdd_sel2 = plusd_ena & &addr[7:5] & ~addr[2] & &addr[1:0];

reg         trdos_en;
wire  [7:0] wd_dout;
wire        fdd_rd;
reg         fdd_ready;
reg         fdd_drive1;
reg         fdd_side;
reg         fdd_reset;
wire        fdd_intrq;
wire        fdd_drq;
wire        fdd_sel  = trdos_en & addr[2] & addr[1];
wire  [7:0] wdc_dout = (addr[7] & ~plusd_en) ? {fdd_intrq, fdd_drq, 6'h3F} : wd_dout;

reg         plus3_fdd_ready;
wire        plus3_fdd = ~addr[1] & addr[13] & ~addr[14] & ~addr[15] & plus3 & ~page_disable;
wire [7:0]  u765_dout;

wire  [7:0] fdd_dout = plus3_fdd ? u765_dout : wdc_dout;

//
// current +D implementation notes:
// 1) all +D ports (except page out port) are disabled if +D memory isn't paged in.
// 2) only possible way to page in is through hooks at h08, h3A, h66 addresses.
//
// This may break compatibility with some apps written specifically for +D using 
// direct port access (badly written apps), but won't introduce
// incompatibilities with +D unaware apps.
//
wire        plusd_stealth = 1;

// read video page.
// available for MF128 and PlusD(patched).
wire        portBF = mf128_port & addr[7] & (mf128_mem | plusd_mem);

always @(posedge clk_sys) begin
	reg old_wr, old_rd;
	reg old_mounted;
	reg old_m1;

	if(cold_reset) {plus3_fdd_ready, fdd_ready, plusd_en} <= 0;
	if(reset)      {plusd_mem, trdos_en} <= 0;

	old_mounted <= img_mounted[1];
	if(~old_mounted & img_mounted[1]) begin
	   //Only TRDs on +3
		fdd_ready <= (!ioctl_index[7:6] & plus3) | ~plus3;
		plusd_en  <= |ioctl_index[7:6] & ~plus3;
		//DSK only for +3
		plus3_fdd_ready <= plus3 & (ioctl_index[7:6] == 2);
	end

	old_rd <= io_rd;
	old_wr <= io_wr;
	old_m1 <= m1;
	psg_reset <= 0;

	if(plusd_en) begin
		trdos_en <= 0;
		if(~old_wr & io_wr  & (addr[7:0] == 'hEF) & plusd_ena) {fdd_side, fdd_drive1} <= {cpu_dout[7], cpu_dout[1:0] != 2};
		if(~old_wr & io_wr  & (addr[7:0] == 'hE7)) plusd_mem <= 0;
		if(~old_rd & io_rd  & (addr[7:0] == 'hE7) & ~plusd_stealth) plusd_mem <= 1;
		if(~old_m1 & m1 & ((addr == 'h08) | (addr == 'h3A) | (~mod[0] & (addr == 'h66)))) {psg_reset,plusd_mem} <= {(addr == 'h66), 1'b1};
	end else begin
		plusd_mem <= 0;
		if(~old_wr & io_wr & fdd_sel & addr[7]) {fdd_side, fdd_reset, fdd_drive1} <= {~cpu_dout[4], ~cpu_dout[2], !cpu_dout[1:0]};
		if(m1 && ~old_m1) begin
			if(addr[15:14]) trdos_en <= 0;
				else if((addr[13:8] == 'h3D) & active_48_rom) trdos_en <= 1;
				//else if(~mod[0] & (addr == 'h66)) trdos_en <= 1;
		end
	end
end

wd1793 #(1,0) fdd
(
	.clk_sys(clk_sys),
	.ce(ce_wd1793),
	.reset((fdd_reset & ~plusd_en) | reset),
	.io_en((fdd_sel2 | (fdd_sel & ~addr[7])) & ~nIORQ & nM1),
	.rd(~nRD),
	.wr(~nWR),
	.addr(plusd_en ? addr[4:3] : addr[6:5]),
	.din(cpu_dout),
	.dout(wd_dout),
	.drq(fdd_drq),
	.intrq(fdd_intrq),

	.img_mounted(img_mounted[1]),
	.img_size(img_size),
	.sd_lba(sd_lba_wd),
	.sd_rd(sd_rd_wd),
	.sd_wr(sd_wr_wd),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_wd),
	.sd_buff_wr(sd_buff_wr),

	.wp(0),

	.size_code(plusd_en ? 3'd4 : 3'd1),
	.layout(ioctl_index[7:6] == 1), // 0 = Track-Side-Sector, 1 - Side-Track-Sector
	.side(fdd_side),
	.ready(fdd_drive1 & fdd_ready),

	.input_active(0),
	.input_addr(0),
	.input_data(0),
	.input_wr(0),
	.buff_din(0)
);

u765 #(20'd1800,1) u765
(
	.clk_sys(clk_sys),
	.ce(ce_u765),
	.reset(reset),
	.a0(addr[12]),
	.ready(plus3_fdd_ready),
	.motor(motor_plus3),
	.available(2'b01),
	.fast(1),
	.nRD(~plus3_fdd | nIORQ | ~nM1 | nRD),
	.nWR(~plus3_fdd | nIORQ | ~nM1 | nWR),
	.din(cpu_dout),
	.dout(u765_dout),

	.img_mounted(img_mounted[1]),
	.img_size(img_size),
	.img_wp(0),
	.sd_lba(sd_lba_plus3),
	.sd_rd(sd_rd_plus3),
	.sd_wr(sd_wr_plus3),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_plus3),
	.sd_buff_wr(sd_buff_wr)
);

///////////////////   TAPE   ///////////////////
wire [24:0] tape_addr = 25'h400000 + tape_addr_raw;
wire [24:0] tape_addr_raw;
wire        tape_req;
wire        tape_dout_en;
wire        tape_turbo;
wire  [7:0] tape_dout;
wire        tape_led;
wire        tape_active;
wire        tape_loaded;
wire        tape_in;
wire        tape_vin;


smart_tape tape
(
	.*,
	.reset(reset & ~Fn[10]),
	.ce(ce_tape),

	.turbo(tape_turbo),
	.mode48k(page_disable),
	.pause(Fn[1]),
	.prev(Fn[2]),
	.next(Fn[3]),
	.audio_out(tape_vin),
	.led(tape_led),
	.active(tape_active),
	.available(tape_loaded),
	.req_hdr((reg_DE == 'h11) & !reg_A),

	.buff_rd_en(~nRFSH),
	.buff_rd(tape_req),
	.buff_addr(tape_addr_raw),
	.buff_din(ram_dout),

	.ioctl_download(ioctl_download & (ioctl_index[4:0] == 2)),
	.tape_size(ioctl_addr - 25'h400000 + 1'b1),
	.tape_mode(ioctl_index[7:6]), // 0 - TAP, 1 - CSW, 2 - TZX

	.m1(~nM1 & ~nMREQ),
	.rom_en(active_48_rom),
	.dout_en(tape_dout_en),
	.dout(tape_dout)
);

reg tape_loaded_reg = 0;

always @(posedge clk_sys) begin
	int timeout = 0;
	
	if(tape_loaded) begin
		tape_loaded_reg <= 1;
		timeout <= 100000000;
	end else begin
		if(timeout) begin
			timeout <= timeout - 1;
		end else begin
			tape_loaded_reg <= 0;
		end
	end
end


assign tape_in = tape_loaded_reg ? tape_vin : ~ear_maxduino;



// -- POWER ON RESET
		reg [15:0] power_on_s	= 16'b1111111111111111;
		reg [7:0] osd_s = 8'b11111111;
		wire hard_reset = ~locked;
		
		//--start the microcontroller OSD menu after the power on
		always @(posedge clk_56) 
		begin
		
				if (hard_reset == 1)
					power_on_s = 16'b1111111111111111;
				else if (power_on_s != 0)
				begin
					power_on_s = power_on_s - 1;
					osd_s = 8'b00111111;
				end 

					
				
				if (ioctl_download == 1 && osd_s == 8'b00111111)
					osd_s = 8'b11111111;
			
		end 
		
//--------------------------------------------------------
		
		
wire dsk_wr;
wire [18:0] dsk_addr_s;
wire [7:0] disk_data_s;
wire        dsk_download  = ioctl_download && (ioctl_index[4:0] == 5'b00001);

assign sram_addr_o  = (dsk_download) ? ioctl_addr[18:0]  : dsk_addr_s;
assign sram_data_io = (dsk_download) ? ioctl_dout 	: 8'bzzzzzzzz;
assign disk_data_s  = sram_data_io;
//assign sram_oe_n_o  = 1'b0; 
assign sram_we_n_o  = ~(dsk_download & ioctl_wr);



image_controller image_controller1
(
    
		.clk_i			( clk_sys ),
		.reset_i			( reset ),
 	 
		.sd_lba			( sd_lba ), 
		.sd_rd			( sd_rd ),
		.sd_wr			( sd_wr ),

		.sd_ack			( sd_ack ),
		.sd_buff_addr	( sd_buff_addr ), 
		.sd_buff_dout	( sd_buff_dout ), 
		.sd_buff_din	( sd_buff_din ),
		.sd_buff_wr		( sd_buff_wr ),
		
		.sram_addr_o  	( dsk_addr_s ),
		.sram_data_i   ( disk_data_s )
);
		
//--- Joystick read with sega 6 button support----------------------
	

		//-- joy_s format MXYZ SACB RLDU
	reg [11:0]joy1_s; 	
	reg [11:0]joy2_s; 
	reg joyP7_s;

	reg [7:0]state_v = 8'd0;
	reg j1_sixbutton_v = 1'b0;
	reg j2_sixbutton_v = 1'b0;
	
	always @(negedge vga_hs_s) 
	begin
		

			state_v <= state_v + 1;

			
			case (state_v)			
				8'd0:  
					joyP7_s <=  1'b0;
					
				8'd1:
					joyP7_s <=  1'b1;

				8'd2:
					begin
						joy1_s[3:0] <= {joy1_right_i, joy1_left_i, joy1_down_i, joy1_up_i}; //-- R, L, D, U
						joy2_s[3:0] <= {joy2_right_i, joy2_left_i, joy2_down_i, joy2_up_i}; //-- R, L, D, U
						joy1_s[5:4] <= {joy1_p9_i, joy1_p6_i}; //-- C, B
						joy2_s[5:4] <= {joy2_p9_i, joy2_p6_i}; //-- C, B					
						joyP7_s <= 1'b0;
						j1_sixbutton_v <= 1'b0; //-- Assume it's not a six-button controller
						j2_sixbutton_v <= 1'b0; //-- Assume it's not a six-button controller
					end
					
				8'd3:
					begin
						if (joy1_right_i == 1'b0 && joy1_left_i == 1'b0) // it's a megadrive controller
								joy1_s[7:6] <= { joy1_p9_i , joy1_p6_i }; //-- Start, A
						else
								joy1_s[7:4] <= { 1'b1, 1'b1, joy1_p9_i, joy1_p6_i }; //-- read A/B as master System
							
						if (joy2_right_i == 1'b0 && joy2_left_i == 1'b0) // it's a megadrive controller
								joy2_s[7:6] <= { joy2_p9_i , joy2_p6_i }; //-- Start, A
						else
								joy2_s[7:4] <= { 1'b1, 1'b1, joy2_p9_i, joy2_p6_i }; //-- read A/B as master System

							
						joyP7_s <= 1'b1;
					end
					
				8'd4:  
					joyP7_s <= 1'b0;

				8'd5:
					begin
						if (joy1_right_i == 1'b0 && joy1_left_i == 1'b0 && joy1_down_i == 1'b0 && joy1_up_i == 1'b0 )
							j1_sixbutton_v <= 1'b1; // --it's a six button
						
						
						if (joy2_right_i == 1'b0 && joy2_left_i == 1'b0 && joy2_down_i == 1'b0 && joy2_up_i == 1'b0 )
							j2_sixbutton_v <= 1'b1; // --it's a six button
						
						
						joyP7_s <= 1'b1;
					end
					
				8'd6:
					begin
						if (j1_sixbutton_v == 1'b1)
							joy1_s[11:8] <= { joy1_right_i, joy1_left_i, joy1_down_i, joy1_up_i }; //-- Mode, X, Y e Z
						
						
						if (j2_sixbutton_v == 1'b1)
							joy2_s[11:8] <= { joy2_right_i, joy2_left_i, joy2_down_i, joy2_up_i }; //-- Mode, X, Y e Z
						
						
						joyP7_s <= 1'b0;
					end 
					
				default:
					joyP7_s <= 1'b1;
					
			endcase

	end
	
	assign joyX_p7_o = joyP7_s;		

endmodule
