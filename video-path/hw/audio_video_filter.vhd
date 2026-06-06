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
		
		FFT_LENGTH : integer := 64; 
		FFT_LENGTH_LOG2 : integer := 6;
		MAG_WIDTH : integer := 32; 
	    
		DATA_WIDTH	: integer	:= 24; 
		BIN_HEIGHT : integer := 12
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
		
		red_effect_en : in std_logic;
		green_effect_en : in std_logic; 
		blue_effect_en : in std_logic; 
		left_right_sw : in std_logic; 
		 
		timing_hsync : in std_logic;
		timing_vsync : in std_logic; 
		timing_fsync : in std_logic; 
		
        left_fft_din : in std_logic_vector(MAG_WIDTH - 1 downto 0); 
        left_fft_bin : out std_logic_vector(FFT_LENGTH_LOG2 - 1 downto 0); 
        left_fft_read : out std_logic; 
        
        right_fft_din : in std_logic_vector(MAG_WIDTH - 1 downto 0); 
        right_fft_bin : out std_logic_vector(FFT_LENGTH_LOG2 - 1 downto 0); 
        right_fft_read : out std_logic
	);
end audio_video_filter;


----------------------------------------------------------------------------
-- Architecture Definition 
architecture Behavioral of audio_video_filter is

signal left_mag, right_mag : unsigned(MAG_WIDTH - 1 downto 0) := (others => '0'); 
signal red_gain, green_gain, blue_gain : unsigned(15 downto 0) := (others => '0'); 

signal row_count : unsigned(15 downto 0) := (others => '0');
signal bin_count : unsigned(FFT_LENGTH_LOG2 - 1 downto 0) := (others => '0'); 

signal prev_fsync, prev_hsync : std_logic := '0'; 
attribute ASYNC_REG : string;
signal fsync_meta, fsync_reg, hsync_meta, hsync_reg : std_logic := '0';

attribute ASYNC_REG of fsync_meta : signal is "TRUE";
attribute ASYNC_REG of fsync_reg : signal is "TRUE";
attribute ASYNC_REG of hsync_meta : signal is "TRUE";
attribute ASYNC_REG of hsync_reg : signal is "TRUE";

signal left_fft_read_addr, right_fft_read_addr : std_logic_vector(FFT_LENGTH_LOG2 - 1 downto 0) := (others => '0'); 
signal left_fft_read_en, right_fft_read_en : std_logic := '0'; 
signal fft_read_pending : std_logic := '0';


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

function mag_to_gain(mag : unsigned(MAG_WIDTH - 1 downto 0)) return unsigned is
    variable clamped : unsigned(11 downto 0); 
begin 
    if mag(MAG_WIDTH - 1 downto 22) = 0 then 
        clamped := mag(21 downto 10);
    else 
        clamped := x"FFF"; 
    end if;
    
    return x"1000" - resize(clamped(11 downto 1), 16);
end function; 


----------------------------------------------------------------------------
begin

cdc_sync_proc: process (s00_axis_aclk) 
begin 
    if rising_edge(s00_axis_aclk) then 
        fsync_meta <= timing_fsync; 
        fsync_reg <= fsync_meta; 
        hsync_meta <= timing_hsync; 
        hsync_reg <= hsync_meta;
    end if; 
end process; 

----------------------------------------------------------------------------
-- Row counter: reset on fsync rising edge, increment on hsync rising edge
----------------------------------------------------------------------------
row_counter_proc: process(s00_axis_aclk)
begin
    if rising_edge(s00_axis_aclk) then
        if s00_axis_aresetn = '0' or m00_axis_aresetn = '0' then
            row_count        <= (others => '0');
            bin_count        <= (others => '0');
            prev_fsync       <= '0';
            prev_hsync       <= '0';
            left_fft_read_en  <= '0';
            right_fft_read_en <= '0';
            fft_read_pending  <= '0';

        else
            -- Default: deassert read enables and pending
            left_fft_read_en  <= '0';
            right_fft_read_en <= '0';
            fft_read_pending  <= '0';

            -- fsync rising edge: reset row counter
            if prev_fsync = '0' and fsync_reg = '1' then
                row_count <= (others => '0');
                bin_count <= (others => '0');

            -- hsync rising edge: increment row, issue FFT read if on bin boundary
            elsif prev_hsync = '0' and hsync_reg = '1' then
                if row_count = BIN_HEIGHT - 1 then 
                    row_count <= (others => '0'); 
                    bin_count <= bin_count + 1; 
                    
                    left_fft_read_en <= '1'; 
                    right_fft_read_en <= '1'; 
                    fft_read_pending <= '1'; 
                else 
                    row_count <= row_count + 1; 
                end if;
            end if;

            -- One cycle after read enable: latch returned BRAM data into gain regs
            if fft_read_pending = '1' then
                left_mag  <= unsigned(left_fft_din);
                right_mag <= unsigned(right_fft_din);
            end if;

            prev_fsync <= fsync_reg;
            prev_hsync <= hsync_reg;
        end if;
    end if;
end process row_counter_proc;

-- Drive FFT address and read enable outputs combinatorially
left_fft_bin  <= std_logic_vector(bin_count);
right_fft_bin <= std_logic_vector(bin_count);
left_fft_read  <= left_fft_read_en;
right_fft_read <= right_fft_read_en;

gain_assign_proc: process(s00_axis_aclk)
begin 
    if rising_edge(s00_axis_aclk) then 
        if s00_axis_aresetn = '0' or m00_axis_aresetn = '0' then 
            red_gain <= x"1000";
            green_gain <= x"1000";
            blue_gain <= x"1000"; 
        else 
            if red_effect_en = '0' then 
                red_gain <= x"1000";
            elsif left_right_sw = '0' then 
                red_gain <= mag_to_gain(left_mag);
            else 
                red_gain <= mag_to_gain(right_mag); 
            end if; 
            
            if green_effect_en = '0' then 
                green_gain <= x"1000";
            elsif left_right_sw = '0' then 
                green_gain <= mag_to_gain(left_mag);
            else 
                green_gain <= mag_to_gain(right_mag); 
            end if;
            
            if blue_effect_en = '0' then 
                blue_gain <= x"1000";
            elsif left_right_sw = '0' then 
                blue_gain <= mag_to_gain(left_mag);
            else 
                blue_gain <= mag_to_gain(right_mag); 
            end if;
        end if;
    end if; 
end process gain_assign_proc; 

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
            
            r_prod <= resize(r_in_reg * red_gain, 24); 
            g_prod <= resize(g_in_reg * green_gain, 24); 
            b_prod <= resize(b_in_reg * blue_gain, 24); 
            
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
