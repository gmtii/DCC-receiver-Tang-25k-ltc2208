 module i2s_module (
   input  wire        reset,   // 1 = run
   input  wire        MCK,
   input  wire        BCK,
   output reg         LRCK,
   output reg         DOUT,
   input  wire [23:0] rx_real,
   input  wire [23:0] rx_imag
);

   reg [4:0]  bit_cnt;     // 31..0
   reg [31:0] shreg;
   reg [15:0] L_lat, R_lat;

    // Redondeo simétrico de 24 -> 16 bits
    wire signed [23:0] xL = rx_real;
    wire signed [23:0] xR = rx_imag;

    wire signed [15:0] Ls =
      $signed(xL[22:8]) + (xL[7] ? (xL[23] ? -16'sd1 : 16'sd1) : 16'sd0);

    wire signed [15:0] Rs =
      $signed(xR[23:8]) + (xR[7] ? (xR[23] ? -16'sd1 : 16'sd1) : 16'sd0);

    // si tu i2s espera unsigned, castea; si espera signed, deja signed
    wire [15:0] L = Ls;
    wire [15:0] R = Rs;

   always @(negedge BCK) begin
      if (!reset) begin
         bit_cnt <= 5'd31;
         LRCK    <= 1'b0;   // Left
         DOUT    <= 1'b0;
         shreg   <= 32'd0;
      end else begin
         // inicio de frame: cargar datos
         if (bit_cnt == 5'd31) begin
            L_lat <= L;
            R_lat <= R;
            shreg <= {L_lat, R_lat};
            LRCK  <= 1'b0;
         end

         // cambiar a Right justo al entrar en el segundo bloque de 16 bits
         if (bit_cnt == 5'd15) begin
            LRCK <= 1'b1;     // Right
         end

         // sacar dato MSB-first
         DOUT <= shreg[bit_cnt];

         // contador
         bit_cnt <= (bit_cnt == 0) ? 5'd31 : (bit_cnt - 1'b1);
      end
   end

endmodule
