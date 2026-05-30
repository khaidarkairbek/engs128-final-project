----------------------------------------------------------------------------
--  Lab 1: DDS and the Audio Codec
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek
----------------------------------------------------------------------------
--	Description: I2S clock generator
----------------------------------------------------------------------------
-- Add libraries 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.std_logic_unsigned.all;

library UNISIM; 
use UNISIM.vcomponents.all; 

-- Entity definition
entity i2s_clock_gen is
    Port (
        -- System clock in
        sysclk_125MHz_i     : in std_logic; 

        -- Forwarded clocks
        mclk_fwd_o          : out std_logic; 
        bclk_fwd_o          : out std_logic; 
        adc_lrclk_fwd_o     : out std_logic; 
        dac_lrclk_fwd_o     : out std_logic;

        -- Clocks for I2S components
        mclk_o              : out std_logic; 
        bclk_o              : out std_logic; 
        lrclk_o             : out std_logic); 
end i2s_clock_gen; 

----------------------------------------------------------------------------
architecture Behavioral of i2s_clock_gen is
----------------------------------------------------------------------------
-- Internal constants, signals, and components used inside this entity
----------------------------------------------------------------------------

component clock_divider is 
    Generic (CLK_DIV_RATIO : integer := 25_000_000; 
            USE_RISING_EDGE : boolean := true);
    Port (  fast_clk_i : in STD_LOGIC;		  
            slow_clk_o : out STD_LOGIC);
end component;

signal clk_fb                   : std_logic; 
signal mclk, mclk_unbuf         : std_logic; 

signal bclk                     : std_logic; 

signal lrclk                    : std_logic; 
signal lrclk_fwd                : std_logic; 

begin

----------------------------------------------------------------------------
-- Master Clock (MCLK) Generation
----------------------------------------------------------------------------

-- 7 Series FPGAs Clocking Resources User Guide (UG472)
-- F_vco = F_clkin * (CLKFBOUT_MULT_F / DIVCLK_DIVIDE)  Min: 600 Max: 1200
-- F_out = F_clkin * (CLKFBOUT_MULT_F / (DIVCLK_DIVIDE * CLKOUT_DIVIDE))
-- 125 MHz -> 12.288 MHz => * 0.098304
-- F_vco = 125 * 39.125 / 8 = 611.328125 MHz
-- F_out = 125 * 39.125 / (8 * 49.750) = 12.288003 MHz
mclk_gen: MMCME2_ADV
generic map (
    BANDWIDTH               => "OPTIMIZED", -- HIGH, LOW or OPTIMIZED (default)
    CLKFBOUT_MULT_F         => 39.125,      -- 2 to 64 or 2.000 to 64.000 in increments of 0.125
    CLKFBOUT_PHASE          => 0.0,        
    CLKIN1_PERIOD           => 8.0,         -- 8ns = 1 / 125MHz
    CLKOUT0_DIVIDE_F        => 49.750,      -- 1 to 128 or 2.000 to 128.000 in increments of 0.125
    CLKOUT0_DUTY_CYCLE      => 0.5,
    CLKOUT0_PHASE           => 0.0,
    DIVCLK_DIVIDE           => 8            -- 1 to 106
)
port map (
    -- Inputs
    CLKFBIN         =>  clk_fb,
    CLKIN1          =>  sysclk_125MHz_i,
    CLKIN2          =>  '0',
    CLKINSEL        =>  '1',                -- if '1' then clkin1, else clkin2
    DADDR           =>  (others => '0'),    -- unused, Dynamic Reconfiguration Address
    DCLK            =>  '0',                -- unused, Dynamic Reconfiguration Reference Clock
    DEN             =>  '0',                -- unused, Dynamic Reconfiguration Enable Strobe
    DI              =>  (others => '0'),    -- unused, Dynamic Reconfiguration Data Input
    DWE             =>  '0',                -- unused, Dynamic Reconfiguration Write Enable
    PSCLK           =>  '0',                -- unused, Phase-Shift Clock
    PSEN            =>  '0',                -- unused, Phase-Shift Enable
    PSINCDEC        =>  '0',                -- unused, Phase-Shift Increment/Decrement Control
    PWRDWN          =>  '0',                -- unused, Power Down
    RST             =>  '0',                -- unused, Asynchronous Reset Signal
    -- Outputs
    CLKFBOUT        =>  clk_fb, 
    CLKOUT0         =>  mclk_unbuf                 
);

