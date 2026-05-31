----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05/29/2026 01:51:17 PM
-- Design Name: 
-- Module Name: fft_wrapper - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fft_wrapper is
generic (
    C_AXI_STREAM_DATA_WIDTH : integer := 32;
    AUDIO_DATA_WIDTH : integer := 24; 
    FFT_LENGTH : integer := 256; 
    FFT_LENGTH_LOG2 : integer := 8;
    MAG_WIDTH : integer := 32; 
    BRAM_READ_ADDR_WIDTH : integer := 13
);
port(
    aclk                : in std_logic; 
    aresetn             : in std_logic; 
    
    s_axis_tdata        : in std_logic_vector(C_AXI_STREAM_DATA_WIDTH - 1 downto 0); 
    s_axis_tvalid       : in std_logic; 
    s_axis_tready       : out std_logic; 
    s_axis_tlast        : in std_logic; 
    s_axis_tkeep        : in std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0); 
    
    m_axis_tdata        : out std_logic_vector(C_AXI_STREAM_DATA_WIDTH - 1 downto 0); 
    m_axis_tvalid       : out std_logic; 
    m_axis_tready       : in std_logic; 
    m_axis_tlast        : out std_logic; 
    m_axis_tkeep        : out std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0);
    
    bram_left_fft_clk           : in std_logic; 
    bram_left_fft_en            : in std_logic; 
    bram_left_fft_addr          : in std_logic_vector(BRAM_READ_ADDR_WIDTH - 1 downto 0); 
    bram_left_fft_dout          : out std_logic_vector(MAG_WIDTH - 1 downto 0); 
    bram_left_fft_din           : in std_logic_vector(MAG_WIDTH - 1 downto 0); -- ignored
    bram_left_fft_rst           : in std_logic; -- ignored
    bram_left_fft_we            : in std_logic_vector(MAG_WIDTH/8 - 1 downto 0); --ignored
    
    bram_right_fft_clk           : in std_logic; 
    bram_right_fft_en            : in std_logic; 
    bram_right_fft_addr          : in std_logic_vector(BRAM_READ_ADDR_WIDTH - 1 downto 0); 
    bram_right_fft_dout          : out std_logic_vector(MAG_WIDTH - 1 downto 0);
    bram_right_fft_din           : in std_logic_vector(MAG_WIDTH - 1 downto 0); -- ignored
    bram_right_fft_rst           : in std_logic; -- ignored
    bram_right_fft_we            : in std_logic_vector(MAG_WIDTH/8 - 1 downto 0) --ignored
);
end fft_wrapper;

architecture Behavioral of fft_wrapper is

