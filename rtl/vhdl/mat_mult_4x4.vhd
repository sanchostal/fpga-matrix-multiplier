library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mat_mult_4x4 is
    generic (
        DATA_W : integer := 8;
        ACC_W  : integer := 20
    );
    port (
        clk       : in  std_logic;
        rst_n     : in  std_logic;
        start     : in  std_logic;
        wr_en     : in  std_logic;
        wr_addr   : in  unsigned(3 downto 0);
        wr_data_a : in  signed(DATA_W-1 downto 0);
        wr_data_b : in  signed(DATA_W-1 downto 0);
        rd_addr   : in  unsigned(3 downto 0);
        rd_data_c : out signed(ACC_W-1 downto 0);
        done      : out std_logic
    );
end mat_mult_4x4;

architecture rtl of mat_mult_4x4 is

    type bram_t is array (0 to 15) of signed(DATA_W-1 downto 0);
    signal bram_a : bram_t := (others => (others => '0'));
    signal bram_b : bram_t := (others => (others => '0'));

    type c_ram_t is array (0 to 15) of signed(ACC_W-1 downto 0);
    signal bram_c : c_ram_t := (others => (others => '0'));

    type state_t is (S_IDLE, S_COMPUTE, S_DONE);
    signal state : state_t;

    signal row_i : unsigned(1 downto 0);
    signal k_idx : unsigned(1 downto 0);

    type row_vec_t is array (0 to 3) of signed(DATA_W-1 downto 0);
    signal a_pipe     : signed(DATA_W-1 downto 0);
    signal b_pipe     : row_vec_t;
    signal valid_pipe : std_logic;
    signal first_pipe : std_logic;
    signal row_pipe   : unsigned(1 downto 0);

    type acc_vec_t is array (0 to 3) of signed(ACC_W-1 downto 0);
    signal mac_acc : acc_vec_t;

begin

    process(clk)
    begin
        if rising_edge(clk) then
            if wr_en = '1' then
                bram_a(to_integer(wr_addr)) <= wr_data_a;
                bram_b(to_integer(wr_addr)) <= wr_data_b;
            end if;
        end if;
    end process;

    rd_data_c <= bram_c(to_integer(rd_addr));

    process(clk, rst_n)
        variable prod : signed(15 downto 0);
    begin
        if rst_n = '0' then
            state      <= S_IDLE;
            row_i      <= (others => '0');
            k_idx      <= (others => '0');
            done       <= '0';
            a_pipe     <= (others => '0');
            b_pipe     <= (others => (others => '0'));
            valid_pipe <= '0';
            first_pipe <= '0';
            row_pipe   <= (others => '0');
            mac_acc    <= (others => (others => '0'));
            bram_c     <= (others => (others => '0'));
        elsif rising_edge(clk) then
            case state is
                when S_IDLE =>
                    done       <= '0';
                    row_i      <= (others => '0');
                    k_idx      <= (others => '0');
                    valid_pipe <= '0';
                    if start = '1' then
                        state <= S_COMPUTE;
                    end if;

                when S_COMPUTE =>
                    a_pipe     <= bram_a(to_integer(row_i & k_idx));
                    b_pipe(0)  <= bram_b(to_integer(k_idx & "00"));
                    b_pipe(1)  <= bram_b(to_integer(k_idx & "01"));
                    b_pipe(2)  <= bram_b(to_integer(k_idx & "10"));
                    b_pipe(3)  <= bram_b(to_integer(k_idx & "11"));
                    valid_pipe <= '1';
                    row_pipe   <= row_i;

                    if k_idx = "00" then
                        first_pipe <= '1';
                    else
                        first_pipe <= '0';
                    end if;

                    if k_idx = "11" then
                        k_idx <= "00";
                        if row_i = "11" then
                            row_i <= "00";
                            state <= S_DONE;
                        else
                            row_i <= row_i + 1;
                        end if;
                    else
                        k_idx <= k_idx + 1;
                    end if;

                when S_DONE =>
                    valid_pipe <= '0';
                    if valid_pipe = '0' then
                        done  <= '1';
                        state <= S_IDLE;
                    end if;

                when others =>
                    state <= S_IDLE;
            end case;

            if valid_pipe = '1' then
                for j in 0 to 3 loop
                    prod := a_pipe * b_pipe(j);
                    if first_pipe = '1' then
                        mac_acc(j) <= resize(prod, ACC_W);
                        bram_c(to_integer(row_pipe) * 4 + j) <= resize(prod, ACC_W);
                    else
                        mac_acc(j) <= mac_acc(j) + resize(prod, ACC_W);
                        bram_c(to_integer(row_pipe) * 4 + j) <= mac_acc(j) + resize(prod, ACC_W);
                    end if;
                end loop;
            end if;
        end if;
    end process;

end rtl;
