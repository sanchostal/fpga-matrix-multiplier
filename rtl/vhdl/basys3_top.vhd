library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity basys3_top is
    port (
        clk : in  std_logic;
        sw  : in  std_logic_vector(15 downto 0);
        led : out std_logic_vector(15 downto 0)
    );
end basys3_top;

architecture rtl of basys3_top is

    signal rst_n        : std_logic;
    signal start_sw     : std_logic;
    signal wr_en        : std_logic;
    signal wr_addr      : unsigned(3 downto 0);
    signal wr_data_a    : signed(7 downto 0);
    signal wr_data_b    : signed(7 downto 0);
    signal core_start   : std_logic;
    signal rd_data_c    : signed(19 downto 0);
    signal core_done    : std_logic;
    signal latched_done : std_logic;

    type rom_t is array (0 to 15) of signed(7 downto 0);
    constant rom_A : rom_t := (
        to_signed(1, 8), to_signed(2, 8), to_signed(3, 8), to_signed(4, 8),
        to_signed(5, 8), to_signed(6, 8), to_signed(7, 8), to_signed(8, 8),
        to_signed(1, 8), to_signed(1, 8), to_signed(1, 8), to_signed(1, 8),
        to_signed(2, 8), to_signed(2, 8), to_signed(2, 8), to_signed(2, 8)
    );

    constant rom_B : rom_t := (
        to_signed(1, 8), to_signed(0, 8), to_signed(0, 8), to_signed(0, 8),
        to_signed(0, 8), to_signed(2, 8), to_signed(0, 8), to_signed(0, 8),
        to_signed(0, 8), to_signed(0, 8), to_signed(3, 8), to_signed(0, 8),
        to_signed(0, 8), to_signed(0, 8), to_signed(0, 8), to_signed(4, 8)
    );

    type w_state_t is (W_IDLE, W_LOAD, W_RUN, W_WAIT);
    signal w_state  : w_state_t;
    signal load_cnt : unsigned(3 downto 0);

begin

    rst_n    <= sw(15);
    start_sw <= sw(14);

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            w_state      <= W_IDLE;
            load_cnt     <= (others => '0');
            wr_en        <= '0';
            wr_addr      <= (others => '0');
            wr_data_a    <= (others => '0');
            wr_data_b    <= (others => '0');
            core_start   <= '0';
            latched_done <= '0';
        elsif rising_edge(clk) then
            case w_state is
                when W_IDLE =>
                    wr_en      <= '0';
                    core_start <= '0';
                    load_cnt   <= (others => '0');
                    if start_sw = '1' then
                        latched_done <= '0';
                        w_state      <= W_LOAD;
                    end if;

                when W_LOAD =>
                    wr_en     <= '1';
                    wr_addr   <= load_cnt;
                    wr_data_a <= rom_A(to_integer(load_cnt));
                    wr_data_b <= rom_B(to_integer(load_cnt));
                    if load_cnt = "1111" then
                        w_state <= W_RUN;
                    else
                        load_cnt <= load_cnt + 1;
                    end if;

                when W_RUN =>
                    wr_en      <= '0';
                    core_start <= '1';
                    w_state    <= W_WAIT;

                when W_WAIT =>
                    core_start <= '0';
                    if core_done = '1' then
                        latched_done <= '1';
                    end if;
                    if start_sw = '0' then
                        w_state <= W_IDLE;
                    end if;
            end case;
        end if;
    end process;

    dut : entity work.mat_mult_4x4
        port map (
            clk       => clk,
            rst_n     => rst_n,
            start     => core_start,
            wr_en     => wr_en,
            wr_addr   => wr_addr,
            wr_data_a => wr_data_a,
            wr_data_b => wr_data_b,
            rd_addr   => unsigned(sw(3 downto 0)),
            rd_data_c => rd_data_c,
            done      => core_done
        );

    led(15)          <= latched_done;
    led(14 downto 0) <= std_logic_vector(rd_data_c(14 downto 0));

end rtl;
