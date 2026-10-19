# 4x4 FPGA Matrix Multiplier (VHDL & SystemVerilog)

This repository contains a hardware 4x4 signed 8-bit (`INT8`) matrix multiplier designed for the Xilinx Artix-7 FPGA (`xc7a35tcpg236-1` on the Digilent Basys 3 board). 

## Why I Built This (and Why There Are Two Languages)

In my initial digital logic coursework and my earlier 4-bit ALU project, I wrote all of my hardware designs in **VHDL**. When I started looking deeper into computer architecture and how hardware teams at companies like NVIDIA design accelerators, I realized that almost all modern RTL design and verification in the industry is done in **SystemVerilog**. 

Instead of just reading a textbook on SystemVerilog syntax, I decided to build a hardware matrix multiplier in VHDL first (`rtl/vhdl/mat_mult_4x4.vhd`), and then port the exact same microarchitecture into SystemVerilog (`rtl/sv/mat_mult_4x4.sv`). Having both versions side-by-side with the exact same top-level pinout allowed me to test both modules against the same self-checking SystemVerilog testbench (`tb/tb_mat_mult_4x4.sv`) and see how Vivado synthesizes both languages onto the Artix-7 fabric.

---

## How the Hardware Works

If you write a standard 4x4 matrix multiplication ($C = A \times B$) in C or Python using three nested `for` loops (`i`, `j`, `k`), a CPU has to execute $4 \times 4 \times 4 = 64$ sequential multiply-accumulate operations. 

On an FPGA, we can exploit spatial parallelism using the onboard `DSP48E1` slices:
1. **Fully Sequential (1 Multiplier):** Takes 64 clock cycles. Uses very little hardware, but is slow.
2. **Fully Parallel Combinational (64 Multipliers):** Computes the whole matrix in 1 cycle, but uses 64 DSP slices at once (which hits 71% of the 90 total DSP slices available on the Basys 3 Artix-7 just for a tiny 4x4 matrix) and creates a massive routing bottleneck.
3. **Outer-Product Pipeline (16 Multipliers — This Design):** A balanced middle ground. By using 16 parallel Multiply-Accumulate (MAC) units (one for each element `C[i][j]`), the hardware computes one full step `k` across the entire 4x4 matrix every clock cycle. This finishes the entire 64-operation matrix multiply in just **4 compute clock cycles**.

### Step-by-Step State Machine (`S_IDLE` -> `S_CALC` -> `S_DONE`)

```text
Cycle 0 (S_IDLE) : Wait for start = 1. Clear all 16 C_mat[i][j] accumulators to 0.
Cycle 1 (k = 0)  : Every C[i][j] += A[i][0] * B[0][j]  (16 parallel multiplications)
Cycle 2 (k = 1)  : Every C[i][j] += A[i][1] * B[1][j]  (16 parallel multiplications)
Cycle 3 (k = 2)  : Every C[i][j] += A[i][2] * B[2][j]  (16 parallel multiplications)
Cycle 4 (k = 3)  : Every C[i][j] += A[i][3] * B[3][j]  (16 parallel multiplications)
Cycle 5 (S_DONE) : Pulse done = 1 for one clock cycle. Output C_flat is valid.
```
At a 100 MHz system clock (`10 ns` period), the entire 4x4 matrix multiplication finishes in **60 ns** (40 ns of actual math, plus 2 cycles for the FSM handshake).

---

## Key Hardware Design Decisions

### 1. Flattened 1D Input/Output Vectors (`A_flat`, `B_flat`, `C_flat`)
When I started writing the VHDL version, I ran into an annoying limitation of standard VHDL-93: you cannot directly pass a 2D array (`array (0 to 3, 0 to 3)`) through an `entity` port unless you create and import a separate custom VHDL package file to define the type first.

To keep the module self-contained in a single file—and to make sure the SystemVerilog and VHDL modules had the exact same port names so I could swap them directly inside the testbench—I flattened the 2D matrices into 1D buses at the top-level boundary:
* **`A_flat [127:0]` & `B_flat [127:0]`:** 16 elements $\times$ 8 bits = 128 bits each.
* **`C_flat [319:0]`:** 16 elements $\times$ 20 bits = 320 bits.

Inside the module, the first thing the hardware does (using zero logic gates, just wire routing) is unpack those 1D vectors back into `4x4` 2D arrays (`A_mat`, `B_mat`, `C_mat`) so the nested `i` and `j` loops in the state machine are clean and easy to read.

