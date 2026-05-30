----------------------------------------------------------------------------
--  Lab 2: AXI Stream Receiver Interface
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek & Kendall Farnham
----------------------------------------------------------------------------
--	Description: AXI stream interface for receiving audio data
----------------------------------------------------------------------------
-- Add libraries 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;     
use IEEE.STD_LOGIC_UNSIGNED.ALL;                                    
----------------------------------------------------------------------------
-- Entity definition
entity axis_receiver_interface is
	generic (
		-- Parameters of Axi Stream Bus Interface S00_AXIS, M00_AXIS
		C_AXI_STREAM_DATA_WIDTH	: integer	:= 32;
		AC_DATA_WIDTH           : integer   := 24
	);
    Port ( 
        ----------------------------------------------------------------------------
        -- 48 kHz clock
		lrclk_i               : in  std_logic;
		left_audio_data_o     : out std_logic_vector(AC_DATA_WIDTH - 1 downto 0);
		right_audio_data_o    : out std_logic_vector(AC_DATA_WIDTH - 1 downto 0);

        
        ----------------------------------------------------------------------------
        -- AXI Stream Interface (Receiver/Responder)
    	-- Ports of Axi Responder Bus Interface S00_AXIS
		s00_axis_aclk     : in std_logic;
		s00_axis_aresetn  : in std_logic;
		s00_axis_tready   : out std_logic;
		s00_axis_tdata	  : in std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0);
		s00_axis_tstrb    : in std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0);
		s00_axis_tlast    : in std_logic;
		s00_axis_tvalid   : in std_logic);
end axis_receiver_interface;
----------------------------------------------------------------------------
architecture Behavioral of axis_receiver_interface is
----------------------------------------------------------------------------
-- Define Constants and Signals
----------------------------------------------------------------------------

signal tready : std_logic := '0';
signal temp_left_data, temp_right_data, left_data, right_data : std_logic_vector(AC_DATA_WIDTH - 1 downto 0) := (others => '0');
signal lrclk_prev, lrclk_edge : std_logic := '0';

type state_type is (LoadLeftState, LoadRightState, WaitLeftState, UpdateLeftState, WaitRightState, UpdateRightState); 
signal curr_state, next_state: state_type := LoadLeftState; 
signal load_temp_left, load_temp_right, update_left, update_right : std_logic := '0';


begin
----------------------------------------------------------------------------
-- Component instantiations
----------------------------------------------------------------------------    
---------------------------------------------------------------------------- 
-- Logic
---------------------------------------------------------------------------- 

-- new design, load both left and right 
-- load at rising edge, left and right 
-- set left when lrclk is low 
-- set right when lrclk gets high 

-- LoadLeft -> LoadRight -> WaitLeft -> UpdateLeft -> WaitRight -> UpdateRight
-- tready = 1, wait for tvalid = '1' and highest bit 0
-- tready = 1, wait for tvalid = '1' and highest bit 1 
-- tready = 0, wait for lrclk_edge = '1' and lrclk_i = '1'
-- tready = 0, update_left = '1' 
-- tready = 0, wait for lrclk_edge = '1' and lrclk_i = '0'
-- tready = 0, update_right = '1', shift to LoadLeft

temp_load_proc: process (s00_axis_aclk) 
begin 
    if rising_edge(s00_axis_aclk) then 
        
        if s00_axis_aresetn = '0' then 
            temp_left_data <= (others => '0'); 
            temp_right_data <= (others => '0');
        else 
            if (load_temp_left = '1') then 
                temp_left_data <= s00_axis_tdata(AC_DATA_WIDTH - 1 downto 0); 
            end if; 
            
            if (load_temp_right = '1') then 
                temp_right_data <= s00_axis_tdata(AC_DATA_WIDTH - 1 downto 0); 
            end if; 
        end if;
    end if; 
end process temp_load_proc;

output_proc: process (s00_axis_aclk)
begin 
    if rising_edge(s00_axis_aclk) then
        if s00_axis_aresetn = '0' then 
            left_data <= (others => '0');
            right_data <= (others => '0'); 
        else 
            if (update_left = '1') then 
                left_data <= temp_left_data;
            end if; 
            
            if (update_right = '1') then 
                right_data <= temp_right_data;
            end if;
        end if;
    end if; 
end process output_proc;

lrclk_edge_proc: process (s00_axis_aclk)
begin 
    if rising_edge(s00_axis_aclk) then
        lrclk_prev <= lrclk_i;
    end if; 
end process lrclk_edge_proc; 

lrclk_edge <= lrclk_prev xor lrclk_i;

left_audio_data_o <= left_data;
right_audio_data_o <= right_data; 
s00_axis_tready <= tready;

next_state_logic: process(curr_state, s00_axis_tvalid, s00_axis_tdata, lrclk_edge, lrclk_i)
begin
    next_state <= curr_state; 
    
    case curr_state is 
        when LoadLeftState => 
            if (s00_axis_tvalid = '1' and s00_axis_tdata(C_AXI_STREAM_DATA_WIDTH-1) = '0') then 
                next_state <= LoadRightState; 
            end if; 
        when LoadRightState => 
            if (s00_axis_tvalid = '1' and s00_axis_tdata(C_AXI_STREAM_DATA_WIDTH-1) = '1') then 
                next_state <= WaitLeftState; 
            end if; 
        when WaitLeftState => 
            if (lrclk_edge = '1' and lrclk_i = '1') then 
                next_state <= UpdateLeftState; 
            end if; 
        when UpdateLeftState => 
            next_state <= WaitRightState; 
        when WaitRightState => 
            if (lrclk_edge = '1' and lrclk_i = '0') then 
                next_state <= UpdateRightState; 
            end if; 
        when UpdateRightState =>
            next_state <= LoadLeftState; 
        when others =>
    end case;
end process next_state_logic; 

fsm_output_logic: process (curr_state)
begin 
    tready <= '0';
    load_temp_left <= '0'; 
    load_temp_right <= '0'; 
    update_left <= '0'; 
    update_right <= '0';
    
    case curr_state is 
        when LoadLeftState => 
            tready <= '1';
            load_temp_left <= '1'; 
        when LoadRightState => 
            tready <= '1'; 
            load_temp_right <= '1'; 
        when WaitLeftState => 
        when UpdateLeftState => 
            update_left <= '1'; 
        when WaitRightState => 
        when UpdateRightState =>
            update_right <= '1'; 
        when others =>
    end case;
end process fsm_output_logic; 

state_update: process (s00_axis_aclk)
begin 
    if (rising_edge(s00_axis_aclk)) then 
        if s00_axis_aresetn = '0' then 
            curr_state <= LoadLeftState;
        else
            curr_state <= next_state; 
        end if;
    end if;
end process state_update; 

----------------------------------------------------------------------------


end Behavioral;