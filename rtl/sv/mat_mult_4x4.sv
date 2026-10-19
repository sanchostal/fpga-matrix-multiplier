`timescale 1ns / 1ps

module mat_mult_4x4 #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 20
)(
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     start,
    input  logic                     wr_en,
    input  logic [3:0]               wr_addr,
    input  logic signed [DATA_W-1:0] wr_data_a,
    input  logic signed [DATA_W-1:0] wr_data_b,
    input  logic [3:0]               rd_addr,
    output logic signed [ACC_W-1:0]  rd_data_c,
    output logic                     done
);

    logic signed [DATA_W-1:0] bram_a [0:15];
    logic signed [DATA_W-1:0] bram_b [0:15];
    logic signed [ACC_W-1:0]  bram_c [0:15];

    typedef enum logic [1:0] {
        S_IDLE    = 2'b00,
        S_COMPUTE = 2'b01,
        S_DONE    = 2'b10
    } state_t;

    state_t state;

    logic [1:0] row_i;
    logic [1:0] k_idx;

    logic signed [DATA_W-1:0] a_rd_data;
    logic signed [DATA_W-1:0] b_rd_data [0:3];

    logic signed [DATA_W-1:0] a_pipe;
    logic signed [DATA_W-1:0] b_pipe [0:3];
    logic                     valid_pipe;
    logic                     first_pipe;
    logic [1:0]               row_pipe;

    logic signed [ACC_W-1:0]  mac_acc [0:3];

    always_ff @(posedge clk) begin
        if (wr_en) begin
            bram_a[wr_addr] <= wr_data_a;
            bram_b[wr_addr] <= wr_data_b;
        end
        a_rd_data    <= bram_a[{row_i, k_idx}];
        b_rd_data[0] <= bram_b[{k_idx, 2'd0}];
        b_rd_data[1] <= bram_b[{k_idx, 2'd1}];
        b_rd_data[2] <= bram_b[{k_idx, 2'd2}];
        b_rd_data[3] <= bram_b[{k_idx, 2'd3}];
    end

    assign rd_data_c = bram_c[rd_addr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            row_i      <= 2'd0;
            k_idx      <= 2'd0;
            done       <= 1'b0;
            a_pipe     <= '0;
            valid_pipe <= 1'b0;
            first_pipe <= 1'b0;
            row_pipe   <= 2'd0;
            for (int j = 0; j < 4; j++) begin
                b_pipe[j]  <= '0;
                mac_acc[j] <= '0;
            end
            for (int m = 0; m < 16; m++) begin
                bram_c[m] <= '0;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    done       <= 1'b0;
                    row_i      <= 2'd0;
                    k_idx      <= 2'd0;
                    valid_pipe <= 1'b0;
                    if (start) begin
                        state <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    a_pipe     <= a_rd_data;
                    b_pipe     <= b_rd_data;
                    valid_pipe <= 1'b1;
                    row_pipe   <= row_i;
                    first_pipe <= (k_idx == 2'd0);

                    if (k_idx == 2'd3) begin
                        k_idx <= 2'd0;
                        if (row_i == 2'd3) begin
                            row_i <= 2'd0;
                            state <= S_DONE;
                        end else begin
                            row_i <= row_i + 2'd1;
                        end
                    end else begin
                        k_idx <= k_idx + 2'd1;
                    end
                end

                S_DONE: begin
                    valid_pipe <= 1'b0;
                    if (!valid_pipe) begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase

            if (valid_pipe) begin
                for (int j = 0; j < 4; j++) begin
                    if (first_pipe) begin
                        mac_acc[j]               <= a_pipe * b_pipe[j];
                        bram_c[row_pipe * 4 + j] <= a_pipe * b_pipe[j];
                    end else begin
                        mac_acc[j]               <= mac_acc[j] + (a_pipe * b_pipe[j]);
                        bram_c[row_pipe * 4 + j] <= mac_acc[j] + (a_pipe * b_pipe[j]);
                    end
                end
            end
        end
    end

endmodule
