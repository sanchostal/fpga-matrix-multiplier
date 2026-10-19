library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mat_mult_4x4 is
    Port (
        clk : in std_logic;
        rst_n : in std_logic;
        start : in std_logic;
        A_flat: in std_logic_vector(127 downto 0);
        B_flat: in std_logic_vector(127 downto 0);
        C_flat: out std_logic_vector(319 downto 0);
        done  : out std_logic
    );
end mat_mult_4x4;

architecture rtl of mat_mult_4x4 is

        type mat_in_t is array( 0 to 3, 0 to 3) of signed(7 downto 0);
        type mat_acc_t is array( 0 to 3, 0 to 3) of signed(19 downto 0);

        signal A_mat : mat_in_t;
        signal B_mat : mat_in_t;
        signal C_mat : mat_acc_t;

        type state_t is (S_IDLE, S_CALC, S_DONE);
        signal state : state_t;

        signal k_idx : integer range 0 to 3;

begin

    gen_unpack_r : for i in 0 to 3 generate
        gen_unpack_c : for j in 0 to 3 generate
            A_mat(i, j) <= signed(A_flat(((i*4 + j)*8 + 7) downto ((i*4 + j)*8)));
            B_mat(i, j) <= signed(A_flat(((i*4 + j)*8 + 7) downto ((i*4 + j)*8)));
            C_flat(((i*4 + j)*20 + 19) downto ((i*4 + j)*20)) <= std_logic_vector(C_mat(i, j));
        end generate;
    end generate;

    process (clk, rst_n)
        variable prod : signed(15 downto 0);
    begin
        if rst_n = '0' then 
            state <= S_IDLE;
            k_idx <= 0;
            done <= '0';
            for i in 0 to 3 loop
                for j in 0 to 3 loop
                    C_mat(i, j) <= (others => '0');
                end loop;
            end loop;
        elsif rising_edge(clk) then
            case state is 
                when S_IDLE =>
                    done <= '0';
                    k_idx <= 0;
                    if start = '1' then
                        for i in 0 to 3 loop
                            for j in 0 to 3 loop
                                C_mat(i, j) <= (others => '0');
                            end loop;
                        end loop;
                        state <= S_CALC;
                    end if;
            
                when S_CALC =>
                    for i in 0 to 3 loop 
                        for j in 0 to 3 loop
                            prod := A_mat(i, k_idx) * B_mat(k_idx, j);
                            C_mat(i, j) <= C_mat(i, j) + resize(prod, 20);
                        end loop;
                    end loop;

                    if k_idx = 3 then 
                        state <= S_DONE;
                    else
                        k_idx <= k_idx + 1;
                    end if;
                
                when S_DONE =>
                    done <= '1';
                    state <= S_IDLE;

                when others =>
                    state <= S_IDLE;
            end case;
        end if;
    end process;

end rtl;

