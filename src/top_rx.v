`timescale 1 ns / 1 ps
module Top_rx#(
    parameter frequency = 61_440_000
)
    (
	input sck,			//61.440MHz
    input uart_rx,
	output uart_tx,

    input clk_50,
    output led_ready,
    input btn1,

	// ADC interface		
	input [15:0] adc_data,

	// I2S bus, master mode
	output DOUT,
	output BCK,
	output MCK,
	output LRCK,
	
    // DAC

	output BCK2,
	output LRCK2,

    // ltc2208 
    output PREAMP,
    output DITH,
    output SHDN,
    input OFL,
    output RAND,
    output PGA,

    // pe4302
    output wire ATT1,
    output wire ATT2,
    output wire ATT3,
    output wire ATT4,
    output wire ATT5,
    output wire ATT6,

    //reconfig
    output reg Reconfig = 1'b1,
    input Reset_Button
	);

    wire reset = 1'b1;
    wire work_rx;



    // IP para generar MCLK (12.288) a partir de sck=61.44/5
    Gowin_CLKDIV5 div5(
        .clkout(MCK), //output clkout MCK = sck/5
        .hclkin(sck), //input hclkin
        .resetn(1'b1) //input resetn
    );

    // IP PLL para generar el BCK a partir de MCK/8

    Gowin_CLKDIV8 div8(
        .clkout(BCK), //output clkout BCK = MCK/8
        .hclkin(MCK), //input hclkin
        .resetn(1'b1) //input resetn
    ); 

    assign BCK2 = BCK;
    assign LRCK2 = LRCK;

    //assign led_ready = OFL;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Parpadeo de led
////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//    reg led_output = 'd0 ;
//    reg [31:0] count='d0 ;

//    always @(posedge sck) begin
//        if(count <= frequency/5 - 1) 
//            count <= count + 'b1;
//        else begin
//            count <= 'b0;
//            led_output <= !led_output ;
//        end
//    end

//    assign led_ready = led_output ;

//Estirar el pulso (si quieres ver “actividad de overflow”)

//En vez de latch permanente, puedes encender el LED durante, por ejemplo, 100 ms cada vez que haya overflow:


    reg [23:0] ofl_cnt = 24'd0;        // ajusta bits según tu clk
    wire ofl_active = (ofl_cnt != 0);

    always @(posedge sck ) begin
      if (Reset_Button) begin
        ofl_cnt <= 0;
      end else begin
        if (OFL)
          ofl_cnt <= 24'd6_000_000;    // ~100ms si clk=60MHz (aprox)
        else if (ofl_cnt != 0)
          ofl_cnt <= ofl_cnt - 1;
      end
    end

    assign led_ready = ofl_active;


////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Aquí está el meollo de la cuestión
// ojo el módulo nuevo tiene inversión de adc_data para que lo tengas en cuenta en el CST!
////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // aqui convierte de binario directo a c2. el ltc2208 está con MODE puesto a c2 ya.
    // wire signed [15:0] adc_tc = {~adc_data[15], adc_data[14:0]};

//    reg signed [15:0] temp_ADC;

//    always @(posedge sck) 
//      temp_ADC <= adc_data;

//---------------------------------------------------------
//		De-ramdomizer
//--------------------------------------------------------- 

/*

 A Digital Output Randomizer is fitted to the LTC2208. This complements bits 15 to 1 if 
 bit 0 is 1. This helps to reduce any pickup by the A/D input of the digital outputs. 
 We need to de-ramdomize the LTC2208 data if this is turned on. 
 
*/

    reg signed [15:0]temp_ADC;

    always @ (posedge sck) 
    begin 
     if (RAND)
          begin	// RAND set so de-ramdomize
            if (adc_data[0])
              temp_ADC <= {~adc_data[15:1],adc_data[0]};
            else
              temp_ADC <= adc_data;
            end
      else
        temp_ADC <= adc_data;  // not set so just copy data	 
    end 


////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	wire signed [23:0] rx_real, rx_imag;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////////////////


////////////////get_frequency//////////////////////////

    wire [31:0] frequency_rx;
    wire [31:0] frequency_out;
    reg [31:0] frequency_reg = 32'd1179000;
    wire uart_ready;

    assign frequency_rx = frequency_reg;

// Aquí muevo con el CLK de la placa de 50mhz

    uart uart_top(
        .clk(clk_50),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .frequency_rx(frequency_rx),
        .frequency_out(frequency_out),
        .byteReady(uart_ready),
        .btn1(btn1),
        .PGA(PGA),
        .RAND(RAND),
        .SHDN(SHDN),
        .DITH(DITH),
        .PREAMP(PREAMP),
        .ATT1(ATT1),
        .ATT2(ATT2),
        .ATT3(ATT3),
        .ATT4(ATT4),
        .ATT5(ATT5),
        .ATT6(ATT6)
    );

    always @(posedge sck) begin
        if (uart_ready) begin
            frequency_reg <= frequency_out;
        end 
    end

/////////////////Recieve///////////////////////////////////////
    reciever rx(sck, frequency_rx, temp_ADC,rx_real,rx_imag);
///////////////////////////////////////////////////////////////

	// I2S module, 32 bit, master
	i2s_module i2s(reset, MCK, BCK, LRCK, DOUT, rx_real, rx_imag);

///////////////////Reconfig//////////////////////////////////////
        reg [31:0] time_r = 16'd70;
        always @(posedge sck)
        begin
           if(Reset_Button) begin
            if(time_r < 16'd70) begin time_r <= time_r + 1; Reconfig <= 0;end
            else Reconfig <= 1;
           end
           else time_r <= 0;
        end
///////////////////////////////////////////////////////////////
endmodule