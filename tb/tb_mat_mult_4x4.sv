`timescale 1ns / 1ps

module tb_mat_mult_4x4;

    logic               clk = 0;
    logic               rst_n = 0;
    logic               start = 0;
    logic               wr_en = 0;
    logic [3:0]         wr_addr = 0;
    logic signed [7:0]  wr_data_a = 0;
    logic signed [7:0]  wr_data_b = 0;
    logic [3:0]         rd_addr = 0;
    logic signed [19:0] rd_data_c;
    logic               done;

    logic signed [7:0]  t_A [4][4];
    logic signed [7:0]  t_B [4][4];
    logic signed [19:0] exp_C [4][4];

    int err_cnt = 0;

    mat_mult_4x4 dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .wr_en     (wr_en),
        .wr_addr   (wr_addr),
        .wr_data_a (wr_data_a),
        .wr_data_b (wr_data_b),
        .rd_addr   (rd_addr),
        .rd_data_c (rd_data_c),
        .done      (done)
    );

    always #4.545 clk = ~clk;

    initial begin
        rst_n = 0;
        start = 0;
        wr_en = 0;
        #25;
        rst_n = 1;
        #10;

        for (int vec = 0; vec < 40; vec++) begin
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    if (vec == 0) begin
                        t_A[i][j] = 8'sd0;
                        t_B[i][j] = 8'sd0;
                    end else if (vec == 1) begin
                        t_A[i][j] = (i == j) ? 8'sd1 : 8'sd0;
                        t_B[i][j] = $signed(i * 4 + j + 1);
                    end else if (vec == 2) begin
                        t_A[i][j] = 8'sd127;
                        t_B[i][j] = 8'sd127;
                    end else if (vec == 3) begin
                        t_A[i][j] = -8'sd128;
                        t_B[i][j] = -8'sd128;
                    end else if (vec == 4) begin
                        t_A[i][j] = ((i + j) % 2 == 0) ? 8'sd127 : -8'sd128;
                        t_B[i][j] = ((i + j) % 2 == 0) ? -8'sd128 : 8'sd127;
                    end else begin
                        t_A[i][j] = $urandom_range(0, 255) - 128;
                        t_B[i][j] = $urandom_range(0, 255) - 128;
                    end
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

            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    @(posedge clk);
                    wr_en     = 1;
                    wr_addr   = i * 4 + j;
                    wr_data_a = t_A[i][j];
                    wr_data_b = t_B[i][j];
                end
            end
            @(posedge clk);
            wr_en = 0;

            @(posedge clk);
            start = 1;
            @(posedge clk);
            start = 0;

            wait (done == 1);
            @(posedge clk);

            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    rd_addr = i * 4 + j;
                    #1;
                    if (rd_data_c !== exp_C[i][j]) begin
                        $display("ERROR on vector %0d at [%0d][%0d]: got %0d, expected %0d",
                                 vec, i, j, rd_data_c, exp_C[i][j]);
                        err_cnt++;
                    end
                end
            end
        end

        if (err_cnt == 0)
            $display("SIMULATION PASSED: 40/40 directed and edge-case matrix vectors matched.");
        else
            $display("SIMULATION FAILED with %0d errors.", err_cnt);

        $finish;
    end

endmodule
