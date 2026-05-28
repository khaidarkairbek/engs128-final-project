----------------------------------------------------------------------------
--  Final Project: Audio Controlled Video Processing
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek & Brandon Carido
----------------------------------------------------------------------------
--	Description: AXI Stream FIFO Controller/Responder Interface 
----------------------------------------------------------------------------
-- Library Declarations
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

----------------------------------------------------------------------------
-- Entity definition
entity audio_video_filter is
	generic (
	    C_S00_AXI_DATA_WIDTH	: integer	:= 32;
		C_S00_AXI_ADDR_WIDTH	: integer	:= 4;
	    
		DATA_WIDTH	: integer	:= 24
	);
	port (
	
		-- Ports of Axi Responder Bus Interface S00_AXIS
		s00_axis_aclk     : in std_logic; 
		s00_axis_aresetn  : in std_logic; 
		s00_axis_tready   : out std_logic;
		s00_axis_tdata	  : in std_logic_vector(DATA_WIDTH-1 downto 0);
		s00_axis_tkeep    : in std_logic_vector((DATA_WIDTH/8)-1 downto 0);
		s00_axis_tlast    : in std_logic;
		s00_axis_tvalid   : in std_logic;
		s00_axis_tuser    : in std_logic; 

		-- Ports of Axi Controller Bus Interface M00_AXIS
		m00_axis_aclk     : in std_logic; 
		m00_axis_aresetn  : in std_logic;
		m00_axis_tvalid   : out std_logic;
		m00_axis_tdata    : out std_logic_vector(DATA_WIDTH-1 downto 0);
		m00_axis_tkeep    : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);
		m00_axis_tlast    : out std_logic;
		m00_axis_tready   : in std_logic; 
		m00_axis_tuser    : out std_logic;
		
		-- Ports of Axi Responder/Slave Bus Interface S00_AXI (PS Clock)
		s00_axi_aclk	: in std_logic;
		s00_axi_aresetn	: in std_logic;
		s00_axi_awaddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_awprot	: in std_logic_vector(2 downto 0);
		s00_axi_awvalid	: in std_logic;
		s00_axi_awready	: out std_logic;
		s00_axi_wdata	: in std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_wstrb	: in std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
		s00_axi_wvalid	: in std_logic;
		s00_axi_wready	: out std_logic;
		s00_axi_bresp	: out std_logic_vector(1 downto 0);
		s00_axi_bvalid	: out std_logic;
		s00_axi_bready	: in std_logic;
		s00_axi_araddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_arprot	: in std_logic_vector(2 downto 0);
		s00_axi_arvalid	: in std_logic;
		s00_axi_arready	: out std_logic;
		s00_axi_rdata	: out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_rresp	: out std_logic_vector(1 downto 0);
		s00_axi_rvalid	: out std_logic;
		s00_axi_rready	: in std_logic
	);
end audio_video_filter;

----------------------------------------------------------------------------
-- Architecture Definition 
architecture Behavioral of audio_video_filter is

component audio_video_filter_axi is
    generic (
    C_S_AXI_DATA_WIDTH	: integer	:= C_S00_AXI_DATA_WIDTH;
    C_S_AXI_ADDR_WIDTH	: integer	:= C_S00_AXI_ADDR_WIDTH
    );
    port (
    ----------------------------------------------------------------------------
    -- User-defined ports
    slv_reg0_out  : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0); 
    slv_reg1_out  : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0); 
    slv_reg2_out  : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0); 
    slv_reg3_out  : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
    ----------------------------------------------------------------------------
    S_AXI_ACLK	: in std_logic;
    S_AXI_ARESETN	: in std_logic;
    S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
    S_AXI_AWVALID	: in std_logic;
    S_AXI_AWREADY	: out std_logic;
    S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
    S_AXI_WVALID	: in std_logic;
    S_AXI_WREADY	: out std_logic;
    S_AXI_BRESP	: out std_logic_vector(1 downto 0);
    S_AXI_BVALID	: out std_logic;
    S_AXI_BREADY	: in std_logic;
    S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
    S_AXI_ARVALID	: in std_logic;
    S_AXI_ARREADY	: out std_logic;
    S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    S_AXI_RRESP	: out std_logic_vector(1 downto 0);
    S_AXI_RVALID	: out std_logic;
    S_AXI_RREADY	: in std_logic
    );
