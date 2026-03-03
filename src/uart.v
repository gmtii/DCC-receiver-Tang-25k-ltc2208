module uart
#(
    // IMPORTANTE:
    // - Si clk = 50 MHz  y baud = 115200  => DELAY_FRAMES ≈ 434
    // - Si clk = 61.44 MHz y baud = 115200 => DELAY_FRAMES ≈ 533
    parameter integer DELAY_FRAMES = 434
)
(
    input  wire        clk,
    input  wire        uart_rx,
    output wire        uart_tx,
    input  wire [31:0] frequency_rx,
    output wire [31:0] frequency_out,
    output reg         byteReady,
    input  wire        btn1,   // ACTIVO A 1 (pulsado = 1)

    // --- Control pins ---
    output reg         PGA,
    output reg         RAND,
    output reg         SHDN,
    output reg         DITH,
    output reg         PREAMP,

    // --- PE4302 (6 bits) ---
    // Orden LSB->MSB: H5, J5, H8, H7, G7, G8
    output wire        ATT1,
    output wire        ATT2,
    output wire        ATT3,
    output wire        ATT4,
    output wire        ATT5,
    output wire        ATT6
);

localparam integer HALF_DELAY_WAIT = (DELAY_FRAMES / 2);

// RX
reg [3:0]  rxState       = 4'd0;
reg [13:0] rxCounter     = 14'd0;

reg [7:0]  dataIn        = 8'd0;
reg [2:0]  rxBitNumber   = 3'd0;
reg [3:0]  byteCounter   = 4'd0;
reg [31:0] receivedValue = 32'd0;

reg [3:0] cmd_f_count      = 4'd0;
reg [3:0] cmd_f_count_sent = 4'd0;

reg [3:0] cmd_q_count      = 4'd0;
reg [3:0] cmd_q_count_sent = 4'd0;

localparam RX_STATE_IDLE      = 0;
localparam RX_STATE_START_BIT = 1;
localparam RX_STATE_READ_WAIT = 2;
localparam RX_STATE_READ      = 3;
localparam RX_STATE_STOP_BIT  = 5;

localparam ASCII_LENGTH  = 8;

// Buffer TX
localparam MEMORY_LENGTH = 16;

reg [31:0] frequency_stmp = 32'd7250000;
assign frequency_out = frequency_stmp;

// --- Parser de comandos para pines: letra -> esperar '0'/'1' ---
reg       cmd_wait_value = 1'b0;
reg [2:0] cmd_sel        = 3'd0; // 0=PGA,1=RAND,2=SHDN,3=DITH,4=PREAMP

// --- Parser comando 'g' para PE4302 (decimal 0..63) ---
reg       cmd_g_active   = 1'b0;
reg [6:0] g_acc          = 7'd0;  // acumula 0..127
reg [1:0] g_digits       = 2'd0;  // 0..2

reg [5:0] att_value      = 6'd0;  // valor aplicado 0..63

// --- FIX: control robusto de "captura de frecuencia" ---
reg       freq_in_progress   = 1'b0;  // estamos recibiendo un número de frecuencia
reg       abort_freq_commit  = 1'b0;  // este byte NO debe poder hacer commit

// Mapeo a pines (LSB->MSB): H5, J5, H8, H7, G7, G8
assign ATT1 = att_value[0];
assign ATT2 = att_value[1];
assign ATT3 = att_value[2];
assign ATT4 = att_value[3];
assign ATT5 = att_value[4];
assign ATT6 = att_value[5];

