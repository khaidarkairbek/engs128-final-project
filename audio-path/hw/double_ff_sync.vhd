----------------------------------------------------------------------------
--  Lab 2: Double Flip-Flop Synchronizer
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek
----------------------------------------------------------------------------
--	Description: Simple double flip-flop synchronizer
----------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity double_ff_sync is
    Generic (
        WIDTH: integer	:= 1
    );
    Port (
        clk_i : in std_logic; 
        async_data_i : in std_logic_vector(WIDTH - 1 downto 0); 
        async_data_o : out std_logic_vector(WIDTH - 1 downto 0)
    );
end double_ff_sync;

architecture Behavioral of double_ff_sync is
signal reg_metastable : std_logic_vector(WIDTH - 1 downto 0); 
begin

sync_proc: process (clk_i)
begin   
    if rising_edge(clk_i) then 
        reg_metastable <= async_data_i; 
        async_data_o <= reg_metastable;
    end if;
end process sync_proc; 

end Behavioral;
