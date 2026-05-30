----------------------------------------------------------------------------
--  Lab 1: DDS and the Audio Codec
----------------------------------------------------------------------------
-- 	ENGS 128 Spring 2026
--	Author: Khaidar Kairbek
----------------------------------------------------------------------------
--	Description: Shift register with serial load and parallel output
----------------------------------------------------------------------------
-- Add libraries
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

----------------------------------------------------------------------------
-- Entity definition
entity shift_register_in is
    Generic ( 
        DATA_WIDTH : integer := 16;
        USE_RISING_EDGE : boolean := true
    );
    Port ( 
      clk_i         : in std_logic;
      data_i        : in std_logic;
      reset_i       : in std_logic;
      shift_en_i    : in std_logic;
      
      data_o        : out std_logic_vector(DATA_WIDTH - 1 downto 0));
end shift_register_in;
----------------------------------------------------------------------------
architecture Behavioral of shift_register_in is
----------------------------------------------------------------------------
-- Define Constants and Signals
----------------------------------------------------------------------------
signal shift_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

----------------------------------------------------------------------------
begin   
data_o <= shift_reg;  -- hook up to MSB

----------------------------------------------------------------------------
-- Shift register logic
gen_rising: if USE_RISING_EDGE generate
shift_reg_logic : process (clk_i)
begin
	if (rising_edge(clk_i)) then
	   if (reset_i = '1') then       -- reset takes priority
	       shift_reg <= (others => '0');
	   elsif (shift_en_i = '1') then
	       shift_reg <= shift_reg(DATA_WIDTH-2 downto 0) & data_i;
	   end if;
	end if;
end process shift_reg_logic;
end generate gen_rising; 

gen_falling: if not USE_RISING_EDGE generate 
shift_reg_logic : process (clk_i)
begin
	if (falling_edge(clk_i)) then
	   if (reset_i = '1') then       -- reset takes priority
	       shift_reg <= (others => '0');
	   elsif (shift_en_i = '1') then
	       shift_reg <= shift_reg(DATA_WIDTH-2 downto 0) & data_i;
	   end if;
	end if;
end process shift_reg_logic;
end generate gen_falling; 

----------------------------------------------------------------------------   
end Behavioral;
