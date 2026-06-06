----------------------------------------------------------------------------
--  Final Project: Audio Controlled Video Processing
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--  Author: Khaidar Kairbek & Brandon Carido
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_fft_wrapper is
end tb_fft_wrapper;

architecture sim of tb_fft_wrapper is

    constant C_AXI_STREAM_DATA_WIDTH : integer := 32;
    constant AUDIO_DATA_WIDTH        : integer := 24;
    constant FFT_LENGTH              : integer := 64;
    constant FFT_LENGTH_LOG2         : integer := 6;
    constant MAG_WIDTH               : integer := 32;

    constant CLK_PERIOD : time := 10 ns;

    constant FREQ_BIN  : integer := 5;
    constant SINE_AMP  : real   := 0.5;
    constant DC_OFFSET : real   := 0.0;

    ------------------------------------------------------------------------
    -- DUT signals
    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';
    
    signal audio_signal : std_logic_vector(AUDIO_DATA_WIDTH -1 downto 0) := (others => '0');
    signal s_axis_tdata  : std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tlast  : std_logic := '0';
    signal s_axis_tkeep  : std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0) := (others => '1');

    signal m_axis_tdata  : std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';
    signal m_axis_tlast  : std_logic;
    signal m_axis_tkeep  : std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0);

    -- BRAM read-back signals (left channel)
    signal bram_left_en   : std_logic := '0';
    signal bram_left_addr : std_logic_vector(FFT_LENGTH_LOG2-1 downto 0) := (others => '0');
    signal bram_left_dout : std_logic_vector(MAG_WIDTH-1 downto 0);

    ------------------------------------------------------------------------
    function real_to_audio(x : real) return std_logic_vector is
        variable scaled : real;
        variable as_int : integer;
    begin
        scaled := x * real(2**(AUDIO_DATA_WIDTH-1) - 1);
        if scaled > real(2**(AUDIO_DATA_WIDTH-1) - 1) then
            scaled := real(2**(AUDIO_DATA_WIDTH-1) - 1);
        elsif scaled < -real(2**(AUDIO_DATA_WIDTH-1)) then
            scaled := -real(2**(AUDIO_DATA_WIDTH-1));
        end if;
        as_int := integer(scaled);
        return std_logic_vector(to_signed(as_int, AUDIO_DATA_WIDTH));
    end function;

begin

    aclk <= not aclk after CLK_PERIOD / 2;

    ------------------------------------------------------------------------
    -- DUT
    DUT : entity work.fft_wrapper
        generic map (
            C_AXI_STREAM_DATA_WIDTH => C_AXI_STREAM_DATA_WIDTH,
            AUDIO_DATA_WIDTH        => AUDIO_DATA_WIDTH,
            FFT_LENGTH              => FFT_LENGTH,
            FFT_LENGTH_LOG2         => FFT_LENGTH_LOG2,
            MAG_WIDTH               => MAG_WIDTH
        )
        port map (
            aclk          => aclk,
            aresetn       => aresetn,

            s_axis_tdata  => s_axis_tdata,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tlast  => s_axis_tlast,
            s_axis_tkeep  => s_axis_tkeep,

            m_axis_tdata  => m_axis_tdata,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tlast  => m_axis_tlast,
            m_axis_tkeep  => m_axis_tkeep,

            bram_left_fft_clk  => aclk,
            bram_left_fft_en   => bram_left_en,
            bram_left_fft_addr => bram_left_addr,
            bram_left_fft_dout => bram_left_dout,

            bram_right_fft_clk  => aclk,
            bram_right_fft_en   => '0',
            bram_right_fft_addr => (others => '0'),
            bram_right_fft_dout => open
        );

    ------------------------------------------------------------------------
    -- Stimulus
    stim_proc : process
        variable sample_idx  : integer := 0;
        variable sample_real : real;
        variable phase       : real;
    begin
        aresetn       <= '0';
        s_axis_tvalid <= '0';
        wait for 20 * CLK_PERIOD;
        aresetn <= '1';
        wait for 10 * CLK_PERIOD;

        report "Starting stimulus" severity note;

        for n in 0 to 4*FFT_LENGTH - 1 loop
            phase       := 2.0 * MATH_PI * real(FREQ_BIN) * real(sample_idx) / real(FFT_LENGTH);
            sample_real := DC_OFFSET + SINE_AMP * sin(phase);

            -- MSB = '0' -> left channel
            audio_signal <= real_to_audio(sample_real);
            s_axis_tdata  <= "00000000" & real_to_audio(sample_real);
            s_axis_tvalid <= '1';
            s_axis_tlast  <= '0';

            wait until rising_edge(aclk);
            while s_axis_tready = '0' loop
                wait until rising_edge(aclk);
            end loop;

            sample_idx := sample_idx + 1;
        end loop;

        s_axis_tvalid <= '0';
        report "Stimulus complete" severity note;

        -- Let in-flight data drain, then read back all FFT bins
        wait for 500 * CLK_PERIOD;

        report "Reading back left FFT BRAM magnitudes:" severity note;
        for bin in 0 to FFT_LENGTH - 1 loop
            bram_left_addr <= std_logic_vector(to_unsigned(bin, FFT_LENGTH_LOG2));
            bram_left_en   <= '1';
            wait until rising_edge(aclk);  -- address registered
            wait until rising_edge(aclk);  -- BRAM output latency (1 cycle for simple-dual-port)
            report "  bin " & integer'image(bin) &
                   " magnitude = " & integer'image(to_integer(unsigned(bram_left_dout)))
                severity note;
        end loop;
        bram_left_en <= '0';

        wait for 100 * CLK_PERIOD;
        assert false report "End of simulation" severity failure;
    end process;

    ------------------------------------------------------------------------
    -- Passthrough check
    passthrough_check_proc : process(aclk)
    begin
        if rising_edge(aclk) then
            if m_axis_tvalid = '1' then

                assert m_axis_tdata = s_axis_tdata
                    report "Passthrough mismatch: input " &
                           integer'image(to_integer(signed(s_axis_tdata))) &
                           " output " &
                           integer'image(to_integer(signed(m_axis_tdata)))
                    severity warning;
            end if;
        end if;
    end process;

end sim;