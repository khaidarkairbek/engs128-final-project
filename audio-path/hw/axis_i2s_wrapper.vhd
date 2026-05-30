----------------------------------------------------------------------------
--  Lab 2: AXI Stream FIFO and DMA
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek & Kendall Farnham
----------------------------------------------------------------------------
--	Description: AXI stream wrapper for controlling I2S audio data flow
----------------------------------------------------------------------------
-- Add libraries 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;     
use IEEE.STD_LOGIC_UNSIGNED.ALL;                                    
----------------------------------------------------------------------------
-- Entity definition
entity axis_i2s_wrapper is
	generic (
		-- Parameters of Axi Stream Bus Interface S00_AXIS, M00_AXIS
		C_AXI_STREAM_DATA_WIDTH	: integer	:= 32
	);
    Port ( 
        ----------------------------------------------------------------------------
        -- Fabric clock from Zynq PS or Clocking Wizard in block design
		sysclk_i : in  std_logic;	
		
		-- Audio Codec I2S controls
        ac_bclk_o : out STD_LOGIC;
        ac_mclk_o : out STD_LOGIC;
        ac_mute_n_o : out STD_LOGIC;	-- Active Low
        
        -- Audio Codec DAC (audio out)
        ac_dac_data_o : out STD_LOGIC;
        ac_dac_lrclk_o : out STD_LOGIC;
        
        -- Audio Codec ADC (audio in)
        ac_adc_data_i : in STD_LOGIC;
        ac_adc_lrclk_o : out STD_LOGIC;
        
        -- Debug ports 
        dbg_left_audio_rx_o : out std_logic_vector(23 downto 0);    -- left audio rx from codec 
        dbg_left_audio_tx_o : out std_logic_vector(23 downto 0);    -- left audio tx to codec 
        dbg_right_audio_rx_o : out std_logic_vector(23 downto 0);   -- right audio rx from codec 
        dbg_right_audio_tx_o : out std_logic_vector(23 downto 0);   -- right audio tx to codec
        
        ----------------------------------------------------------------------------
        -- AXI Stream Interface (Receiver/Responder)
    	-- Ports of Axi Responder Bus Interface S00_AXIS
		s00_axis_aclk     : in std_logic;
		s00_axis_aresetn  : in std_logic;
		s00_axis_tready   : out std_logic;
		s00_axis_tdata	  : in std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0);
		s00_axis_tstrb    : in std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0);
		s00_axis_tlast    : in std_logic;
		s00_axis_tvalid   : in std_logic;
		
        -- AXI Stream Interface (Tranmitter/Controller)
		-- Ports of Axi Controller Bus Interface M00_AXIS
		m00_axis_aclk     : in std_logic;
		m00_axis_aresetn  : in std_logic;
		m00_axis_tvalid   : out std_logic;
		m00_axis_tdata    : out std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0);
		m00_axis_tstrb    : out std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0);
		m00_axis_tlast    : out std_logic;
		m00_axis_tready   : in std_logic);
end axis_i2s_wrapper;
----------------------------------------------------------------------------
architecture Behavioral of axis_i2s_wrapper is
----------------------------------------------------------------------------
-- Define Constants and Signals
----------------------------------------------------------------------------
constant AC_DATA_WIDTH : integer := 24;	-- audio data width

signal lrclk, bclk, mclk : std_logic := '0'; 
signal axis_rx_left_audio_data, axis_rx_right_audio_data : std_logic_vector(AC_DATA_WIDTH - 1 downto 0) := (others => '0'); 
signal i2s_rx_left_audio_data, i2s_rx_right_audio_data : std_logic_vector(AC_DATA_WIDTH - 1 downto 0) := (others => '0');
signal rx_left_audio_data, rx_right_audio_data : std_logic_vector(AC_DATA_WIDTH - 1 downto 0) := (others => '0'); 

signal ac_mute_n : std_logic := '1'; 

----------------------------------------------------------------------------
-- Component declarations
----------------------------------------------------------------------------
-- Clock generation
component i2s_clock_gen is
    Port (

        -- System clock in
		sysclk_125MHz_i   : in  std_logic;	
		
		-- Forwarded clocks
		mclk_fwd_o		  : out std_logic;	
		bclk_fwd_o        : out std_logic;
		adc_lrclk_fwd_o   : out std_logic;
		dac_lrclk_fwd_o   : out std_logic;

        -- Clocks for I2S components
		mclk_o		      : out std_logic;	
		bclk_o            : out std_logic;
		lrclk_o           : out std_logic);  
end component;

---------------------------------------------------------------------------- 
-- I2S receiver
component i2s_receiver is
    Generic (AC_DATA_WIDTH : integer := AC_DATA_WIDTH);
    Port (

        -- Timing
		bclk_i    : in std_logic;	
		lrclk_i   : in std_logic;
		
		-- Data
		left_audio_data_o     : out std_logic_vector(AC_DATA_WIDTH-1 downto 0);
		right_audio_data_o    : out std_logic_vector(AC_DATA_WIDTH-1 downto 0);
		adc_serial_data_i     : in std_logic);  