mclk_bufg: BUFG
port map (
    I => mclk_unbuf,
    O => mclk
); 

 

mclk_oddr: ODDR
generic map (
    DDR_CLK_EDGE    => "SAME_EDGE", 
    INIT            => '0',
    SRTYPE          => "SYNC"
)
port map (
    Q   => mclk_fwd_o,      -- 1-bit DDR output
    C   => mclk,            -- 1-bit clock input
    CE  => '1',             -- 1-bit clock enable input
    D1  => '1',             -- 1-bit data input (positive edge)
    D2  => '0',             -- 1-bit data input (negative edge)
    R   => '0',             -- 1-bit reset input
    S   => '0'              -- 1-bit set input
); 

mclk_o <= mclk; 

----------------------------------------------------------------------------
-- Bit Clock (BCLK) Generation
----------------------------------------------------------------------------

bclk_divider: clock_divider
generic map ( CLK_DIV_RATIO => 4 ) -- 12.288 MHz / 4 = 3.072 MHz
port map (
    fast_clk_i => mclk, 
    slow_clk_o => bclk
); 

bclk_oddr: ODDR
generic map (
    DDR_CLK_EDGE    => "SAME_EDGE", 
    INIT            => '0',
    SRTYPE          => "SYNC"
)
port map (
    Q   => bclk_fwd_o,      -- 1-bit DDR output
    C   => bclk,            -- 1-bit clock input
    CE  => '1',             -- 1-bit clock enable input
    D1  => '1',             -- 1-bit data input (positive edge)
    D2  => '0',             -- 1-bit data input (negative edge)
    R   => '0',             -- 1-bit reset input
    S   => '0'              -- 1-bit set input
);

bclk_o <= bclk; 

----------------------------------------------------------------------------
-- Left-Right Clock (LRCLK) Generation
----------------------------------------------------------------------------

lrclk_divider: clock_divider
generic map ( 
    CLK_DIV_RATIO => 64,        -- 3.072 MHz / 64 = 48 kHz
    USE_RISING_EDGE => false    -- change on falling edge
)
port map (
    fast_clk_i => bclk, 
    slow_clk_o => lrclk
); 

adc_lrclk_oddr: ODDR
generic map (
    DDR_CLK_EDGE    => "SAME_EDGE", 
    INIT            => '0',
    SRTYPE          => "SYNC"
)
port map (
    Q   => adc_lrclk_fwd_o,       -- 1-bit DDR output
    C   => lrclk,           -- 1-bit clock input
    CE  => '1',             -- 1-bit clock enable input
    D1  => '1',             -- 1-bit data input (positive edge)
    D2  => '0',             -- 1-bit data input (negative edge)
    R   => '0',             -- 1-bit reset input
    S   => '0'              -- 1-bit set input
);

dac_lrclk_oddr: ODDR
generic map (
    DDR_CLK_EDGE    => "SAME_EDGE", 
    INIT            => '0',
    SRTYPE          => "SYNC"
)
port map (
    Q   => dac_lrclk_fwd_o,       -- 1-bit DDR output
    C   => lrclk,           -- 1-bit clock input
    CE  => '1',             -- 1-bit clock enable input
    D1  => '1',             -- 1-bit data input (positive edge)
    D2  => '0',             -- 1-bit data input (negative edge)
    R   => '0',             -- 1-bit reset input
    S   => '0'              -- 1-bit set input
);

lrclk_o             <= lrclk;


-- end of the architecture definition
end Behavioral;
