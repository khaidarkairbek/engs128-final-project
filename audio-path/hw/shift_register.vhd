----------------------------------------------------------------------------
--  Lab 1: DDS and the Audio Codec
----------------------------------------------------------------------------
-- 	ENGS 128 Spring 2026
--	Author: Khaidar Kairbek & Kendall Farnham
----------------------------------------------------------------------------
--	Description: Shift register with parallel load and serial output
----------------------------------------------------------------------------
-- Add libraries
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

----------------------------------------------------------------------------
-- Entity definition
entity shift_register is
    Generic ( 
        DATA_WIDTH : integer := 16;
        USE_RISING_EDGE : boolean := true
    );
    Port ( 
      clk_i         : in std_logic;
      data_i        : in std_logic_vector(DATA_WIDTH-1 downto 0);
      load_en_i     : in std_logic;
      shift_en_i    : in std_logic;
      
      data_o        : out std_logic);
end shift_register;
----------------------------------------------------------------------------
architecture Behavioral of shift_register is
----------------------------------------------------------------------------
-- Define Constants and Signals
----------------------------------------------------------------------------
signal shift_reg : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');

----------------------------------------------------------------------------
begin
----------------------------------------------------------------------------
-- ++++ Describe the behavior using processes ++++
----------------------------------------------------------------------------     
data_o <= shift_reg(DATA_WIDTH-1);  -- hook up to MSB

----------------------------------------------------------------------------
-- Shift register logic
gen_rising: if USE_RISING_EDGE generate
shift_reg_logic : process (clk_i)
begin
	if (rising_edge(clk_i)) then
	   if (load_en_i = '1') then       -- load takes priority
	       shift_reg <= data_i;
	   elsif (shift_en_i = '1') then
	       shift_reg <= shift_reg(DATA_WIDTH-2 downto 0) & shift_reg(DATA_WIDTH-1); -- circular shift
	   end if;
	end if;
end process shift_reg_logic;
end generate gen_rising; 

gen_falling: if not USE_RISING_EDGE generate 
shift_reg_logic : process (clk_i)
begin
	if (falling_edge(clk_i)) then
	   if (load_en_i = '1') then       -- load takes priority
	       shift_reg <= data_i;
	   elsif (shift_en_i = '1') then
	       shift_reg <= shift_reg(DATA_WIDTH-2 downto 0) & shift_reg(DATA_WIDTH-1); -- circular shift
	   end if;
	end if;
end process shift_reg_logic;
end generate gen_falling; 

----------------------------------------------------------------------------   
end Behavioral;