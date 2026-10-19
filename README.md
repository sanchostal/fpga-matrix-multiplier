# 4x4 FPGA Matrix Multiplication Accelerator (VHDL & SystemVerilog)

A parameterized 4x4 signed 8-bit (`INT8`) matrix multiplication accelerator designed for the Xilinx Artix-7 FPGA (`xc7a35tcpg236-1` on the Digilent Basys 3 board).

## Overview & Motivation

In my introductory digital logic coursework (and when building my 4-bit ALU), all of our labs and projects were written in **VHDL**[cite: 2]. While looking into how hardware engineering teams build hardware accelerators for machine learning workloads, I saw that industry RTL design and verification rely heavily on **SystemVerilog**.

To bridge that gap, I built this matrix multiplier in VHDL first (`rtl/vhdl/mat_mult_4x4.vhd`) to get the state machine, memory addressing, and pipeline timing working[cite: 2]. Once the VHDL version met timing, I translated the exact same architecture into SystemVerilog (`rtl/sv/mat_mult_4x4.sv`). Both modules use the exact same top-level pinout so they can be swapped directly into the same self-checking testbench (`tb/tb_mat_mult_4x4.sv`)[cite: 2].

---

## Step-by-Step Hardware Walkthrough

A standard 4x4 matrix multiplication ($C = A \times B$) takes $4 \times 4 \times 4 = 64$ multiply-add operations. Doing them one by one takes 64 clock cycles, while doing all 64 at once in a single clock cycle takes 64 DSP slices and creates heavy routing congestion. 

This design uses a middle-ground approach: **4 parallel Multiply-Accumulate (MAC) units** mapped to FPGA DSP slices, calculating one full row of 4 elements at a time over 16 compute cycles[cite: 2].

### Step 1: Loading the Input Matrices into BRAM
Because a 4x4 matrix of 8-bit numbers (128 bits per matrix) would use too many physical I/O pins on the FPGA if wired directly to the top level, inputs `A` and `B` are stored in internal 16-element Block RAM arrays (`bram_a` and `bram_b`)[cite: 2]:
* Drive `wr_en = 1` and step `wr_addr` from `0` to `15`.
* On each rising clock edge, `wr_data_a` and `wr_data_b` write one element into `bram_a` and `bram_b`.

### Step 2: Starting the 3-State FSM (`S_IDLE` -> `S_COMPUTE` -> `S_DONE`)
A 3-state Finite State Machine controls the memory read pointers and the compute pipeline[cite: 2]:
1. **`S_IDLE`:** Resets the row counter (`row_i = 0`), inner dimension counter (`k_idx = 0`), and clears `done = 0`. When `start` is pulsed high for one clock cycle, the state transitions to `S_COMPUTE`.
2. **`S_COMPUTE`:** Generates the BRAM read addresses using `row_i` (`0` to `3`) and `k_idx` (`0` to `3`).
   * For every `row_i`, `k_idx` counts from `0` to `3` (4 cycles per row $\times$ 4 rows = 16 cycles total).
   * Once both `row_i = 3` and `k_idx = 3` finish, the FSM moves to `S_DONE`.
3. **`S_DONE`:** Waits one cycle for the final pipelined multiply-accumulate operation to finish writing to `bram_c`, pulses `done = 1` for one clock cycle, and returns to `S_IDLE`.

### Step 3: Pipelining the BRAM-to-DSP Critical Path (80 MHz to 110 MHz)
In my initial unpipelined VHDL draft, the output of `bram_a` and `bram_b` fed straight into the 8x8 multipliers and 20-bit adders in the same clock cycle. Looking at the Vivado timing report, `Fmax` was limited to **80 MHz** because the critical path ran through the BRAM read delay, the multiplier, and the adder carry chain all at once[cite: 2].

To speed it up, I added a pipeline stage (`a_pipe`, `b_pipe`, `valid_pipe`, `first_pipe`, `row_pipe`) between the memory read and the MAC datapath[cite: 2]:
* **Clock Cycle $T$ (Memory Read Stage):** The FSM reads `A[row_i][k_idx]` into `a_pipe` and reads the 4 row elements `B[k_idx][0..3]` into `b_pipe[0..3]`.
* **Clock Cycle $T+1$ (DSP Compute Stage):** When `valid_pipe = 1`, the 4 DSP slices multiply `a_pipe * b_pipe[j]` in parallel.

