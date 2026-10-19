`timescale 1ns / 1ps

module tb_mat_mult_4x4;

    logic         clk = 0;
    logic         rst_n = 0;
    logic         start = 0;
    logic [127:0] A_flat;
    logic [127:0] B_flat;
    logic [319:0] C_flat;
    logic         done;

    logic signed [7:0]  t_A [4][4];
    logic signed [7:0]  t_B [4][4];
    logic signed [19:0] exp_C [4][4];
    logic signed [19:0] act_C;

    int err_cnt = 0;

    mat_mult_4x4 dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (start),
        .A_flat (A_flat),
        .B_flat (B_flat),
        .C_flat (C_flat),
        .done   (done)
    );

    always #5 clk = ~clk;

    initial begin
        rst_n  = 0;
        start  = 0;
        A_flat = '0;
        B_flat = '0;
        #25;
        rst_n = 1;
        #10;

        for (int test = 0; test < 20; test++) begin
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    t_A[i][j] = $urandom_range(0, 255) - 128;
                    t_B[i][j] = $urandom_range(0, 255) - 128;
                    A_flat[(i*4 + j)*8 +: 8] = t_A[i][j];
                    B_flat[(i*4 + j)*8 +: 8] = t_B[i][j];
                end
            end

            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    exp_C[i][j] = 0;
                    for (int k = 0; k < 4; k++) begin
                        exp_C[i][j] += t_A[i][k] * t_B[k][j];
                    end
                end
            end

            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            wait (done == 1);
            @(posedge clk);

            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    act_C = signed'(C_flat[(i*4 + j)*20 +: 20]);
                    if (act_C !== exp_C[i][j]) begin
                        $display("ERROR on test %0d at [%0d][%0d]: got %0d, expected %0d",
                                 test, i, j, act_C, exp_C[i][j]);
                        err_cnt++;
                    end
                end
            end
        end

        if (err_cnt == 0)
            $display("SIMULATION PASSED: 20/20 random 4x4 matrix tests matched.");
        else
            $display("SIMULATION FAILED with %0d errors.", err_cnt);

        $finish;
    end

endmodule