component fft_bram IS
  PORT (
    clka : IN STD_LOGIC;
    ena : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(FFT_LENGTH_LOG2 - 1 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(MAG_WIDTH - 1 DOWNTO 0);
    clkb : IN STD_LOGIC;
    enb : IN STD_LOGIC;
    addrb : IN STD_LOGIC_VECTOR(FFT_LENGTH_LOG2 - 1 DOWNTO 0);
    doutb : OUT STD_LOGIC_VECTOR(MAG_WIDTH - 1 DOWNTO 0)
  );
END component;

component xfft_0
port(
    aclk : in std_logic; 
    aresetn : in std_logic; 
    
    s_axis_config_tdata     : in std_logic_vector(15 downto 0); 
    s_axis_config_tready    : out std_logic; 
    s_axis_config_tvalid    : in std_logic; 
    
    s_axis_data_tdata       : in std_logic_vector(AUDIO_DATA_WIDTH * 2 - 1 downto 0); 
    s_axis_data_tlast       : in std_logic; 
    s_axis_data_tready      : out std_logic; 
    s_axis_data_tvalid      : in std_logic; 
    
    m_axis_data_tdata       : out std_logic_vector(AUDIO_DATA_WIDTH * 2 - 1 downto 0); 
    m_axis_data_tlast       : out std_logic; 
    m_axis_data_tready      : in std_logic; 
    m_axis_data_tuser       : out std_logic_vector(FFT_LENGTH_LOG2-1 downto 0); 
    m_axis_data_tvalid      : out std_logic; 
    
    event_frame_started         : out std_logic; 
    event_tlast_unexpected      : out std_logic; 
    event_tlast_missing         : out std_logic; 
    event_status_channel_halt   : out std_logic; 
    event_data_in_channel_halt  : out std_logic; 
    event_data_out_channel_halt : out std_logic
);
end component;

signal lr_select: std_logic := '0';

--------------------------------------------------
-- LEFT FFT SIGNALS
--------------------------------------------------

signal left_config_tdata : std_logic_vector(15 downto 0) := (others => '0'); 
signal left_config_tready, left_config_tvalid : std_logic := '0'; 

signal left_fft_in_tdata : std_logic_vector(AUDIO_DATA_WIDTH * 2 - 1 downto 0) := (others => '0'); 
signal left_fft_in_tlast, left_fft_in_tready, left_fft_in_tvalid : std_logic := '0';

signal left_fft_out_tdata : std_logic_vector(AUDIO_DATA_WIDTH * 2 - 1 downto 0) := (others => '0'); 
signal left_fft_out_tlast, left_fft_out_tready, left_fft_out_tvalid : std_logic := '0';
signal left_fft_out_tuser : std_logic_vector(7 downto 0) := (others => '0'); 

signal left_sample_count : unsigned(FFT_LENGTH_LOG2 - 1 downto 0) := (others => '0'); 

signal left_config_sent : std_logic := '0';
signal left_fft_real, left_fft_imag : signed(AUDIO_DATA_WIDTH-1 downto 0) := (others => '0'); 
signal left_fft_abs_real, left_fft_abs_imag : unsigned(AUDIO_DATA_WIDTH-1 downto 0) := (others => '0'); 
signal left_fft_magnitude : unsigned(MAG_WIDTH - 1 downto 0) := (others => '0'); 

signal bram_left_tmp_en : std_logic := '0'; 
signal bram_left_tmp_we : std_logic_vector(0 downto 0) := "0"; 
signal bram_left_tmp_addr : std_logic_vector(FFT_LENGTH_LOG2 - 1 downto 0) := (others => '0'); 

--------------------------------------------------
-- RIGHT FFT SIGNALS
--------------------------------------------------

signal right_config_tdata : std_logic_vector(15 downto 0) := (others => '0'); 
signal right_config_tready, right_config_tvalid : std_logic := '0'; 

signal right_fft_in_tdata : std_logic_vector(AUDIO_DATA_WIDTH * 2 - 1 downto 0) := (others => '0'); 
signal right_fft_in_tlast, right_fft_in_tready, right_fft_in_tvalid : std_logic := '0';

signal right_fft_out_tdata : std_logic_vector(AUDIO_DATA_WIDTH * 2 - 1 downto 0) := (others => '0'); 
signal right_fft_out_tlast, right_fft_out_tready, right_fft_out_tvalid : std_logic := '0';
signal right_fft_out_tuser : std_logic_vector(7 downto 0) := (others => '0'); 

signal right_sample_count : unsigned(FFT_LENGTH_LOG2 - 1 downto 0) := (others => '0'); 

signal right_config_sent : std_logic := '0';
signal right_fft_real, right_fft_imag : signed(AUDIO_DATA_WIDTH-1 downto 0) := (others => '0'); 
signal right_fft_abs_real, right_fft_abs_imag : unsigned(AUDIO_DATA_WIDTH-1 downto 0) := (others => '0'); 
signal right_fft_magnitude : unsigned(MAG_WIDTH - 1 downto 0) := (others => '0'); 

signal bram_right_tmp_en : std_logic := '0'; 
signal bram_right_tmp_we : std_logic_vector(0 downto 0) := "0"; 
signal bram_right_tmp_addr : std_logic_vector(FFT_LENGTH_LOG2 - 1 downto 0) := (others => '0'); 

signal zero_padding : std_logic_vector(MAG_WIDTH - 1 downto 0) := (others => '0'); 

begin
lr_select <= s_axis_tdata(C_AXI_STREAM_DATA_WIDTH - 1);

-- Audio Pass Through
m_axis_tdata <= s_axis_tdata; 
m_axis_tvalid <= s_axis_tvalid; 
m_axis_tlast <= s_axis_tlast;
m_axis_tkeep <= s_axis_tkeep; 

s_axis_tready <= m_axis_tready and left_fft_in_tready and right_fft_in_tready; 

---------------------------------------------------
-- FFT INPUT
---------------------------------------------------
left_fft_in_tdata(AUDIO_DATA_WIDTH - 1 downto 0) <= s_axis_tdata(AUDIO_DATA_WIDTH - 1 downto 0);
left_fft_in_tdata(AUDIO_DATA_WIDTH * 2 - 1 downto AUDIO_DATA_WIDTH) <= (others => '0'); 

left_fft_in_tvalid <= s_axis_tvalid and m_axis_tready and not lr_select;
left_fft_in_tlast <= '1' when left_sample_count = to_unsigned(FFT_LENGTH - 1, FFT_LENGTH_LOG2) else '0'; 

left_sample_counter_proc: process (aclk)
begin 
    if rising_edge(aclk) then 
        if aresetn = '0' then 
            left_sample_count <= (others => '0'); 
        elsif left_fft_in_tvalid = '1' and left_fft_in_tready = '1' then 
            if left_fft_in_tlast = '1' then 
                left_sample_count <= (others => '0'); 
            else 
                left_sample_count <= left_sample_count + 1; 
            end if; 
        end if; 
    end if;
end process; 

right_fft_in_tdata(AUDIO_DATA_WIDTH - 1 downto 0) <= s_axis_tdata(AUDIO_DATA_WIDTH - 1 downto 0);
right_fft_in_tdata(AUDIO_DATA_WIDTH * 2 - 1 downto AUDIO_DATA_WIDTH) <= (others => '0'); 

right_fft_in_tvalid <= s_axis_tvalid and m_axis_tready and lr_select;
right_fft_in_tlast <= '1' when right_sample_count = to_unsigned(FFT_LENGTH - 1, FFT_LENGTH_LOG2) else '0'; 

right_sample_counter_proc: process (aclk)
begin 
    if rising_edge(aclk) then 
        if aresetn = '0' then 
            right_sample_count <= (others => '0'); 
        elsif right_fft_in_tvalid = '1' and right_fft_in_tready = '1' then 
            if right_fft_in_tlast = '1' then 
                right_sample_count <= (others => '0'); 
            else 
                right_sample_count <= right_sample_count + 1; 
            end if; 
        end if; 
    end if;
end process; 

-----------------------------------------------------
-- FFT CONFIG
-----------------------------------------------------
left_config_tdata <= x"0001"; -- TODO: change the value 
right_config_tdata <= x"0001";

left_config_proc: process (aclk) 
begin 
    if rising_edge(aclk) then 
        if aresetn = '1' then 
            left_config_sent <= '0'; 
            left_config_tvalid <= '0';
        elsif left_config_sent = '0' then 
            left_config_tvalid <= '1'; 
            if left_config_tready = '1' then 
                left_config_sent <= '1'; 
                left_config_tvalid <= '0'; 
            end if; 
        else 
            left_config_tvalid <= '0'; 
        end if;
    end if; 
end process; 

right_config_proc: process (aclk) 
begin 
    if rising_edge(aclk) then 
        if aresetn = '1' then 
            right_config_sent <= '0'; 
            right_config_tvalid <= '0';
        elsif right_config_sent = '0' then 
            right_config_tvalid <= '1'; 
            if right_config_tready = '1' then 
                right_config_sent <= '1'; 
                right_config_tvalid <= '0'; 
            end if; 
        else 
            right_config_tvalid <= '0'; 
        end if;
    end if; 
end process; 

left_fft_inst: xfft_0
port map(
    aclk => aclk,
    aresetn =>aresetn,
    
    s_axis_config_tdata     => left_config_tdata,
    s_axis_config_tready    => left_config_tready, 
    s_axis_config_tvalid    => left_config_tvalid,
    
    s_axis_data_tdata       => left_fft_in_tdata,
    s_axis_data_tlast       => left_fft_in_tlast,
    s_axis_data_tready      => left_fft_in_tready, 
    s_axis_data_tvalid      => left_fft_in_tvalid,
    
    m_axis_data_tdata       => left_fft_out_tdata,
    m_axis_data_tlast       => left_fft_out_tlast,
    m_axis_data_tready      => left_fft_out_tready,
    m_axis_data_tuser       => left_fft_out_tuser, 
    m_axis_data_tvalid      => left_fft_out_tvalid, 
    
    event_frame_started         => open,
    event_tlast_unexpected      => open,
    event_tlast_missing         => open,
    event_status_channel_halt   => open,
    event_data_in_channel_halt  => open,
    event_data_out_channel_halt => open
);

right_fft_inst: xfft_0
port map(
    aclk => aclk,
    aresetn =>aresetn,
    
    s_axis_config_tdata     => right_config_tdata,
    s_axis_config_tready    => right_config_tready, 
    s_axis_config_tvalid    => right_config_tvalid,
    
    s_axis_data_tdata       => right_fft_in_tdata,
    s_axis_data_tlast       => right_fft_in_tlast,
    s_axis_data_tready      => right_fft_in_tready, 
    s_axis_data_tvalid      => right_fft_in_tvalid,
    
    m_axis_data_tdata       => right_fft_out_tdata,
    m_axis_data_tlast       => right_fft_out_tlast,
    m_axis_data_tready      => right_fft_out_tready,
    m_axis_data_tuser       => right_fft_out_tuser, 
    m_axis_data_tvalid      => right_fft_out_tvalid, 
    
    event_frame_started         => open,
    event_tlast_unexpected      => open,
    event_tlast_missing         => open,
    event_status_channel_halt   => open,
    event_data_in_channel_halt  => open,
    event_data_out_channel_halt => open
);

left_fft_out_tready <= '1'; 
right_fft_out_tready <= '1'; 

left_fft_real <= signed(left_fft_out_tdata(AUDIO_DATA_WIDTH-1 downto 0));
left_fft_imag <= signed(left_fft_out_tdata(AUDIO_DATA_WIDTH * 2 - 1 downto AUDIO_DATA_WIDTH)); 

left_fft_abs_real <= unsigned(std_logic_vector(abs(left_fft_real))); 
left_fft_abs_imag <= unsigned(std_logic_vector(abs(left_fft_imag))); 

left_fft_magnitude <= resize(left_fft_abs_real, MAG_WIDTH) + resize(left_fft_abs_imag, MAG_WIDTH); 

left_fft_out_proc: process (aclk) 
begin 
    if rising_edge(aclk) then 
        if aresetn = '0' then 
            bram_left_tmp_en <= '0';
            bram_left_tmp_we <= (others => '0'); 
            bram_left_tmp_addr <= (others => '0'); 
        else 
            bram_left_tmp_en <= left_fft_out_tvalid; 
            bram_left_tmp_we <= (others => left_fft_out_tvalid); 
            if left_fft_out_tvalid = '1' then 
                bram_left_tmp_addr <= left_fft_out_tuser(FFT_LENGTH_LOG2 - 1 downto 0); 
            end if;
        end if;
    end if;
end process; 

left_fft_bram: fft_bram
port map(
    clka => aclk,
    ena => bram_left_tmp_en,
    wea => bram_left_tmp_we,
    addra => bram_left_tmp_addr,
    dina => std_logic_vector(left_fft_magnitude),
    clkb => bram_left_fft_clk,
    enb => bram_left_fft_en,
    addrb => bram_left_fft_addr(FFT_LENGTH_LOG2-1 downto 0),
    doutb => bram_left_fft_dout
);

right_fft_real <= signed(right_fft_out_tdata(AUDIO_DATA_WIDTH - 1 downto 0));
right_fft_imag <= signed(right_fft_out_tdata(AUDIO_DATA_WIDTH * 2 - 1 downto AUDIO_DATA_WIDTH)); 

right_fft_abs_real <= unsigned(std_logic_vector(abs(right_fft_real))); 
right_fft_abs_imag <= unsigned(std_logic_vector(abs(right_fft_imag))); 

right_fft_magnitude <= resize(right_fft_abs_real, MAG_WIDTH) + resize(right_fft_abs_imag, MAG_WIDTH);

right_fft_out_proc: process (aclk) 
begin 
    if rising_edge(aclk) then 
        if aresetn = '0' then 
            bram_right_tmp_en <= '0';
            bram_right_tmp_we <= (others => '0'); 
            bram_right_tmp_addr <= (others => '0'); 
        else 
            bram_right_tmp_en <= left_fft_out_tvalid; 
            bram_right_tmp_we <= (others => left_fft_out_tvalid); 
            if right_fft_out_tvalid = '1' then 
                bram_right_tmp_addr <= right_fft_out_tuser(FFT_LENGTH_LOG2 - 1 downto 0); 
            end if;
        end if;
    end if;
end process; 

right_fft_bram: fft_bram
port map(
    clka => aclk,
    ena => bram_right_tmp_en,
    wea => bram_right_tmp_we,
    addra => bram_right_tmp_addr,
    dina => std_logic_vector(right_fft_magnitude),
    clkb => bram_right_fft_clk,
    enb => bram_right_fft_en,
    addrb => bram_right_fft_addr(FFT_LENGTH_LOG2 - 1 downto 0),
    doutb => bram_right_fft_dout
);
end Behavioral;