end component;

signal slv_reg0, slv_reg1, slv_reg2, slv_reg3 : std_logic_vector(C_S00_AXI_DATA_WIDTH - 1 downto 0) := (others => '0'); 

-- Synchronized gain (Q4.12 fixed point)
signal r_gain_meta, r_gain_sync, g_gain_meta, g_gain_sync, b_gain_meta, b_gain_sync : unsigned(15 downto 0) := (others => '0'); 

attribute ASYNC_REG : string; 
attribute ASYNC_REG of r_gain_meta : signal is "TRUE"; 
attribute ASYNC_REG of r_gain_sync : signal is "TRUE";
attribute ASYNC_REG of g_gain_meta : signal is "TRUE"; 
attribute ASYNC_REG of g_gain_sync : signal is "TRUE";
attribute ASYNC_REG of b_gain_meta : signal is "TRUE"; 
attribute ASYNC_REG of b_gain_sync : signal is "TRUE";
attribute ASYNC_REG of slv_reg0 : signal is "TRUE";
attribute ASYNC_REG of slv_reg1 : signal is "TRUE";
attribute ASYNC_REG of slv_reg2 : signal is "TRUE";

signal r_in_reg, g_in_reg, b_in_reg : unsigned(7 downto 0) := (others => '0'); 
signal v0, u0, l0 : std_logic; -- axi-stream signal
signal k0 : std_logic_vector((DATA_WIDTH/8)-1 downto 0);

-- Stage 1: Per-channel multiply (8b x 16b = 24b)
signal r_prod, g_prod, b_prod : unsigned(23 downto 0) := (others => '0'); 
signal v1, u1, l1 : std_logic; -- axi-stream signal
signal k1 : std_logic_vector((DATA_WIDTH/8)-1 downto 0); 

-- Stage 2: Saturated 24-bit output
signal pixel_out : std_logic_vector(23 downto 0); 
signal v2, u2, l2 : std_logic; -- axi-stream signals 
signal k2 : std_logic_vector((DATA_WIDTH/8)-1 downto 0); 

-- Input is Q12.12; Output is 8 bit vector
function sat8(x : unsigned(23 downto 0)) return std_logic_vector is
begin 
    if x(23 downto 20) /= "0000" then 
        return x"FF"; -- saturate 
    else
        return std_logic_vector(x(19 downto 12));
    end if; 
end function; 


----------------------------------------------------------------------------
begin

audio_video_filter_axi_inst : audio_video_filter_axi
generic map (
    C_S_AXI_DATA_WIDTH	=> C_S00_AXI_DATA_WIDTH,
    C_S_AXI_ADDR_WIDTH	=> C_S00_AXI_ADDR_WIDTH
)
port map (
    slv_reg0_out => slv_reg0,
    slv_reg1_out => slv_reg1,
    slv_reg2_out => slv_reg2,
    slv_reg3_out => slv_reg3,
    S_AXI_ACLK	=> s00_axi_aclk,
    S_AXI_ARESETN	=> s00_axi_aresetn,
    S_AXI_AWADDR	=> s00_axi_awaddr,
    S_AXI_AWPROT	=> s00_axi_awprot,
    S_AXI_AWVALID	=> s00_axi_awvalid,
    S_AXI_AWREADY	=> s00_axi_awready,
    S_AXI_WDATA	=> s00_axi_wdata,
    S_AXI_WSTRB	=> s00_axi_wstrb,
    S_AXI_WVALID	=> s00_axi_wvalid,
    S_AXI_WREADY	=> s00_axi_wready,
    S_AXI_BRESP	=> s00_axi_bresp,
    S_AXI_BVALID	=> s00_axi_bvalid,
    S_AXI_BREADY	=> s00_axi_bready,
    S_AXI_ARADDR	=> s00_axi_araddr,
    S_AXI_ARPROT	=> s00_axi_arprot,
    S_AXI_ARVALID	=> s00_axi_arvalid,
    S_AXI_ARREADY	=> s00_axi_arready,
    S_AXI_RDATA	=> s00_axi_rdata,
    S_AXI_RRESP	=> s00_axi_rresp,
    S_AXI_RVALID	=> s00_axi_rvalid,
    S_AXI_RREADY	=> s00_axi_rready
);


