//
// data_io.v
//
// data_io for the MiST board
// http://code.google.com/p/mist-board/
//
// Copyright (c) 2014 Till Harbaum <till@harbaum.org>
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
///////////////////////////////////////////////////////////////////////

module data_io # (
parameter STRLEN		=	0
)
(
	input             clk_sys,
	
	input             SPI_SCK,
	input             SPI_SS2,
	input             SPI_DI,
	output            SPI_DO,
	
	input   [7:0]           data_in,
	input [(8*STRLEN)-1:0] conf_str,
	output reg [31:0] status,
	
	output      [1:0] img_mounted, // signaling that new image has been mounted
	output reg [31:0] img_size,    // size of image in bytes
		
	// ARM -> FPGA download
	output reg        ioctl_download = 0, // signal indicating an active download
	output reg  [7:0] ioctl_index,        // menu index used to upload the file
	output            ioctl_wr,
	output reg [24:0] ioctl_addr,
	output reg  [7:0] ioctl_dout
);

///////////////////////////////   DOWNLOADING   ///////////////////////////////

reg  [7:0] data_w;
reg [24:0] addr_w;
reg        rclk   = 0;
reg sdo_s;

reg [23:0] ext;

reg [1:0] mount_strobe = 2'b00;
assign img_mounted  = mount_strobe;

assign SPI_DO = sdo_s;

localparam UIO_FILE_TX      = 8'h53;
localparam UIO_FILE_TX_DAT  = 8'h54;
localparam UIO_FILE_INDEX   = 8'h55;

