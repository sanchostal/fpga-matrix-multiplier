# 4x4 FPGA Matrix Multiplier (VHDL & SystemVerilog)

This repo has my 4x4 signed 8-bit matrix multiplication accelerator for the Artix-7 FPGA (`xc7a35tcpg236-1` on the Basys 3 board).

## Background

In my digital logic class (and when I made my 4-bit ALU), we used VHDL for everything. When I started looking into computer architecture and hardware internships, I noticed almost everyone in industry uses SystemVerilog for RTL design and verification. 

To learn SystemVerilog properly, I built this project in VHDL first (`rtl/vhdl/mat_mult_4x4.vhd`)[cite: 1], got the state machine and pipelining working, and then rewrote the exact same design in SystemVerilog (`rtl/sv/mat_mult_4x4.sv`). Both versions have the exact same ports so I could test both of them with the same SystemVerilog testbench (`tb/tb_mat_mult_4x4.sv`) and run them on my Basys 3 board.

## How the Design Works

A normal 4x4 matrix multiply takes 64 multiply-adds. Doing 1 per clock cycle takes 64 cycles, and doing all 64 at once uses up way too many DSP slices on the Basys 3. Instead, I mapped the math to **4 parallel MAC units (4 DSP slices)** so it calculates one row of 4 elements at a time[cite: 1]:

1. **BRAM Storage:** You can't wire full matrices to top-level FPGA pins without running out of I/O pins, so matrices `A` and `B` are written into internal 16-element memory arrays (`bram_a` and `bram_b`) using `wr_en` and `wr_addr`[cite: 1].
2. **3-State FSM (`S_IDLE`, `S_COMPUTE`, `S_DONE`):** When `start` goes high, the state machine uses two 2-bit counters (`row_i` and `k_idx`) to step through the BRAM addresses[cite: 1]. Every cycle, it reads `A[row_i][k_idx]` and all four elements of row `k_idx` from `B` (`B[k_idx][0..3]`). It takes 4 cycles to finish one row of `C`, and 16 compute cycles for the whole 4x4 matrix.
3. **20-bit Accumulators:** Multiplying two signed 8-bit numbers (`-128` to `127`) gives a 16-bit product. Adding 4 of them together needs at least 18 bits so it doesn't overflow, so I set the accumulator width (`ACC_W`) to 20 bits.

## Timing & Pipelining (80 MHz to 110 MHz)

In my first VHDL version, I wired the BRAM read outputs straight into the multipliers in the same clock cycle. When I checked the Vivado timing report, `Fmax` was stuck around **80 MHz** because the critical path went through the memory read, the multiplier, and the 20-bit adder all in one cycle[cite: 1].

I added pipeline registers (`a_pipe`, `b_pipe`, `valid_pipe`, `first_pipe`, `row_pipe`) between the BRAM read stage and the 4 MAC units[cite: 1]. That broke up the critical path and pushed `Fmax` from **80 MHz to ~110 MHz (~38% faster)** while only adding 1 extra clock cycle of latency[cite: 1].

## VHDL vs SystemVerilog Notes

* In VHDL, turning the 2-bit `row_i` and `k_idx` counters into a 4-bit RAM address required `to_integer(row_i & k_idx)`. In SystemVerilog it is just `bram_a[{row_i, k_idx}]`.
* VHDL's `numeric_std` makes you manually call `resize(prod, ACC_W)` on the 16-bit multiplier output before adding it to the 20-bit accumulator. SystemVerilog sign-extends `logic signed` values automatically.

## Testing (Simulation & Basys 3 Board)

### 1. Simulation (`tb/tb_mat_mult_4x4.sv`)
The testbench runs **40 test vectors** (640 element checks total) against a reference loop[cite: 1]:
* Vectors 0-4 test corner cases: all zeros, identity matrix, max positive (`+127`), min negative (`-128`), and alternating signs[cite: 1].
* Vectors 5-39 run 35 random signed 8-bit matrices[cite: 1].

To run it in Vivado or ModelSim, add either `mat_mult_4x4.vhd` or `mat_mult_4x4.sv` as a design source, add `tb_mat_mult_4x4.sv` as a simulation source, and run behavioral simulation (hit `Run All / F3` in Vivado)[cite: 1].

### 2. Running on the Basys 3 (`basys3_top`)
Since the Basys 3 only has 16 switches and 16 LEDs, `basys3_top` wraps the multiplier with a small state machine that loads two test matrices (`rom_A` and `rom_B`) into BRAM when you flip a switch, runs the math, and lets you check all 16 answers on the LEDs:
* `SW15`: Reset (`DOWN` = reset, `UP` = run)
* `SW14`: Flip `UP` to load the matrices into BRAM and start the multiply
* `LD15`: Lights up when `done = 1`
* `SW3..SW0`: Selects which element `0` to `15` of output matrix `C` to show on `LD14..LD0` (for example, `0000` shows `1`, `0001` shows `4`, `0010` shows `9`, `0011` shows `16`)

## Files

* `rtl/vhdl/mat_mult_4x4.vhd` - VHDL matrix multiplier core[cite: 1]
* `rtl/vhdl/basys3_top.vhd` - VHDL wrapper for the Basys 3 board
* `rtl/sv/mat_mult_4x4.sv` - SystemVerilog matrix multiplier core
* `rtl/sv/basys3_top.sv` - SystemVerilog wrapper for the Basys 3 board
* `tb/tb_mat_mult_4x4.sv` - Self-checking testbench (40 vectors)[cite: 1]
* `constraints/basys3.xdc` - Basys 3 pinout and 100 MHz clock constraint
