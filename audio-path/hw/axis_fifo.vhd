----------------------------------------------------------------------------
--  Lab 2: AXI Stream FIFO and DMA
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek & Kendall Farnham
----------------------------------------------------------------------------
--	Description: AXI Stream FIFO Controller/Responder Interface 
----------------------------------------------------------------------------
-- Library Declarations
library ieee;
use ieee.std_logic_1164.all;

----------------------------------------------------------------------------
-- Entity definition
entity axis_fifo is
	generic (
		DATA_WIDTH	: integer	:= 32;
		FIFO_DEPTH	: integer	:= 1024
	);
	port (
	
		-- Ports of Axi Responder Bus Interface S00_AXIS
		s00_axis_aclk     : in std_logic;
		s00_axis_aresetn  : in std_logic;
		s00_axis_tready   : out std_logic;
		s00_axis_tdata	  : in std_logic_vector(DATA_WIDTH-1 downto 0);
		s00_axis_tstrb    : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);
		s00_axis_tlast    : in std_logic;
		s00_axis_tvalid   : in std_logic;

		-- Ports of Axi Controller Bus Interface M00_AXIS
		m00_axis_aclk     : in std_logic;
		m00_axis_aresetn  : in std_logic;
		m00_axis_tvalid   : out std_logic;
		m00_axis_tdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
		m00_axis_tstrb    : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);
		m00_axis_tlast    : out std_logic;
		m00_axis_tready   : in std_logic
	);
end axis_fifo;

----------------------------------------------------------------------------
-- Architecture Definition 
architecture Behavioral of axis_fifo is
----------------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------------  
signal full, empty, reset : std_logic; 
signal s_ready, m_valid, write_enable, read_enable : std_logic; 
signal fifo_out, fifo_in : std_logic_vector(DATA_WIDTH downto 0) := (others => '0'); 

----------------------------------------------------------------------------
-- Component Declarations
----------------------------------------------------------------------------  
component fifo is
    Generic (
		FIFO_DEPTH : integer := FIFO_DEPTH;
        DATA_WIDTH : integer := DATA_WIDTH + 1);
    Port ( 
        clk_i       : in std_logic;
        reset_i     : in std_logic;
        
        -- Write channel
        wr_en_i     : in std_logic;
        wr_data_i   : in std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Read channel
        rd_en_i     : in std_logic;
        rd_data_o   : out std_logic_vector(DATA_WIDTH-1 downto 0);
        
        -- Status flags
        empty_o         : out std_logic;
        full_o          : out std_logic);   
end component fifo;

----------------------------------------------------------------------------
begin

----------------------------------------------------------------------------
-- Component Instantiations
----------------------------------------------------------------------------
fifo_1: fifo 
port map(
    clk_i           => s00_axis_aclk,
    reset_i         => reset,
    
    wr_en_i         => write_enable,
    wr_data_i       => fifo_in,
    
    rd_en_i         => read_enable,
    rd_data_o       => fifo_out,
    
    empty_o         => empty,
    full_o          => full);   

----------------------------------------------------------------------------
-- Logic
----------------------------------------------------------------------------

write_enable <= s00_axis_tvalid and s_ready; 
read_enable <= m00_axis_tready and m_valid; 
fifo_in <= s00_axis_tlast & s00_axis_tdata; 
  
reset <= not s00_axis_aresetn or not m00_axis_aresetn;
s_ready <= '1' when (reset = '0' and full = '0') else '0'; 
m_valid <= '1' when (reset = '0' and empty = '0') else '0';

s00_axis_tready <= s_ready; 

m00_axis_tvalid <= m_valid; 
m00_axis_tstrb <= s00_axis_tstrb; 
m00_axis_tlast <= fifo_out(DATA_WIDTH);
m00_axis_tdata <= fifo_out(DATA_WIDTH - 1 downto 0);

end Behavioral;
