----------------------------------------------------------------------------
--  Lab 1: DDS and the Audio Codec
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Kendall Farnham
----------------------------------------------------------------------------
--	Description: I2S receiver for SSM2603 audio codec
----------------------------------------------------------------------------
-- Add libraries 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.ALL;
----------------------------------------------------------------------------
-- Entity definition
entity i2s_receiver is
    Generic (AC_DATA_WIDTH : integer := 24);
    Port (

        -- Timing
		bclk_i    : in std_logic;	
		lrclk_i   : in std_logic;
		
		-- Data
		left_audio_data_o     : out std_logic_vector(AC_DATA_WIDTH-1 downto 0);
		right_audio_data_o    : out std_logic_vector(AC_DATA_WIDTH-1 downto 0);
		adc_serial_data_i     : in std_logic);  
end i2s_receiver;
----------------------------------------------------------------------------
architecture Behavioral of i2s_receiver is
----------------------------------------------------------------------------
-- Define constants, signals, and declare sub-components
----------------------------------------------------------------------------

signal lrclk_prev: std_logic := '0';
signal lrclk_edge: std_logic := '0'; 

-- Shift Register Control Signals
signal left_shift_en, right_shift_en: std_logic := '0'; 
signal shift_count: integer := 0; 
signal shift_tc: std_logic := '0';

-- Custom types for FSM 
type state_type is (WaitState, LeftShiftState, RightShiftState); 
signal curr_state, next_state: state_type := WaitState; 

component shift_register_in is
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
end component;


----------------------------------------------------------------------------
begin
----------------------------------------------------------------------------
-- Port-map sub-components, and describe the entity behavior
----------------------------------------------------------------------------
left_shift_register: shift_register_in
    generic map ( 
        DATA_WIDTH => AC_DATA_WIDTH,
        USE_RISING_EDGE => false
    ) 
    port map (
        clk_i => bclk_i,
        data_i => adc_serial_data_i,
        reset_i => '0',
        shift_en_i => left_shift_en, 

        data_o => left_audio_data_o);
        
right_shift_register: shift_register_in
    generic map ( 
        DATA_WIDTH => AC_DATA_WIDTH,
        USE_RISING_EDGE => false
    ) 
    port map (
        clk_i => bclk_i,
        data_i => adc_serial_data_i,
        reset_i => '0',
        shift_en_i => right_shift_en, 

        data_o => right_audio_data_o);

shift_counter: process (bclk_i)
begin 
    if (falling_edge(bclk_i)) then
        if (left_shift_en = '1' or right_shift_en = '1') then
            if (shift_count = AC_DATA_WIDTH - 1) then 
                shift_count <= 0; 
            else 
                shift_count <= shift_count + 1;
            end if;
        else 
            shift_count <= 0; 
        end if; 
    end if;
end process shift_counter; 

shift_tc <= '1' when shift_count = AC_DATA_WIDTH - 1 else '0';

channel_switch_process: process (bclk_i)
begin
    if (falling_edge(bclk_i)) then 
        lrclk_prev <= lrclk_i;
    end if;
end process channel_switch_process; 

lrclk_edge <= lrclk_i xor lrclk_prev; --change in lrclk 

next_state_logic: process(curr_state, lrclk_i, lrclk_edge, shift_tc)
begin
    next_state <= curr_state; 
    
    case curr_state is 
        when WaitState => 
            if (lrclk_i = '0') and (lrclk_edge = '1') then 
                next_state <= LeftShiftState;
            elsif (lrclk_i = '1') and (lrclk_edge = '1') then 
                next_state <= RightShiftState;
            end if;
        when LeftShiftState => 
            if (shift_tc = '1') then 
                next_state <= WaitState;
            end if;
        when RightShiftState => 
            if (shift_tc = '1') then
                next_state <= WaitState;  
            end if;
        when others => 
            next_state <= WaitState;
    end case;
end process next_state_logic; 

fsm_output_logic: process (curr_state)
begin 
    left_shift_en <= '0'; 
    right_shift_en <= '0';
    
    case curr_state is 
        when LeftShiftState =>
            left_shift_en <= '1';
        when RightShiftState =>
            right_shift_en <= '1';
        when others =>
    end case; 
end process fsm_output_logic; 

state_update: process (bclk_i)
begin 
    if (falling_edge(bclk_i)) then 
        curr_state <= next_state; 
    end if;
end process state_update; 
---------------------------------------------------------------------------- 
end Behavioral;