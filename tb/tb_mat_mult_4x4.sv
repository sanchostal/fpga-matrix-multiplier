module mat_mult_4x4 (
    input logic       clk,
    input logic       rst_n,
    input logic       start,
    input logic [127:0] A_flat,
    input logic [127:0] B_flat,
    output logic [319:0] C_flat,
    output logic      done
    ports
);

    logic signed [7:0] A_mat [4][4];
    logic signed [7:0] B_mat [4][4];
    logic signed [19:0] C_mat [4][4];

    typedef enum logic [1:0] {
        S_IDLE = 2'b00,
        S_CALC = 2'b01,
        S_DONE = 2'b10
    } state_t;

    state_t state;
    logic [1:0] k_idx;

    always_comb begin
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 4; j++) begin
                A_mat[i][j] = signed'(A_flat[(i*4 + j)*8 +: 8]);
                B_mat[i][j] = signed'(B_flat[(i*4 + j)*8 +: 8]);
                C_flat[(i*4 + j)*20 +: 20] = C_mat[i][j];
            end
        end
    end

    always_ff @( posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            k_idx <= 2'd0;
            done <= 1'b0;
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    C_mat[i][j] <= 20'sd0;
                end
            end
        end else begin
            case (state)
            S_IDLE: begin
                done <= 1'b0;
                k_idx <= 2'd0;
                if (start) begin
                    for (int i = 0; i < 4; i++) begin
                        for (int j = 0; j < 4; j++) begin
                            C_mat[i][j] <= 20'sd0;
                        end
                    end
                    state <= S_CALC;
                end
            end

            S_CALC: begin
                for (int i = 0; i < 4; i++) begin
                    for (int j = 0; j < 4; j++) begin
                        C_mat[i][j] <= C_mat[i][j] + (A_mat[i][k_idx] * B_mat[k_idx][j]);
                    end
                end

                if (k_idx == 2'd3)
                    state <= S_DONE;
                else
                    k_idx <= k_idx + 2'd1;
            end

            S_DONE; begin
                done <= 1'b1;
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end
    
endmodule