### 2. Bit-Growth and Accumulator Sizing (Why 20 Bits?)
One mistake I wanted to avoid was arithmetic overflow during accumulation:
* Each input in `A` and `B` is an 8-bit signed integer (`-128` to `+127`).
* Multiplying two 8-bit signed numbers produces up to a **16-bit signed product** (for example, $-128 \times -128 = +16,384$, which needs 16 bits in two's complement).
* Each position `C[i][j]` adds together 4 of those 16-bit products. Every time you double the number of additions, the result can grow by 1 bit ($\log_2(4) = 2$ extra bits), meaning a 4x4 signed 8-bit matrix multiply needs at least **18 bits** ($16 + 2$) to guarantee it never overflows.
* I rounded the accumulators up to **20 bits** (`signed(19 downto 0)` / `logic signed [19:0]`), which prevents overflow on any possible input combination and leaves enough bit headroom if I ever scale the loop count up to `16x16` ($16 + \log_2(16) = 20$ bits).

---

## What I Learned Porting VHDL to SystemVerilog

Writing the exact same hardware block in both languages made the practical differences between VHDL and SystemVerilog click for me:

1. **Indexed Part-Select (`+:`) vs. Verbose Bit Ranges:**
   In VHDL, unpacking the 128-bit `A_flat` bus into the 2D `A_mat(i, j)` array required nested `for ... generate` blocks and calculating both the MSB and LSB manually:
   ```vhdl
   A_mat(i, j) <= signed(A_flat(((i*4 + j)*8 + 7) downto ((i*4 + j)*8)));
   ```
   In SystemVerilog, I used the indexed part-select operator (`+: 8`), which just asks for the starting bit `(i*4 + j)*8` and grabs 8 bits upward inside an `always_comb` block:
   ```systemverilog
   A_mat[i][j] = signed'(A_flat[(i*4 + j)*8 +: 8]);
   ```
   That single feature makes bus unpacking much cleaner and way less likely to have an off-by-one bit error.

2. **Signed Math & Bit Resizing:**
   VHDL's `numeric_std` library is super strict about bit widths. Multiplying two 8-bit `signed` numbers produces a strictly 16-bit result, and Vivado throws a compile error if you try to add that 16-bit product directly to the 20-bit `C_mat(i, j)` accumulator without wrapping it in `resize(prod, 20)`. SystemVerilog automatically sign-extends `A_mat[i][k_idx] * B_mat[k_idx][j]` to match the 20-bit width of `C_mat[i][j]`.

3. **Explicit Hardware Blocks (`always_ff` & `always_comb`):**
   In VHDL, both combinational logic and clocked flip-flops use the exact same `process(...)` keyword, and you have to rely on how you write the sensitivity list and `rising_edge(clk)` so you don't accidentally infer a latch. SystemVerilog separates them into `always_ff` (flip-flops) and `always_comb` (combinational logic, which automatically handles the sensitivity list), so the synthesis tool immediately warns you if your code doesn't match the hardware you intended to build.

---

## Verification (`tb/tb_mat_mult_4x4.sv`)

Rather than manually poking a few numbers into a waveform viewer and checking them by hand with a calculator, I wrote a self-checking testbench in SystemVerilog that runs **20 back-to-back randomized 4x4 matrix tests** (320 total dot-product checks):
1. On each iteration, the testbench generates random signed 8-bit values between `-128` and `+127` using `$urandom_range(0, 255) - 128` and packs them into `A_flat` and `B_flat`.
2. It computes the expected answer (`exp_C[i][j]`) in software using a standard triple `for` loop.
3. It pulses `start = 1` for one clock cycle and waits for the hardware to assert `done = 1`.
4. It unpacks the 320-bit `C_flat` hardware output and compares all 16 cells against `exp_C[i][j]`. If any cell mismatches, it prints the exact test number, row/column index, and expected vs. actual values.

---

## Repository Structure

```text
├── rtl/
│   ├── vhdl/
│   │   └── mat_mult_4x4.vhd      # Original VHDL implementation
│   └── sv/
│       └── mat_mult_4x4.sv       # SystemVerilog implementation
├── tb/
│   └── tb_mat_mult_4x4.sv        # Self-checking testbench (20 random matrix tests)
└── constraints/
    └── artix7_timing.xdc         # 100 MHz clock constraint for Vivado STA
```

## How to Run in Vivado

1. Create a new RTL Project in Vivado and select the Basys 3 part (`xc7a35tcpg236-1`).
2. Under **Design Sources**, add either `rtl/sv/mat_mult_4x4.sv` OR `rtl/vhdl/mat_mult_4x4.vhd` (since both have the exact same entity/module name `mat_mult_4x4`, you can test either one without changing a single line of the testbench).
3. Under **Simulation Sources**, add `tb/tb_mat_mult_4x4.sv`.
4. Click **Run Simulation -> Run Behavioral Simulation**.
5. Look at the **Tcl Console** at the bottom of Vivado to verify the output:
   ```text
   SIMULATION PASSED: 20/20 random 4x4 matrix tests matched.
   ```
