
/******************************************************************************/
// RISC-V playground for curious minds, using FemtoRV32-Gracilis (RV32IMC)
/******************************************************************************/

`default_nettype none // Makes it easier to detect typos !

`include "femtorv32_gracilis.v"
`include "uart-fifo.v"
`include "ice40up5k_spram.v"

module riscv_playground(

           input clk_in, // 12 MHz

           output uart_tx,
           input  uart_rx,

           inout [7:0] pmod,

           // SPI
           input  spi_mosi,
           output spi_miso,
           input  spi_clk,
           input  spi_cs_n,

           output irq_n,

           // LCD
           output reg  [7:0] lcd_d,
           output reg        lcd_rs,
           output            lcd_wr_n,
           output reg        lcd_cs_n,
           output reg        lcd_rst_n,
           input             lcd_fmark,
           input             lcd_mode,

           inout [2:0] rgb // LED outputs. [0]: Blue, [1]: Red, [2]: Green.
);

   /***************************************************************************/
   // Clock.
   /***************************************************************************/

   wire clk, pll_locked;

   SB_PLL40_PAD #(.FEEDBACK_PATH("SIMPLE"),
                  .PLLOUT_SELECT("GENCLK_HALF"),
                  .DIVR(4'b0000),         // DIVR =  0
                  .DIVF(7'b1001111),      // DIVF = 79
                  .DIVQ(3'b101),          // DIVQ =  5
                  .FILTER_RANGE(3'b001)   // FILTER_RANGE = 1
          ) uut (
                  .RESETB(1'b1),
                  .BYPASS(1'b0),
                  .LOCK(pll_locked),
                  .PACKAGEPIN(clk_in),  // 12 MHz
                  .PLLOUTGLOBAL(clk)    // 15 MHz (minimum for the SPI interface on the badge)
                );

   /***************************************************************************/
   // Reset logic.
   /***************************************************************************/

   wire reset_button = pll_locked; // No reset button on this board

   reg [15:0] reset_cnt = 0;
   wire resetbit = &reset_cnt;
   reg resetq = 0;

   always @(posedge clk) begin
     if (reset_button) reset_cnt <= reset_cnt + !resetbit;
     else        reset_cnt <= 0;

     resetq <= resetbit;
   end

   /***************************************************************************/
   // LEDs.
   /***************************************************************************/

   reg [3:0] LEDs; // [6:4]: IN [2:0] Constant Current Drivers

   reg [15:0] sdm_red,   phase_red;   reg sdm_red_out;   always @(posedge clk) {sdm_red_out,   phase_red}   <= phase_red   + sdm_red;
   reg [15:0] sdm_green, phase_green; reg sdm_green_out; always @(posedge clk) {sdm_green_out, phase_green} <= phase_green + sdm_green;
   reg [15:0] sdm_blue,  phase_blue;  reg sdm_blue_out;  always @(posedge clk) {sdm_blue_out,  phase_blue}  <= phase_blue  + sdm_blue;

   wire red   = LEDs[0] | sdm_red_out;
   wire green = LEDs[1] | sdm_green_out;
   wire blue  = LEDs[2] | sdm_blue_out;

   wire red_in, green_in, blue_in;

   SB_IO #(.PIN_TYPE(6'b1010_01)) rgb1 (.PACKAGE_PIN(rgb[1]),  .D_OUT_0(1'b0),  .D_IN_0(red_in),   .OUTPUT_ENABLE(1'b0) );
   SB_IO #(.PIN_TYPE(6'b1010_01)) rgb2 (.PACKAGE_PIN(rgb[2]),  .D_OUT_0(1'b0),  .D_IN_0(green_in), .OUTPUT_ENABLE(1'b0) );
   SB_IO #(.PIN_TYPE(6'b1010_01)) rgb0 (.PACKAGE_PIN(rgb[0]),  .D_OUT_0(1'b0),  .D_IN_0(blue_in),  .OUTPUT_ENABLE(1'b0) );

   // Instantiate iCE40 LED driver hard logic.
   //
   // Note that it's possible to drive the LEDs directly,
   // however that is not current-limited and results in
   // overvolting the red LED.
   //
   // See also:
   // https://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/IK/ICE40LEDDriverUsageGuide.ashx?document_id=50668

   SB_RGBA_DRV #(
       .CURRENT_MODE("0b1"),       // half current
       .RGB0_CURRENT("0b000011"),  // 4 mA
       .RGB1_CURRENT("0b000011"),  // 4 mA
       .RGB2_CURRENT("0b000011")   // 4 mA
   ) RGBA_DRIVER (
       .CURREN(1'b1),
       .RGBLEDEN(1'b1),
       .RGB1PWM(red),
       .RGB2PWM(green),
       .RGB0PWM(blue),
       .RGB1(rgb[1]),
       .RGB2(rgb[2]),
       .RGB0(rgb[0])
   );

   /***************************************************************************/
   // Ring oscillator for random numbers.
   /***************************************************************************/

   wire [1:0] buffers_in, buffers_out;
   assign buffers_in = {buffers_out[0:0], ~buffers_out[1]};
   SB_LUT4 #(
           .LUT_INIT(16'd2)
   ) buffers [1:0] (
           .O(buffers_out),
           .I0(buffers_in),
           .I1(1'b0),
           .I2(1'b0),
           .I3(1'b0)
   );

   wire random = ~buffers_out[1];

   /***************************************************************************/
   // Timer with interrupt.
   /***************************************************************************/

   reg  interrupt = 0;
   reg  [31:0] ticks;
   wire [32:0] ticks_plus_1 = ticks + 1;
   reg  [31:0] reload = 0;
   wire [31:0] next_ticks = ticks_plus_1[32] ? reload[31:0] : ticks_plus_1[31:0];

   always @(posedge clk)
   begin
     if (io_wstrb & mem_address[18]) ticks  <= mem_wdata; else ticks <= next_ticks;
     if (io_wstrb & mem_address[19]) reload <= mem_wdata;

     interrupt <= ticks_plus_1[32]; // Generate interrupt on ticks overflow
   end

   /***************************************************************************/
   // Example register. You can hook your logic here!
   /***************************************************************************/

   reg  [31:0] example = 0;
   wire [31:0] example_feedback = example ^ example[31:1];

   /***************************************************************************/
   // GPIO.
   /***************************************************************************/

   wire [7:0] port_in;
   reg  [7:0] port_out;
   reg  [7:0] port_dir;

   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa0  (.PACKAGE_PIN(pmod[0]),  .D_OUT_0(port_out[0]),  .D_IN_0(port_in[0]),  .OUTPUT_ENABLE(port_dir[0]),  .INPUT_CLK(clk) );
   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa1  (.PACKAGE_PIN(pmod[1]),  .D_OUT_0(port_out[1]),  .D_IN_0(port_in[1]),  .OUTPUT_ENABLE(port_dir[1]),  .INPUT_CLK(clk) );
   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa2  (.PACKAGE_PIN(pmod[2]),  .D_OUT_0(port_out[2]),  .D_IN_0(port_in[2]),  .OUTPUT_ENABLE(port_dir[2]),  .INPUT_CLK(clk) );
   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa3  (.PACKAGE_PIN(pmod[3]),  .D_OUT_0(port_out[3]),  .D_IN_0(port_in[3]),  .OUTPUT_ENABLE(port_dir[3]),  .INPUT_CLK(clk) );
   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa4  (.PACKAGE_PIN(pmod[4]),  .D_OUT_0(port_out[4]),  .D_IN_0(port_in[4]),  .OUTPUT_ENABLE(port_dir[4]),  .INPUT_CLK(clk) );
   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa5  (.PACKAGE_PIN(pmod[5]),  .D_OUT_0(port_out[5]),  .D_IN_0(port_in[5]),  .OUTPUT_ENABLE(port_dir[5]),  .INPUT_CLK(clk) );
   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa6  (.PACKAGE_PIN(pmod[6]),  .D_OUT_0(port_out[6]),  .D_IN_0(port_in[6]),  .OUTPUT_ENABLE(port_dir[6]),  .INPUT_CLK(clk) );
   SB_IO #(.PIN_TYPE(6'b1010_00)) ioa7  (.PACKAGE_PIN(pmod[7]),  .D_OUT_0(port_out[7]),  .D_IN_0(port_in[7]),  .OUTPUT_ENABLE(port_dir[7]),  .INPUT_CLK(clk) );

   /***************************************************************************/
   // UART.
   /***************************************************************************/

   wire serial_valid       /*verilator public_flat*/ ;
   wire serial_busy        /*verilator public_flat*/ ;
   wire [7:0] serial_data  /*verilator public_flat*/ ;
   wire serial_wr          /*verilator public_flat*/ = io_wstrb & mem_address[16];
   wire serial_rd          /*verilator public_flat*/ = io_rstrb & mem_address[16];

   buart #(
     .FREQ_MHZ(15),
     .BAUDS(115200)
   ) the_buart (
      .clk(clk),
      .resetq(resetq),
      .rx(uart_rx),
      .tx(uart_tx),
      .rd(serial_rd),
      .wr(serial_wr),
      .valid(serial_valid),
      .busy(serial_busy),
      .tx_data(mem_wdata[7:0]),
      .rx_data(serial_data)
   );

   /***************************************************************************/
   // SPI interface.
   /***************************************************************************/

   wire [7:0] usr_miso_data, usr_mosi_data;
   wire usr_mosi_stb, usr_miso_ack;
   wire csn_state, csn_rise, csn_fall;

   spi_dev_core _communication (

     .clk (clk),
     .rst (~resetq),

     .usr_mosi_data (usr_mosi_data),
     .usr_mosi_stb  (usr_mosi_stb),
     .usr_miso_data (usr_miso_data),
     .usr_miso_ack  (usr_miso_ack),

     .csn_state (csn_state),
     .csn_rise  (csn_rise),
     .csn_fall  (csn_fall),

     // Interface to SPI wires

     .spi_miso (spi_miso),
     .spi_mosi (spi_mosi),
     .spi_clk  (spi_clk),
     .spi_cs_n (spi_cs_n)
   );

   wire [7:0] pw_wdata;
   wire pw_wcmd, pw_wstb, pw_end;

   wire [7:0] pw_rdata;
   wire pw_req, pw_rstb, pw_gnt;

   wire [3:0] pw_irq;
   wire irq;

   spi_dev_proto _protocol (
     .clk (clk),
     .rst (~resetq),

     // Connection to the actual SPI module:

     .usr_mosi_data (usr_mosi_data),
     .usr_mosi_stb  (usr_mosi_stb),
     .usr_miso_data (usr_miso_data),
     .usr_miso_ack  (usr_miso_ack),

     .csn_state (csn_state),
     .csn_rise  (csn_rise),
     .csn_fall  (csn_fall),

     // These wires deliver received data:

     .pw_wdata (pw_wdata),
     .pw_wcmd  (pw_wcmd),
     .pw_wstb  (pw_wstb),
     .pw_end   (pw_end),

     // Replies and requests

     .pw_req   (pw_req),
     .pw_gnt   (pw_gnt),
     .pw_rdata (pw_rdata),
     .pw_rstb  (pw_rstb),

     .pw_irq   (pw_irq),
     .irq      (irq)
   );

   assign pw_irq[3:1] = 3'b000;
   assign irq_n = irq ? 1'b0 : 1'bz;

   /***************************************************************************/
   // File request interface over SPI.
   /***************************************************************************/

   reg [31:0] buffercontent = 32'hFFFFFFFF; // Start with an invalid address
   reg [31:0] file_id = 32'hDABBAD00;
   reg request = 0;
   wire file_request_ready;

   spi_dev_fread #(
      .INTERFACE("STREAM")
   ) _fread (
      .clk (clk),
      .rst (~resetq),

      // SPI interface
      .pw_wdata     (pw_wdata),
      .pw_wcmd      (pw_wcmd),
      .pw_wstb      (pw_wstb),
      .pw_end       (pw_end),
      .pw_req       (pw_req),
      .pw_gnt       (pw_gnt),
      .pw_rdata     (pw_rdata),
      .pw_rstb      (pw_rstb),
      .pw_irq       (pw_irq[0]),

      // Read request interface
      .req_file_id  (file_id),
      .req_offset   (buffercontent),
      .req_len      (10'd1023), // One less than the actual requested length!

      .req_valid    (request),
      .req_ready    (file_request_ready),

      // Stream reply interface
      .resp_data    (file_data),
      .resp_valid   (file_data_wstrb)
   );

   /***************************************************************************/
   // Receive file data over SPI.
   /***************************************************************************/

   reg file_rbusy = 0;

   reg [31:0] FILE[1024/4-1:0];
   reg [31:0] file_rdata;
   reg [10:0] file_recv_addr;

   wire [7:0] file_data;
   wire       file_data_wstrb;

   always @(posedge clk)
   begin
     if (request) request <= request & ~file_request_ready;
     else
     if ((mem_address_is_file & (buffercontent != {4'b0, mem_address[27:10], 10'b0}) & mem_rstrb) | (io_wstrb & mem_address[20]))
     begin
       buffercontent <= {4'b0, mem_address[27:10], 10'b0};
       request    <= 1;
       file_rbusy <= 1;
       file_recv_addr <= 0;
     end
     else
     begin
       if (file_data_wstrb)
       begin
         if (file_recv_addr[1:0] == 0) FILE[file_recv_addr[9:2]][ 7:0 ] <= file_data;
         if (file_recv_addr[1:0] == 1) FILE[file_recv_addr[9:2]][15:8 ] <= file_data;
         if (file_recv_addr[1:0] == 2) FILE[file_recv_addr[9:2]][23:16] <= file_data;
         if (file_recv_addr[1:0] == 3) FILE[file_recv_addr[9:2]][31:24] <= file_data;
         file_recv_addr <= file_recv_addr + 1;
       end
       if (pw_end & (file_recv_addr != 0)) file_rbusy <= 0;
     end
   end

   always @(posedge clk) file_rdata <= FILE[mem_address[9:2]];

   /***************************************************************************/
   // Receive button state over SPI.
   /***************************************************************************/

   reg  [7:0] command;
   reg [31:0] incoming_data;
   reg [31:0] buttonstate;

   always @(posedge clk)
   begin
     if (pw_wstb & pw_wcmd)           command       <= pw_wdata;
     if (pw_wstb)                     incoming_data <= incoming_data << 8 | pw_wdata;
     if (pw_end & (command == 8'hF4)) buttonstate   <= incoming_data;
   end

   // wire joystick_down  = buttonstate[16];
   // wire joystick_up    = buttonstate[17];
   // wire joystick_left  = buttonstate[18];
   // wire joystick_right = buttonstate[19];
   // wire joystick_press = buttonstate[20];
   // wire home           = buttonstate[21];
   // wire menu           = buttonstate[22];
   // wire select         = buttonstate[23];
   //
   // wire start          = buttonstate[24];
   // wire accept         = buttonstate[25];
   // wire back           = buttonstate[26];

     /*
   Bits are mapped to the following keys:
    0 - joystick down
    1 - joystick up
    2 - joystick left
    3 - joystick right
    4 - joystick press
    5 - home
    6 - menu
    7 - select
    8 - start
    9 - accept
   10 - back
     */

   /***************************************************************************/
   // LCD
   /***************************************************************************/
   wire mem_address_is_lcd;
   wire mem_address_is_pal;
   wire [15:0] lcd_rdata0;
   wire [15:0] lcd_rdata1;
   wire [15:0] lcd_rdata = lcdsel ? lcd_rdata0 : lcd_rdata1;
   wire [3:0] lcd_read;
   wire lcd_rbusy = 0;

   always @(pixelpos, lcd_rdata) begin
      case(pixelpos[1:0])
	     2'b00: lcd_read <= lcd_rdata[ 3: 0];
	     2'b01: lcd_read <= lcd_rdata[ 7: 4];
	     2'b10: lcd_read <= lcd_rdata[11: 8];
	     2'b11: lcd_read <= lcd_rdata[15:12];
		 default: lcd_read <= 0;
	  endcase
   end

   reg lcdsel = 0;

   /*
   always @(posedge clk) begin
      if(ypos == 1 & xpos == 0) lcdsel <= ~lcdsel;
   end
   */

   wire [15:0] mem_nibdata = {mem_wdata[27:24],mem_wdata[19:16],mem_wdata[11:8],mem_wdata[3:0]};

   SB_SPRAM256KA lcdram0 (
      .ADDRESS(lcdsel ? pixelpos[15:2] : mem_address[15:2]),
      .DATAIN(mem_nibdata),
      .MASKWREN({4{~lcdsel}} & mem_wmask & {4{mem_address_is_lcd}}),
      .WREN(~lcdsel & |mem_wmask & mem_address_is_lcd),
      .CHIPSELECT(1'b1),
      .CLOCK(clk),
      .STANDBY(1'b0),
      .SLEEP(1'b0),
      .POWEROFF(1'b1),
      .DATAOUT(lcd_rdata0)
   );

   SB_SPRAM256KA lcdram1 (
      .ADDRESS(~lcdsel ? pixelpos[15:2] : mem_address[15:2]),
      .DATAIN(mem_nibdata),
      .MASKWREN({4{lcdsel}} & mem_wmask & {4{mem_address_is_lcd}}),
      .WREN(lcdsel & |mem_wmask & mem_address_is_lcd),
      .CHIPSELECT(1'b1),
      .CLOCK(clk),
      .STANDBY(1'b0),
      .SLEEP(1'b0),
      .POWEROFF(1'b1),
      .DATAOUT(lcd_rdata1)
   );

   reg [15:0] palette [15:0];

   // Software control of special wires

   reg [1:0] lcd_ctrl = 2'b01;
   assign {lcd_rst_n, lcd_cs_n} = lcd_ctrl;

   // Set WR in the second half of the clock cycle using DDR pin mode to allow the data lines to settle

   SB_IO #(.PIN_TYPE(6'b0100_01)) lcdwrn (.OUTPUT_CLK(clk), .PACKAGE_PIN(lcd_wr_n), .D_OUT_0(1'b0), .D_OUT_1(lcd_write), .OUTPUT_ENABLE(1'b1));
   reg lcd_write = 0;
   // Internal signals for textmode generation

  reg fmark_sync1 = 0;
  reg fmark_sync2 = 0;
  reg updating = 0;
  reg toggle = 0;
  wire [15:0] pixelpos = (ypos*256)|xpos[7:0];

   reg [8:0] xpos; // 0 to 320-1
   reg [7:0] ypos; // 0 to 240-1

   reg [8:0] data0, data1;

   always @(posedge clk) begin
      if(mem_wmask[0] & mem_address_is_pal) palette[mem_address[3:1]][ 7:0] <= mem_wdata[ 7:0 ];
      if(mem_wmask[1] & mem_address_is_pal) palette[mem_address[3:1]][15:8] <= mem_wdata[15:8 ];
      if(mem_wmask[2] & mem_address_is_pal) palette[mem_address[3:1]][ 7:0] <= mem_wdata[23:16];
      if(mem_wmask[3] & mem_address_is_pal) palette[mem_address[3:1]][15:8] <= mem_wdata[31:24];
   end

   always @(posedge clk) begin

     // Reads from font data set & character buffer

     toggle <= ~toggle; // Toggle between high and low part of data to LCD and between logic and software read access.

     // Synchronise incoming asynchronous VSYNC signal to clk

     fmark_sync1 <= lcd_fmark;
     fmark_sync2 <= fmark_sync1;

     // Logic to push data to LCD

     if (fmark_sync2 & ~updating) // VSYNC active and not yet updating?
     begin
       xpos <= 0;
      ypos <= 1;

       data0 <= {1'b0, 8'h00}; //   NOP command
       data1 <= {1'b0, 8'h2C}; // RAMWR command

       lcd_write <= 0;       // Nothing to write
       updating <= toggle; // Start when toggle is high, updating starts with toggle low in next cycle.
     end
     else
     begin
       if (updating) // Currently updating? Push data. One more pair of data is pushed for RAMWR command.
       begin
         lcd_write <= 1;

         case (toggle)
           0: begin
                {lcd_rs, lcd_d} <= data0;
              end

           1: begin
                {lcd_rs, lcd_d} <= data1;

				if(xpos > 256 | ypos > 200) {data1, data0} <= {1'b1, 8'h00, 1'b1, 8'h00};
				else {data1, data0} <= {1'b1, palette[lcd_read][7:0], 1'b1, palette[lcd_read][15:8]};


                if (ypos == 239) begin xpos <= xpos + 1; ypos <= 0; end else ypos <= ypos + 1;
               updating <= ~((xpos == 320) & (ypos == 1));
              end
         endcase

       end
       else // Software control of the LCD wires for initialisation toggle or if software wants to slowly draw graphics
       begin
         if (io_wstrb & mem_address[13])  begin
           {lcd_rs, lcd_d}  <= mem_wdata ^ 9'h100; // Data written with 9th bit set is written in command mode.
           lcd_write        <= 1;
         end
         else
           lcd_write <= 0;
       end
     end
   end


   // This is a little trick to coax a word-addressed CPU into byte aligned reads and writes!

   // Reading char&font data is possible three cycles after the address is set.
   // Generate a busy signal accordingly.

   /***************************************************************************/
   // IO Ports.
   /***************************************************************************/

   // Using 1-hot adressing of IO registers saves LUTs.

   // With byte selection and clear/set/toggle bit masks,
   // we can use mem_address[27:4] for IO, 24 bits in total.

   // Bits mem_address[1:0] : Byte select
   // Bits mem_address[3:2] : Write +0, Clear +4, Set +8, Toggle +12

   wire [31:0] io_rdata =

      (mem_address[ 4] ?  {port_dir, port_out, port_in}                    : 32'd0) |  // RW: GPIO
      (mem_address[ 5] ?  example                                          : 32'd0) |  // RW: Example register
      (mem_address[ 6] ?  example_feedback                                 : 32'd0) |  // R:  Example feedback
      (mem_address[ 7] ?  buttonstate[26:16]                               : 32'd0) |  // R:  Buttons

      (mem_address[ 8] ?  {blue_in, green_in, red_in, LEDs}                : 32'd0) |  // RW: [6:4] LED inputs [2:0] LEDs outputs
      (mem_address[ 9] ?  sdm_red                                          : 32'd0) |  // RW: Sigma-delta modulator brightness for red   channel
      (mem_address[10] ?  sdm_green                                        : 32'd0) |  // RW: Sigma-delta modulator brightness for green channel
      (mem_address[11] ?  sdm_blue                                         : 32'd0) |  // RW: Sigma-delta modulator brightness for blue  channel

      (mem_address[12] ?  {updating,fmark_sync2,lcd_mode,lcd_ctrl}         : 32'd0) |
      //           13      lcd_data write-only                                         // WO: Handled in LCD code
      (mem_address[16] |                                                               // RW: Write: Data to send (8 bits) Read: Received data (8 bits) and flags
       mem_address[17] ? {random, serial_busy, serial_valid, serial_data}  : 32'd0) |  // RO: Status. [10]: Random [9]: Busy sending [8]: Valid read data [7]: Read data without dropping from receive FIFO
      (mem_address[18] ?  ticks                                            : 32'd0) |  // RW: Timer count register
      (mem_address[19] ?  reload                                           : 32'd0) |  // RW: Timer reload value
      (mem_address[20] ?  file_id                                          : 32'd0) |  // RW: File identifier
      (mem_address[21] ?  lcdsel                                           : 32'd0) ;  // RW: Framebuffer switch

      //        27-22     Unused


   // This is for preparing the value to allow atomic clear, set, toggle capabilities on writes to IO registers!
   wire [31:0] io_modifier = (mem_address[3:2] == 2'b01)    ? ~mem_wdata & io_rdata :  // Clear
                             (mem_address[3:2] == 2'b10)    ?  mem_wdata | io_rdata :  // Set
                             (mem_address[3:2] == 2'b11)    ?  mem_wdata ^ io_rdata :  // Toggle
                          /* (mem_address[3:2] == 2'b00) */    mem_wdata            ;

   always @(posedge clk)
   begin

     // Word-only access

     if (io_wstrb & mem_address[ 8]) LEDs      <= io_modifier;
     if (io_wstrb & mem_address[ 9]) sdm_red   <= io_modifier;
     if (io_wstrb & mem_address[10]) sdm_green <= io_modifier;
     if (io_wstrb & mem_address[11]) sdm_blue  <= io_modifier;

     if (io_wstrb & mem_address[12]) lcd_ctrl <= io_modifier;
     if (io_wstrb & mem_address[20]) file_id  <= io_modifier;
     if (io_wstrb & mem_address[21]) lcdsel  <= io_modifier;
     //                         13   lcd_data write-only, side-effects in LCD code

     //                         16   uart_data, side-effects in UART code
     //                         18   ticks,  side-effects in timer code
     //                         19   reload, side-effects in timer code

     // Variable width access, allows to control the individual bytes

     if (mem_address_is_io & mem_address[ 4] & mem_wmask[1]) port_out        <= io_modifier[15:8 ];
     if (mem_address_is_io & mem_address[ 4] & mem_wmask[2]) port_dir        <= io_modifier[23:16];

     if (mem_address_is_io & mem_address[ 5] & mem_wmask[0]) example[ 7:0 ]  <= io_modifier[ 7:0 ];
     if (mem_address_is_io & mem_address[ 5] & mem_wmask[1]) example[15:8 ]  <= io_modifier[15:8 ];
     if (mem_address_is_io & mem_address[ 5] & mem_wmask[2]) example[23:16]  <= io_modifier[23:16];
     if (mem_address_is_io & mem_address[ 5] & mem_wmask[3]) example[31:24]  <= io_modifier[31:24];

   end

   // The processor reads the contents one clock cycle after the read strobe has been active.
   // Buffering is necessary for getting IO register contents of the read strobe cycle
   // that causes side-effects such as dropping a char from the UART receive FIFO.

   reg  [31:0] io_rdata_buffered /*verilator public_flat*/ ;

   always @(posedge clk)
      if (mem_address_is_io & io_rstrb) io_rdata_buffered <= io_rdata;

   /***************************************************************************/
   // The memory bus.
   /***************************************************************************/

   wire [31:0] mem_address; // Word-aligned, but with a trick byte-adressed areas are possible
   wire  [3:0] mem_wmask;   // Mem write mask and strobe /write. Possible values are 0000,0001,0010,0100,1000,0011,1100,1111
   wire [31:0] mem_rdata;   // Processor <- (mem and peripherals)
   wire [31:0] mem_wdata;   // Processor -> (mem and peripherals)
   wire        mem_rstrb;   // Mem read strobe. Goes high to initiate memory read.
   wire        mem_rbusy;   // Processor <- (mem and peripherals). Stays high until a read transfer is finished.
   wire        mem_wbusy;   // Processor <- (mem and peripherals). Stays high until a write transfer is finished.

   /***************************************************************************/
   // The processor.
   /***************************************************************************/

   FemtoRV32 #(
     .RESET_ADDR(32'h80000000),
     .ADDR_WIDTH(32)
   ) processor (
     .clk(clk),
     .mem_addr(mem_address),
     .mem_wdata(mem_wdata),
     .mem_wmask(mem_wmask),
     .mem_rdata(mem_rdata),
     .mem_rstrb(mem_rstrb),
     .mem_rbusy(mem_rbusy),
     .mem_wbusy(mem_wbusy),
     .interrupt_request(interrupt),
     .reset(resetq)
   );

   /***************************************************************************/
   // Memory, memory map and IO access control wires.
   /***************************************************************************/

   // Memory map:

   wire mem_address_is_ram  = (mem_address[31:28] == 4'h0); // 0x00000000
   wire mem_address_is_lcd  = (mem_address[31:28] == 4'h1); // 0x10000000
   wire mem_address_is_pal  = (mem_address[31:28] == 4'h2); // 0x20000000
   wire mem_address_is_io   = (mem_address[31:28] == 4'h4); // 0x40000000
   wire mem_address_is_boot = (mem_address[31:28] == 4'h8); // 0x80000000
   wire mem_address_is_file = (mem_address[31:28] == 4'h9); // 0x90000000

   // Connect the read registers of memories and IO to the memory bus.

   assign mem_rdata =

      (mem_address_is_ram  ? ram_rdata              : 32'd0) |
      (mem_address_is_io   ? io_rdata_buffered      : 32'd0) |
      (mem_address_is_boot ? boot_rdata             : 32'd0) |
      (mem_address_is_file ? file_rdata             : 32'd0) ;

   // Conveniently decoded read and write wires for IO

   wire mem_wstrb = |mem_wmask;

   wire io_rstrb = mem_rstrb & mem_address_is_io;
   wire io_wstrb = mem_wstrb & mem_address_is_io;

   // If you have peripherals or memories that might be busy, wire them here.

   wire mem_rbusy = lcd_rbusy | file_rbusy;
   wire mem_wbusy = 1'b0;

   /***************************************************************************/
   // Uninitialised RAM. 64 kb
   /***************************************************************************/

   wire [31:0] ram_rdata;

   ice40up5k_spram ram(
      .clk(clk),
      .wen(mem_wmask & {4{mem_address_is_ram}}),
      .addr(mem_address[15:2]),
      .wdata(mem_wdata),
      .rdata(ram_rdata)
   );

   /***************************************************************************/
   // Boot memory, initialised BRAMs. 1 kb
   /***************************************************************************/

   reg [31:0] BOOT[1024/4-1:0]; initial $readmemh("bootloader.hex", BOOT);

   reg [31:0] boot_rdata;

   always @(posedge clk) begin

      if (mem_wmask[0] & mem_address_is_boot) BOOT[mem_address[15:2]][ 7:0 ] <= mem_wdata[ 7:0 ];
      if (mem_wmask[1] & mem_address_is_boot) BOOT[mem_address[15:2]][15:8 ] <= mem_wdata[15:8 ];
      if (mem_wmask[2] & mem_address_is_boot) BOOT[mem_address[15:2]][23:16] <= mem_wdata[23:16];
      if (mem_wmask[3] & mem_address_is_boot) BOOT[mem_address[15:2]][31:24] <= mem_wdata[31:24];

      boot_rdata <= BOOT[mem_address[15:2]];
   end

endmodule