Splitting the memory read from the math stage shortened the critical path and increased `Fmax` from **80 MHz to 110 MHz (~38% speedup)** at the cost of just 1 extra clock cycle of latency[cite: 2].

### Step 4: Parallel MAC Execution & Bit-Growth Math
Inside the compute stage, 4 parallel MAC units (`j = 0` to `3`) calculate an entire row of `C` simultaneously[cite: 2]:
* When `first_pipe = 1` (`k_idx = 0`), the accumulators `mac_acc[0..3]` overwrite their old values with the first product `a_pipe * b_pipe[j]`.
* For `k_idx = 1, 2, 3`, `mac_acc[0..3]` adds `a_pipe * b_pipe[j]` to the running sum and updates `bram_c[row_pipe * 4 + j]`.
* **Why 20-bit Accumulators (`ACC_W = 20`)?** Multiplying two signed 8-bit numbers (`-128` to `+127`) produces up to a 16-bit signed number. Adding 4 of those 16-bit products together can grow the result by $\log_2(4) = 2$ bits (18 bits minimum). Using 20-bit accumulators prevents overflow on any corner case.

### Step 5: Reading Out the Final Matrix (`C`)
Once `done` goes high, the testbench or external controller drives `rd_addr` from `0` to `15` to read the 20-bit signed results out on `rd_data_c`.

---

## Step-by-Step Verification (`tb/tb_mat_mult_4x4.sv`)

Instead of checking waveforms manually, the testbench runs **40 directed and edge-case matrix multiplications** (640 individual element checks) against a golden reference loop[cite: 2]:

1. **Vectors 0 to 4 (Directed Corner Cases):**
   * `vec = 0`: All-zero matrices (`0 * 0 = 0`) to test reset and clearing.
   * `vec = 1`: Identity matrix multiplied by `[1..16]` to verify row and column addressing aren't swapped.
   * `vec = 2`: All `+127` elements (tests max positive accumulation: $4 \times 127 \times 127 = +64,516$).
   * `vec = 3`: All `-128` elements (tests min negative signed corner case: $4 \times (-128) \times (-128) = +65,536$).
   * `vec = 4`: Alternating `+127` and `-128` checkerboard pattern to test sign-bit toggling every cycle.
2. **Vectors 5 to 39 (35 Randomized Matrices):**
   * Fills `A` and `B` with random signed 8-bit values between `-128` and `+127`, runs the hardware, and checks every output cell against `exp_C[i][j]`.

---

## Key Differences I Learned Between VHDL and SystemVerilog

* **Address Indexing:** In VHDL, combining the 2-bit `row_i` and 2-bit `k_idx` signals into an integer array index required `to_integer(row_i & k_idx)`. In SystemVerilog, bit concatenation inside brackets is just `bram_a[{row_i, k_idx}]`.
* **Bit Width Resizing:** VHDL (`numeric_std`) requires explicit bit-matching—multiplying two 8-bit `signed` numbers produces a 16-bit result that must be wrapped in `resize(prod, ACC_W)` before adding it to a 20-bit signal. SystemVerilog automatically sign-extends `logic signed` expressions to match the left-hand accumulator width.
* **Dedicated RTL Blocks:** SystemVerilog's `always_ff` makes it explicitly clear to both the reader and the synthesis tool that the block describes clocked flip-flops, compared to VHDL's general `process(clk, rst_n)`.

---

## File Structure

```text
├── rtl/
│   ├── vhdl/
│   │   └── mat_mult_4x4.vhd      # Original VHDL implementation (4 DSPs, pipelined)
│   └── sv/
│       └── mat_mult_4x4.sv       # SystemVerilog translation
└── tb/
    └── tb_mat_mult_4x4.sv        # Self-checking testbench (40 directed & edge-case vectors)
```

## How to Run the Simulation (ModelSim / Vivado)

1. Create a new project in Vivado (`xc7a35tcpg236-1`) or ModelSim[cite: 2].
2. Add **either** `rtl/vhdl/mat_mult_4x4.vhd` **or** `rtl/sv/mat_mult_4x4.sv` as your design source (both modules are named `mat_mult_4x4` with identical ports).
3. Add `tb/tb_mat_mult_4x4.sv` as your simulation source.
4. Run the behavioral simulation. The console will output:
   ```text
   SIMULATION PASSED: 40/40 directed and edge-case matrix vectors matched.
   ```