end component; 
	
---------------------------------------------------------------------------- 
-- I2S transmitter
component i2s_transmitter is
    Generic (AC_DATA_WIDTH : integer := AC_DATA_WIDTH);
    Port (

        -- Timing
		bclk_i    : in std_logic;	
		lrclk_i   : in std_logic;
		
		-- Data
		left_audio_data_i     : in std_logic_vector(AC_DATA_WIDTH-1 downto 0);
		right_audio_data_i    : in std_logic_vector(AC_DATA_WIDTH-1 downto 0);
		dac_serial_data_o     : out std_logic);  
end component; 

---------------------------------------------------------------------------- 
-- AXI stream transmitter
component axis_transmitter_interface is
Generic (
    C_AXI_STREAM_DATA_WIDTH : integer	:= C_AXI_STREAM_DATA_WIDTH;
    AC_DATA_WIDTH           : integer   := AC_DATA_WIDTH );
Port (
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
end component axis_transmitter_interface; 
    
---------------------------------------------------------------------------- 
-- AXI stream receiver
component axis_receiver_interface is
Generic (
    C_AXI_STREAM_DATA_WIDTH : integer	:= C_AXI_STREAM_DATA_WIDTH;
    AC_DATA_WIDTH           : integer   := AC_DATA_WIDTH );
Port (
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
end component axis_receiver_interface; 

----------------------------------------------------------------------------
begin
----------------------------------------------------------------------------
-- Component instantiations
----------------------------------------------------------------------------    
-- Clock generation
clock_generation: i2s_clock_gen
port map (
    sysclk_125MHz_i     => sysclk_i,
    
    mclk_fwd_o          => ac_mclk_o,
    bclk_fwd_o          => ac_bclk_o,
    adc_lrclk_fwd_o     => ac_adc_lrclk_o,
    dac_lrclk_fwd_o     => ac_dac_lrclk_o,
    
    mclk_o              => mclk,
    bclk_o              => bclk,
    lrclk_o             => lrclk
);

---------------------------------------------------------------------------- 
-- I2S receiver
receiver: i2s_receiver
port map(
    bclk_i              => bclk,
    lrclk_i             => lrclk,
    
    left_audio_data_o   => i2s_rx_left_audio_data,
    right_audio_data_o  => i2s_rx_right_audio_data,
    adc_serial_data_i   => ac_adc_data_i
);
	
---------------------------------------------------------------------------- 
-- I2S transmitter
transmitter: i2s_transmitter
port map (
    bclk_i              => bclk,
    lrclk_i             => lrclk,
    left_audio_data_i   => axis_rx_left_audio_data, 
    right_audio_data_i  => axis_rx_right_audio_data, 
    
    dac_serial_data_o   => ac_dac_data_o    
);

---------------------------------------------------------------------------- 
-- AXI stream transmitter
axis_transmitter: axis_transmitter_interface
port map (
    lrclk_i               => lrclk,
    left_audio_data_i     => rx_left_audio_data,
    right_audio_data_i    => rx_right_audio_data,

    
    -- AXI Stream Interface (Tranmitter/Controller)
    -- Ports of Axi Controller Bus Interface M00_AXIS
    m00_axis_aclk     => m00_axis_aclk,
    m00_axis_aresetn  => m00_axis_aresetn,
    m00_axis_tvalid   => m00_axis_tvalid,
    m00_axis_tdata    => m00_axis_tdata,
    m00_axis_tstrb    => m00_axis_tstrb,
    m00_axis_tlast    => m00_axis_tlast,
    m00_axis_tready   => m00_axis_tready);
    
---------------------------------------------------------------------------- 
-- AXI stream receiver
axis_receiver: axis_receiver_interface 
port map (
    lrclk_i               => lrclk,
    left_audio_data_o     => axis_rx_left_audio_data,
    right_audio_data_o    => axis_rx_right_audio_data,
    
    ----------------------------------------------------------------------------
    -- AXI Stream Interface (Receiver/Responder)
    -- Ports of Axi Responder Bus Interface S00_AXIS
    s00_axis_aclk     => s00_axis_aclk,
    s00_axis_aresetn  => s00_axis_aresetn,
    s00_axis_tready   => s00_axis_tready,
    s00_axis_tdata	  => s00_axis_tdata,
    s00_axis_tstrb    => s00_axis_tstrb,
    s00_axis_tlast    => s00_axis_tlast,
    s00_axis_tvalid   => s00_axis_tvalid);

---------------------------------------------------------------------------- 
-- Logic
---------------------------------------------------------------------------- 

rx_left_audio_data <= i2s_rx_left_audio_data; 
rx_right_audio_data <= i2s_rx_right_audio_data; 


ac_mute_n_o <= '1'; 
dbg_left_audio_rx_o <= rx_left_audio_data;
dbg_left_audio_tx_o <= axis_rx_left_audio_data;
dbg_right_audio_rx_o <= rx_right_audio_data;
dbg_right_audio_tx_o <= axis_rx_right_audio_data;


----------------------------------------------------------------------------


end Behavioral;