reg [7:0]	ACK = 8'd75; // letter K - 0x4b
reg  [9:0]  byte_cnt;   // counts bytes
reg  [7:0] cmd;
reg  [4:0] cnt;
	
	// SPI MODE 0 : incoming data on Rising, outgoing on Falling
	always@(negedge SPI_SCK, posedge SPI_SS2) 
	begin
	
		
				//each time the SS goes down, we will receive a command from the SPI master
				if (SPI_SS2) // not selected
					begin
						sdo_s <= 1'bZ;
						byte_cnt <= 10'd0;
					end
				else
					begin
							
							if (cmd == 8'h10 ) //command 0x10 - send the data to the microcontroller
								sdo_s <= data_in[~cnt[2:0]];
								
							else if (cmd == 8'h00 ) //command 0x00 - ACK
								sdo_s <= ACK[~cnt[2:0]];
							
						//	else if (cmd == 8'h61 ) //command 0x61 - echo the pumped data
						//		sdo_s <= sram_data_s[~cnt[2:0]];			
					
					
							else if(cmd == 8'h14) //command 0x14 - reading config string
								begin
								
									if(byte_cnt < STRLEN + 1 ) // returning a byte from string
										sdo_s <= conf_str[{STRLEN - byte_cnt,~cnt[2:0]}];
									else
										sdo_s <= 1'b0;
										
								end	
						
				
							if((cnt[2:0] == 7)) 
								byte_cnt <= byte_cnt + 10'd1;
							
					end
	end
	

// data_io has its own SPI interface to the io controller
always@(posedge SPI_SCK, posedge SPI_SS2) begin
	reg  [6:0] sbuf;
	reg [24:0] addr;
	reg  [4:0] cnf_byte;

	if(SPI_SS2) 
	begin
		cnt <= 0;
		cnf_byte <= 4'd15;
		mount_strobe = 2'b00;
	end
	else begin
		rclk <= 0;

		// don't shift in last bit. It is evaluated directly
		// when writing to ram
		if(cnt != 15) sbuf <= { sbuf[5:0], SPI_DI};

		// increase target address after write
		if(rclk) addr <= addr + 1'd1;

		// count 0-7 8-15 8-15 ... 
		if(cnt < 15) cnt <= cnt + 1'd1;
			else cnt <= 8;

		// finished command byte
		if(cnt == 7) 
		begin 
			cmd <= {sbuf, SPI_DI};
		
		
				// command 0x61: start the data streaming
				if(sbuf[6:0] == 7'b0110000 && SPI_DI == 1'b1)
				begin
					//addr <= 0;
					ioctl_download <= 1;
				end
				
				// command 0x62: end the data streaming
				if(sbuf[6:0] == 7'b0110001 && SPI_DI == 1'b0)
				begin
					//addr_w <= addr;
					ioctl_download <= 0;
					
					//a disk image was mounted
					if(ioctl_index[4:0]==5'b00001) 
					begin
								mount_strobe = 2'b10;
								img_size = 32'd194816;
					end
					else //tape
					begin
						img_size = 32'd0;
					end 
								
								
				end
		end
		
		if(cnt == 15) 
		begin 
		
				// command 0x15: stores the status word (menu selections)
						if (cmd == 8'h15)
						begin
						
							case (cnf_byte)			
								4'd15: status[31:24] <={sbuf, SPI_DI};
								4'd14: status[23:16] <={sbuf, SPI_DI};
								4'd13: status[15:8]  <={sbuf, SPI_DI};
								4'd12: status[7:0]   <={sbuf, SPI_DI};
							endcase
							
							cnf_byte <= cnf_byte - 1'd1;

						end
		
			// command 0x60: stores a configuration byte
				if (cmd == 8'h60)
				begin
				
							case (cnf_byte)	
								4'd11: ext[23:16] <= { sbuf, SPI_DI };
								4'd10: ext[15:8]  <= { sbuf, SPI_DI };
								4'd9 : ext[7:0]	<= { sbuf, SPI_DI };
							endcase
							
						//config_buffer_o[cnf_byte] <= {sbuf[6:0], sdi};
						cnf_byte <= cnf_byte - 1'd1;
						
						
							//ioctl_index[4:0]
							//1: addr <= 25'h200000; // TRD buffer  at 2MB
							//2: addr <= 25'h400000; // tape buffer at 4MB 
							//default: addr <= 25'h150000; // boot rom
							
							//for disks
							//ioctl_index[7:6] == 1), // 0 = Track-Side-Sector, 1 - Side-Track-Sector
							//Only TRDs on +3
							//fdd_ready <= (!ioctl_index[7:6] & plus3) | ~plus3;
							//plusd_en  <= |ioctl_index[7:6] & ~plus3;
							//DSK only for +3
							//plus3_fdd_ready <= plus3 & (ioctl_index[7:6] == 2);
		
						
							//for tapes
						   //ioctl_index[7:6] // 0 - TAP, 1 - CSW, 2 - TZX
							//ioctl_index[4:0] == 2
						
						if(ext[23:16] == "t" && ext[15:8] == "r" && ext[7:0] == "d") 
							begin
									ioctl_index <= 8'b00000001; 
									addr <= 25'h200000; // buffer  at 2MB
							end	
						else if(ext[23:16] == "d" && ext[15:8] == "s" && ext[7:0] == "k") 
							begin
									ioctl_index <= 8'b10000001; 
									addr <= 25'h200000; // buffer  at 2MB
							end	
						else if(ext[23:16] == "t" && ext[15:8] == "a" && ext[7:0] == "p") 
							begin
									ioctl_index <= 8'b00000010; // TAP tape image
									addr <= 25'h400000; // tape buffer at 4MB 
							end
						else if(ext[23:16] == "c" && ext[15:8] == "s" && ext[7:0] == "w") 
							begin
									ioctl_index <= 8'b01000010; // CSW tape image
									addr <= 25'h400000; // tape buffer at 4MB 
							end
						else if(ext[23:16] == "t" && ext[15:8] == "z" && ext[7:0] == "x") 
							begin
									ioctl_index <= 8'b10000010; // TZX tape image
									addr <= 25'h400000; // tape buffer at 4MB 
							end
						else if(ext[23:16] == "d" && ext[15:8] == "a" && ext[7:0] == "t") 
							begin
									ioctl_index <= 8'd0; // default
									addr <= 25'h150000; // boot rom; 
							end
						else 
							begin
									ioctl_index <= 8'b00000010; // TAP tape image
									addr <= 25'h400000; // tape buffer at 4MB 
							end
									
				end
						
				// command 0x61: Data Pump 8 bits
				if (cmd == 8'h61) 
				begin
						addr_w <= addr;
						data_w <= {sbuf, SPI_DI};
						rclk <= 1;
				end
		end
/*		
		// prepare/end transmission
		if((cmd == UIO_FILE_TX) && (cnt == 15)) begin
			// prepare 
			if(SPI_DI) begin
				addr <= 0;
				ioctl_download <= 1; 
			end else begin
				addr_w <= addr;
				ioctl_download <= 0;
			end
		end

		// command 0x54: UIO_FILE_TX
		if((cmd == UIO_FILE_TX_DAT) && (cnt == 15)) begin
			addr_w <= addr;
			data_w <= {sbuf, SPI_DI};
			rclk <= 1;
		end
		*/

		// expose file (menu) index
		if((cmd == UIO_FILE_INDEX) && (cnt == 15)) ioctl_index <= {sbuf, SPI_DI};
	end
end

assign ioctl_wr = |ioctl_wrd;
reg [1:0] ioctl_wrd;

always@(negedge clk_sys) begin
	reg        rclkD, rclkD2;

	rclkD    <= rclk;
	rclkD2   <= rclkD;
	ioctl_wrd<= {ioctl_wrd[0],1'b0};

	if(rclkD & ~rclkD2) begin
		ioctl_dout <= data_w;
		ioctl_addr <= addr_w;
		ioctl_wrd  <= 2'b11;
	end
end

endmodule