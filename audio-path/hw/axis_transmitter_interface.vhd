----------------------------------------------------------------------------
--  Lab 2: AXI Stream Transmitter Interface
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek & Kendall Farnham
----------------------------------------------------------------------------
--	Description: AXI stream interface for transmitting audio data
----------------------------------------------------------------------------
-- Add libraries 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;     
use IEEE.STD_LOGIC_UNSIGNED.ALL;                                    
----------------------------------------------------------------------------
-- Entity definition
entity axis_transmitter_interface is
	generic (
		-- Parameters of Axi Stream Bus Interface S00_AXIS, M00_AXIS
		C_AXI_STREAM_DATA_WIDTH	: integer	:= 32;
		AC_DATA_WIDTH           : integer   := 24
	);
    Port ( 
        ----------------------------------------------------------------------------
        -- 48 kHz clock
		lrclk_i               : in  std_logic;
		left_audio_data_i     : in std_logic_vector(AC_DATA_WIDTH - 1 downto 0);
		right_audio_data_i    : in std_logic_vector(AC_DATA_WIDTH - 1 downto 0);

        
        -- AXI Stream Interface (Tranmitter/Controller)
		-- Ports of Axi Controller Bus Interface M00_AXIS
		m00_axis_aclk     : in std_logic;
		m00_axis_aresetn  : in std_logic;
		m00_axis_tvalid   : out std_logic;
		m00_axis_tdata    : out std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0);
		m00_axis_tstrb    : out std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0);
		m00_axis_tlast    : out std_logic;
		m00_axis_tready   : in std_logic);
end axis_transmitter_interface;
----------------------------------------------------------------------------
architecture Behavioral of axis_transmitter_interface is
----------------------------------------------------------------------------
-- Define Constants and Signals
----------------------------------------------------------------------------

signal lrclk_prev, lrclk_edge : std_logic := '0'; 
signal left_audio_data_sync, right_audio_data_sync : std_logic_vector(AC_DATA_WIDTH - 1 downto 0) := (others => '0');

type state_type is (WaitLeftState, ReadLeftState, WaitRightState, ReadRightState, WriteLeftState, WriteRightState); 
signal curr_state, next_state: state_type := WaitLeftState; 
signal tvalid, update_left, update_right, set_left, set_right : std_logic := '0';
signal temp_left_data, temp_right_data : std_logic_vector(AC_DATA_WIDTH - 1 downto 0) := (others => '0');
signal output_data : std_logic_vector(C_AXI_STREAM_DATA_WIDTH - 1 downto 0) := (others => '0');

----------------------------------------------------------------------------
-- Component declarations
----------------------------------------------------------------------------

component double_ff_sync is
    generic ( WIDTH : integer := AC_DATA_WIDTH);
    Port (
        clk_i : in std_logic; 
        async_data_i : in std_logic_vector(WIDTH - 1 downto 0); 
        async_data_o : out std_logic_vector(WIDTH - 1 downto 0)
    );
end component double_ff_sync;

begin

left_data_sync: double_ff_sync 
port map(
    clk_i => m00_axis_aclk, 
    async_data_i => left_audio_data_i, 
    async_data_o => left_audio_data_sync
);

right_data_sync: double_ff_sync 
port map(
    clk_i => m00_axis_aclk, 
    async_data_i => right_audio_data_i, 
    async_data_o => right_audio_data_sync
);


---------------------------------------------------------------------------- 
-- Logic
---------------------------------------------------------------------------- 

temp_load_proc: process(m00_axis_aclk)
begin 
    if rising_edge(m00_axis_aclk) then 
        if m00_axis_aresetn = '0' then 
            temp_left_data <= (others => '0'); 
            temp_right_data <= (others => '0'); 
        else 
            if (update_left = '1') then 
                temp_left_data <= left_audio_data_sync; 
            end if; 
            
            if (update_right = '1') then 
                temp_right_data <= right_audio_data_sync; 
            end if;
        end if; 
    end if; 
end process; 

output_proc: process (set_left, set_right, temp_left_data, temp_right_data) 
begin 
    output_data <= (others => '0'); 
    if set_left = '1' then 
        output_data(C_AXI_STREAM_DATA_WIDTH - 1) <= '0'; 
        output_data(AC_DATA_WIDTH - 1 downto 0) <= temp_left_data; 
    end if;  
    
    if set_right = '1' then 
        output_data(C_AXI_STREAM_DATA_WIDTH - 1) <= '1'; 
        output_data(AC_DATA_WIDTH - 1 downto 0) <= temp_right_data; 
    end if; 
end process; 

m00_axis_tdata <= output_data;

-- new design
-- WaitLeft -> ReadLeft -> WaitRight -> ReadRight -> WriteLeft -> WriteRight
-- tvalid = 0 , if lrclk_edge = '1' and lrclk_i = '0' -> ReadLeft 
-- tvalid = 0 , update_left = '1' 
-- tvalid = 0, if lrclk_edge = '1' and lrclk_i = '1' -> ReadRight 
-- tvalid = 0, update_right = '1'
-- tvalid = '1', set_left = '1' if tready = '1' -> WriteRight 
-- tvalid = '1', set_right = '1' if tready = '1' -> WaitLeft


lrclk_edge_proc: process (m00_axis_aclk)
begin 
    if rising_edge(m00_axis_aclk) then
        lrclk_prev <= lrclk_i;
    end if; 
end process lrclk_edge_proc; 

lrclk_edge <= lrclk_prev xor lrclk_i;

next_state_logic: process(curr_state, lrclk_edge, lrclk_i, m00_axis_tready)
begin
    next_state <= curr_state; 
    
    case curr_state is 
        when WaitLeftState => 
            if (lrclk_edge = '1' and lrclk_i = '0') then 
                next_state <= ReadLeftState; 
            end if; 
        when ReadLeftState => 
            next_state <= WaitRightState; 
        when WaitRightState => 
            if (lrclk_edge = '1' and lrclk_i = '1') then 
                next_state <= ReadRightState; 
            end if; 
        when ReadRightState => 
            next_state <= WriteLeftState;
        when WriteLeftState => 
            if (m00_axis_tready = '1') then 
                next_state <= WriteRightState; 
            end if; 
        when WriteRightState =>
            if (m00_axis_tready = '1') then 
                next_state <= WaitLeftState;
            end if; 
        when others => 
    end case;
end process next_state_logic; 

fsm_output_logic: process (curr_state)
begin 
    tvalid <= '0'; 
    update_left <= '0'; 
    update_right <= '0'; 
    set_left <= '0'; 
    set_right <= '0'; 
    
    case curr_state is
        when WaitLeftState => 
        when ReadLeftState => 
            update_left <= '1'; 
        when WaitRightState => 
        when ReadRightState => 
            update_right <= '1'; 
        when WriteLeftState => 
            set_left <= '1'; 
            tvalid <= '1'; 
        when WriteRightState =>
            set_right <= '1'; 
            tvalid <= '1'; 
        when others => 
    end case;
end process fsm_output_logic; 

state_update: process (m00_axis_aclk)
begin 
    if (rising_edge(m00_axis_aclk)) then 
        if m00_axis_aresetn = '0' then 
            curr_state <= WaitLeftState;
        else
            curr_state <= next_state; 
        end if;
    end if;
end process state_update; 

m00_axis_tlast <= '0'; 
m00_axis_tstrb <= (others => '1'); 
m00_axis_tvalid <= tvalid; 


----------------------------------------------------------------------------


end Behavioral;