cdc_proc: process (s00_axis_aclk)
begin 
    if (rising_edge(s00_axis_aclk)) then 
        if (s00_axis_aresetn = '0' or m00_axis_aresetn = '0') then 
            r_gain_meta <= x"1000";
            r_gain_sync <= x"1000"; 
            
            g_gain_meta <= x"1000";
            g_gain_sync <= x"1000"; 
            
            b_gain_meta <= x"1000";
            b_gain_sync <= x"1000"; 
        else 
            r_gain_sync <= r_gain_meta; 
            r_gain_meta <= unsigned(slv_reg0(15 downto 0));
            
            g_gain_sync <= g_gain_meta; 
            g_gain_meta <= unsigned(slv_reg1(15 downto 0));
            
            b_gain_sync <= b_gain_meta; 
            b_gain_meta <= unsigned(slv_reg2(15 downto 0));
        end if; 
    end if; 
end process;

stage_0_proc: process(s00_axis_aclk)
begin 
    if rising_edge(s00_axis_aclk) then 
        if s00_axis_aresetn = '0' or m00_axis_aresetn = '0' then 
            r_in_reg <= (others => '0'); 
            g_in_reg <= (others => '0'); 
            b_in_reg <= (others => '0'); 
            
            v0 <= '0'; 
            u0 <= '0';
            l0 <= '0'; 
            k0 <= (others => '0');
        elsif m00_axis_tready = '1' then 
            r_in_reg <= unsigned(s00_axis_tdata(23 downto 16));
            g_in_reg <= unsigned(s00_axis_tdata(15 downto 8)); 
            b_in_reg <= unsigned(s00_axis_tdata(7 downto 0)); 
            
            v0 <= s00_axis_tvalid; 
            u0 <= s00_axis_tuser; 
            l0 <= s00_axis_tlast; 
            k0 <= s00_axis_tkeep;          
        end if;
    end if;
end process stage_0_proc; 

stage_1_proc: process(s00_axis_aclk)
begin 
    if rising_edge(s00_axis_aclk) then
        if s00_axis_aresetn = '0' or m00_axis_aresetn = '0' then 
            r_prod <= (others => '0'); 
            g_prod <= (others => '0'); 
            b_prod <= (others => '0'); 
            
            v1 <= '0'; 
            u1 <= '0'; 
            l1 <= '0'; 
            k1 <= (others => '0');
        elsif m00_axis_tready = '1' then 
            r_prod <= resize(r_in_reg * r_gain_sync, 24); 
            g_prod <= resize(g_in_reg * g_gain_sync, 24); 
            b_prod <= resize(b_in_reg * b_gain_sync, 24); 
            
            v1 <= v0; 
            u1 <= u0; 
            l1 <= l0; 
            k1 <= k0;
        end if;
    end if; 
end process stage_1_proc; 

stage_2_proc: process(s00_axis_aclk)
begin 
    if rising_edge(s00_axis_aclk) then 
        if s00_axis_aresetn = '0' or m00_axis_aresetn = '0' then 
            pixel_out <= (others => '0'); 
            v2 <= '0'; 
            u2 <= '0'; 
            l2 <= '0';
        elsif m00_axis_tready = '1' then
            pixel_out <= sat8(r_prod) & sat8(g_prod) & sat8(b_prod); 
            v2 <= v1; 
            u2 <= u1;
            l2 <= l1; 
            k2 <= k1;
        end if;
    end if;
end process stage_2_proc; 



s00_axis_tready <= m00_axis_tready; 

m00_axis_tdata <= pixel_out;
m00_axis_tvalid <= v2;  
m00_axis_tkeep <= k2;
m00_axis_tlast <= l2; 
m00_axis_tuser <= u2; 


end Behavioral;