// clamp a 63
function automatic [5:0] clamp63(input [6:0] v);
begin
    if (v > 7'd63) clamp63 = 6'd63;
    else           clamp63 = v[5:0];
end
endfunction

// Valores por defecto
initial begin
    PGA    = 1'b1;
    RAND   = 1'b0;
    SHDN   = 1'b0;
    DITH   = 1'b0;
    PREAMP = 1'b1;

    att_value = 6'd0;

    rxState       = RX_STATE_IDLE;
    rxCounter     = 14'd0;
    dataIn        = 8'd0;
    rxBitNumber   = 3'd0;
    byteCounter   = 4'd0;
    receivedValue = 32'd0;

    cmd_f_count      = 4'd0;
    cmd_f_count_sent = 4'd0;
    cmd_q_count      = 4'd0;
    cmd_q_count_sent = 4'd0;

    cmd_wait_value = 1'b0;
    cmd_sel        = 3'd0;

    cmd_g_active   = 1'b0;
    g_acc          = 7'd0;
    g_digits       = 2'd0;

    freq_in_progress  = 1'b0;
    abort_freq_commit = 1'b0;

    byteReady = 1'b0;
end

always @(posedge clk) begin
    case (rxState)
        RX_STATE_IDLE: begin
            if (uart_rx == 1'b0) begin
                rxState     <= RX_STATE_START_BIT;
                rxCounter   <= 14'd1;
                rxBitNumber <= 3'd0;
                byteReady   <= 1'b0;
            end
        end

        RX_STATE_START_BIT: begin
            if (rxCounter == HALF_DELAY_WAIT) begin
                rxState   <= RX_STATE_READ_WAIT;
                rxCounter <= 14'd1;
            end else begin
                rxCounter <= rxCounter + 14'd1;
            end
        end

        RX_STATE_READ_WAIT: begin
            rxCounter <= rxCounter + 14'd1;
            if ((rxCounter + 14'd1) == DELAY_FRAMES) begin
                rxState <= RX_STATE_READ;
            end
        end

        RX_STATE_READ: begin
            rxCounter   <= 14'd1;
            dataIn      <= {uart_rx, dataIn[7:1]};
            rxBitNumber <= rxBitNumber + 3'd1;
            if (rxBitNumber == 3'b111) begin
                rxState <= RX_STATE_STOP_BIT;
            end else begin
                rxState <= RX_STATE_READ_WAIT;
            end
        end

        RX_STATE_STOP_BIT: begin
            rxCounter <= rxCounter + 14'd1;
            if ((rxCounter + 14'd1) == DELAY_FRAMES) begin
                rxCounter <= 14'd0;
                byteReady <= 1'b1;
                rxState   <= RX_STATE_IDLE;

                // por defecto: este byte puede hacer commit, salvo que lo abortemos
                abort_freq_commit <= 1'b0;

                // -----------------------------
                //   PARSER DE COMANDOS / DATOS
                // -----------------------------

                // 1) Si estamos esperando el valor '0'/'1' para un pin
                if (cmd_wait_value) begin
                    // en este modo, NO queremos commits de frecuencia
                    abort_freq_commit <= 1'b1;

                    if (dataIn == 8'h30 || dataIn == 8'h31) begin // '0' o '1'
                        case (cmd_sel)
                            3'd0: PGA    <= (dataIn == 8'h31);
                            3'd1: RAND   <= (dataIn == 8'h31);
                            3'd2: SHDN   <= (dataIn == 8'h31);
                            3'd3: DITH   <= (dataIn == 8'h31);
                            3'd4: PREAMP <= (dataIn == 8'h31);
                            default: ;
                        endcase
                        cmd_wait_value <= 1'b0;
                    end
                    // cancelar si entra CR/LF mientras esperaba
                    if (dataIn == 8'h0D || dataIn == 8'h0A) begin
                        cmd_wait_value <= 1'b0;
                    end

                    // aborta cualquier frecuencia pendiente
                    freq_in_progress <= 1'b0;
                    byteCounter      <= 4'd0;
                    receivedValue    <= 32'd0;
                end

                // 2) Si estamos en modo 'g' leyendo el número de atenuación
                else if (cmd_g_active) begin
                    // en este modo, NO queremos commits de frecuencia
                    abort_freq_commit <= 1'b1;

                    if (dataIn >= 8'h30 && dataIn <= 8'h39) begin // dígito
                        g_acc    <= (g_acc * 7'd10) + (dataIn - 8'h30);
                        g_digits <= g_digits + 2'd1;

                        // si ya tenemos 2 dígitos, aplicamos ya y salimos
                        if (g_digits == 2'd1) begin
                            att_value    <= clamp63((g_acc * 7'd10) + (dataIn - 8'h30));
                            cmd_g_active <= 1'b0;
                            g_acc        <= 7'd0;
                            g_digits     <= 2'd0;
                        end
                    end
                    else begin
                        // terminador (CR/LF o cualquier no-dígito): aplicar si hubo al menos 1 dígito
                        if (g_digits != 2'd0) begin
                            att_value <= clamp63(g_acc);
                        end
                        cmd_g_active <= 1'b0;
                        g_acc        <= 7'd0;
                        g_digits     <= 2'd0;
                    end

                    // aborta cualquier frecuencia pendiente
                    freq_in_progress <= 1'b0;
                    byteCounter      <= 4'd0;
                    receivedValue    <= 32'd0;
                end

                // 3) Modo normal: comandos y/o frecuencia
                else begin
                    // Comando: 'Q'/'q' => pedir estado
                    if (dataIn == 8'h51 || dataIn == 8'h71) begin
                        cmd_q_count        <= cmd_q_count + 4'd1;
                        abort_freq_commit  <= 1'b1;
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    // Comando: 'f'/'F' => pedir envío de frecuencia
                    else if (dataIn == 8'h66 || dataIn == 8'h46) begin
                        cmd_f_count        <= cmd_f_count + 4'd1;
                        abort_freq_commit  <= 1'b1;
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    // Comando: 'g'/'G' => leer atenuación 0..63 (decimal)
                    else if (dataIn == 8'h67 || dataIn == 8'h47) begin // 'g'/'G'
                        cmd_g_active       <= 1'b1;
                        g_acc              <= 7'd0;
                        g_digits           <= 2'd0;

                        abort_freq_commit  <= 1'b1;   // <-- CLAVE
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    // Comandos para pines (letra -> esperar '0'/'1')
                    else if (dataIn == 8'h50 || dataIn == 8'h70) begin // 'P'/'p'
                        cmd_sel            <= 3'd0; cmd_wait_value <= 1'b1;
                        abort_freq_commit  <= 1'b1;
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    else if (dataIn == 8'h52 || dataIn == 8'h72) begin // 'R'/'r'
                        cmd_sel            <= 3'd1; cmd_wait_value <= 1'b1;
                        abort_freq_commit  <= 1'b1;
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    else if (dataIn == 8'h53 || dataIn == 8'h73) begin // 'S'/'s'
                        cmd_sel            <= 3'd2; cmd_wait_value <= 1'b1;
                        abort_freq_commit  <= 1'b1;
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    else if (dataIn == 8'h44 || dataIn == 8'h64) begin // 'D'/'d'
                        cmd_sel            <= 3'd3; cmd_wait_value <= 1'b1;
                        abort_freq_commit  <= 1'b1;
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    else if (dataIn == 8'h41 || dataIn == 8'h61) begin // 'A'/'a'
                        cmd_sel            <= 3'd4; cmd_wait_value <= 1'b1;
                        abort_freq_commit  <= 1'b1;
                        freq_in_progress   <= 1'b0;
                        byteCounter        <= 4'd0;
                        receivedValue      <= 32'd0;
                    end
                    // Dígitos ASCII para frecuencia
                    else if (dataIn >= 8'h30 && dataIn <= 8'h39) begin
                        receivedValue     <= (receivedValue * 10) + (dataIn - 8'h30);
                        byteCounter       <= byteCounter + 4'd1;
                        freq_in_progress  <= 1'b1;
                    end
                    else begin
                        // cualquier otro carácter en modo normal: si estabas metiendo frecuencia, lo aborta
                        // (evita commits raros con basura)
                        if (freq_in_progress) begin
                            freq_in_progress <= 1'b0;
                            byteCounter      <= 4'd0;
                            receivedValue    <= 32'd0;
                            abort_freq_commit<= 1'b1;
                        end
                    end
                end

                // Fin de número (CR/LF o longitud) -> actualizar frecuencia
                // Solo si realmente estábamos capturando frecuencia y este byte no ha sido "abort"
                if (!cmd_wait_value && !cmd_g_active && !abort_freq_commit) begin
                    if (freq_in_progress &&
                        (dataIn == 8'h0D || dataIn == 8'h0A || byteCounter == ASCII_LENGTH)) begin
                        byteCounter       <= 4'd0;
                        frequency_stmp    <= receivedValue;
                        receivedValue     <= 32'd0;
                        freq_in_progress  <= 1'b0;
                    end
                end
            end
        end
    endcase
end

// -----------------------------
//              TX
// -----------------------------
reg [3:0]  txState       = 4'd0;
reg [24:0] txCounter     = 25'd0;
reg [7:0]  dataOut       = 8'd0;
reg        txPinRegister = 1'b1;
reg [2:0]  txBitNumber   = 3'd0;
reg [3:0]  txByteCounter = 4'd0;

assign uart_tx = txPinRegister;

reg [7:0]  text [0:MEMORY_LENGTH-1];
integer    i;
reg [3:0]  digit;
reg [31:0] frequency_tmp;

// LATCH del tipo de mensaje AL INICIO del TX (evita que Q y f se confundan)
reg        tx_is_status = 1'b0; // 1 => estado (Q), 0 => frecuencia (f/botón)

initial begin
    txState       = 4'd0;
    txCounter     = 25'd0;
    dataOut       = 8'd0;
    txPinRegister = 1'b1;
    txBitNumber   = 3'd0;
    txByteCounter = 4'd0;
    tx_is_status  = 1'b0;
end

always @(*) begin
    // defaults (no latches)
    frequency_tmp = frequency_rx;
    digit         = 4'd0;

    for (i = 0; i < MEMORY_LENGTH; i = i + 1)
        text[i] = 8'h20; // ' '

    if (tx_is_status) begin
        // Estado: P#R#S#D#A#\r  (11 bytes)
        text[0]  = 8'h50; // 'P'
        text[1]  = PGA    ? 8'h31 : 8'h30;

        text[2]  = 8'h52; // 'R'
        text[3]  = RAND   ? 8'h31 : 8'h30;

        text[4]  = 8'h53; // 'S'
        text[5]  = SHDN   ? 8'h31 : 8'h30;

        text[6]  = 8'h44; // 'D'
        text[7]  = DITH   ? 8'h31 : 8'h30;

        text[8]  = 8'h41; // 'A'
        text[9]  = PREAMP ? 8'h31 : 8'h30;

        text[10] = 8'h0D; // CR
    end else begin
        // Frecuencia: 8 dígitos + CR (9 bytes)
        for (i = 0; i < 8; i = i + 1) begin
            digit          = frequency_tmp % 10;
            text[7-i]      = digit + 8'h30;
            frequency_tmp  = frequency_tmp / 10;
        end
        text[8] = 8'h0D; // CR
    end
end

localparam TX_STATE_IDLE      = 0;
localparam TX_STATE_START_BIT = 1;
localparam TX_STATE_WRITE     = 2;
localparam TX_STATE_STOP_BIT  = 3;
localparam TX_STATE_DEBOUNCE  = 4;

wire [3:0] tx_msg_len = tx_is_status ? 4'd11 : 4'd9;

always @(posedge clk) begin
    case (txState)
        TX_STATE_IDLE: begin
            // Prioridad: Q sobre f sobre botón
            if (cmd_q_count_sent != cmd_q_count) begin
                tx_is_status      <= 1'b1;        // <-- latch tipo mensaje
                cmd_q_count_sent  <= cmd_q_count;

                txState       <= TX_STATE_START_BIT;
                txCounter     <= 25'd0;
                txByteCounter <= 4'd0;
            end
            else if (cmd_f_count_sent != cmd_f_count) begin
                tx_is_status      <= 1'b0;        // <-- latch tipo mensaje
                cmd_f_count_sent  <= cmd_f_count;

                txState       <= TX_STATE_START_BIT;
                txCounter     <= 25'd0;
                txByteCounter <= 4'd0;
            end
            else if (btn1 == 1'b1) begin // botón ACTIVO A 1
                tx_is_status  <= 1'b0;            // botón => frecuencia
                txState       <= TX_STATE_START_BIT;
                txCounter     <= 25'd0;
                txByteCounter <= 4'd0;
            end
            else begin
                txPinRegister <= 1'b1;
            end
        end

        TX_STATE_START_BIT: begin
            txPinRegister <= 1'b0;
            if ((txCounter + 25'd1) == DELAY_FRAMES) begin
                txState     <= TX_STATE_WRITE;
                dataOut     <= text[txByteCounter];
                txBitNumber <= 3'd0;
                txCounter   <= 25'd0;
            end else begin
                txCounter <= txCounter + 25'd1;
            end
        end

        TX_STATE_WRITE: begin
            txPinRegister <= dataOut[txBitNumber];
            if ((txCounter + 25'd1) == DELAY_FRAMES) begin
                if (txBitNumber == 3'b111) begin
                    txState <= TX_STATE_STOP_BIT;
                end else begin
                    txBitNumber <= txBitNumber + 3'd1;
                end
                txCounter <= 25'd0;
            end else begin
                txCounter <= txCounter + 25'd1;
            end
        end

        TX_STATE_STOP_BIT: begin
            txPinRegister <= 1'b1;
            if ((txCounter + 25'd1) == DELAY_FRAMES) begin
                if (txByteCounter == tx_msg_len - 1) begin
                    txState <= TX_STATE_DEBOUNCE;
                end else begin
                    txByteCounter <= txByteCounter + 4'd1;
                    txState <= TX_STATE_START_BIT;
                end
                txCounter <= 25'd0;
            end else begin
                txCounter <= txCounter + 25'd1;
            end
        end

        TX_STATE_DEBOUNCE: begin
            // espera un rato y, si el botón estaba causando TX, espera a que se suelte
            if (txCounter == 25'h1FFFFF) begin
                if (btn1 == 1'b0) // suelto
                    txState <= TX_STATE_IDLE;
            end else begin
                txCounter <= txCounter + 25'd1;
            end
        end
    endcase
end

endmodule
