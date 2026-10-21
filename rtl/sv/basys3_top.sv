`timescale 1ns / 1ps

module basys3_top (
    input  logic        clk,
    input  logic [15:0] sw,
    output logic [15:0] led
);

    logic rst_n;
    logic start_sw;
    assign rst_n    = sw[15];
    assign start_sw = sw[14];

    logic               wr_en;
    logic [3:0]         wr_addr;
    logic signed [7:0]  wr_data_a;
    logic signed [7:0]  wr_data_b;
    logic               core_start;
    logic signed [19:0] rd_data_c;
    logic               core_done;
    logic               latched_done;

    const logic signed [7:0] rom_A [0:15] = '{
        8'sd1, 8'sd2, 8'sd3, 8'sd4,
        8'sd5, 8'sd6, 8'sd7, 8'sd8,
        8'sd1, 8'sd1, 8'sd1, 8'sd1,
        8'sd2, 8'sd2, 8'sd2, 8'sd2
    };

    const logic signed [7:0] rom_B [0:15] = '{
        8'sd1, 8'sd0, 8'sd0, 8'sd0,
        8'sd0, 8'sd2, 8'sd0, 8'sd0,
        8'sd0, 8'sd0, 8'sd3, 8'sd0,
        8'sd0, 8'sd0, 8'sd0, 8'sd4
    };

    typedef enum logic [1:0] {
        W_IDLE = 2'b00,
        W_LOAD = 2'b01,
        W_RUN  = 2'b10,
        W_WAIT = 2'b11
    } w_state_t;

    w_state_t w_state;
    logic [3:0] load_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state      <= W_IDLE;
            load_cnt     <= 4'd0;
            wr_en        <= 1'b0;
            wr_addr      <= 4'd0;
            wr_data_a    <= 8'sd0;
            wr_data_b    <= 8'sd0;
            core_start   <= 1'b0;
            latched_done <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    wr_en      <= 1'b0;
                    core_start <= 1'b0;
                    load_cnt   <= 4'd0;
                    if (start_sw) begin
                        latched_done <= 1'b0;
                        w_state      <= W_LOAD;
                    end
                end

                W_LOAD: begin
                    wr_en     <= 1'b1;
                    wr_addr   <= load_cnt;
                    wr_data_a <= rom_A[load_cnt];
                    wr_data_b <= rom_B[load_cnt];
                    if (load_cnt == 4'd15) begin
                        w_state <= W_RUN;
                    end else begin
                        load_cnt <= load_cnt + 4'd1;
                    end
                end

                W_RUN: begin
                    wr_en      <= 1'b0;
                    core_start <= 1'b1;
                    w_state    <= W_WAIT;
                end

                W_WAIT: begin
                    core_start <= 1'b0;
                    if (core_done) begin
                        latched_done <= 1'b1;
                    end
                    if (!start_sw) begin
                        w_state <= W_IDLE;
                    end
                end
            endcase
        end
    end

    mat_mult_4x4 dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (core_start),
        .wr_en     (wr_en),
        .wr_addr   (wr_addr),
        .wr_data_a (wr_data_a),
        .wr_data_b (wr_data_b),
        .rd_addr   (sw[3:0]),
        .rd_data_c (rd_data_c),
        .done      (core_done)
    );

    assign led[15]   = latched_done;
    assign led[14:0] = rd_data_c[14:0];

endmodule
