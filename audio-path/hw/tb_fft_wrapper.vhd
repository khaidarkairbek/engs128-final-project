----------------------------------------------------------------------------
--  Final Project: Audio Controlled Video Processing
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--  Author: Khaidar Kairbek & Brandon Carido
----------------------------------------------------------------------------
--  Description: Testbench for fft_wrapper. Generates a sine wave at a
--               known frequency, feeds it into the wrapper, and prints
--               the magnitude output for inspection. Expect a peak in the
--               magnitude spectrum at the bin corresponding to the sine
--               frequency.
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use std.textio.all;
use ieee.std_logic_textio.all;

----------------------------------------------------------------------------
entity tb_fft_wrapper is
end tb_fft_wrapper;

----------------------------------------------------------------------------
architecture sim of tb_fft_wrapper is

    -- Match wrapper generics
    constant C_AXI_STREAM_DATA_WIDTH : integer := 32;
    constant AUDIO_DATA_WIDTH : integer := 24;
    constant FFT_LENGTH       : integer := 1024;
    constant FFT_LENGTH_LOG2  : integer := 10;

    -- Clock: 100 MHz nominal for simulation (just needs to be fast enough
    -- to push 1024+ samples through in reasonable sim time; the FFT IP
    -- doesn't care about absolute clock rate).
    constant CLK_PERIOD : time := 10 ns;

    -- Test signal parameters
    --   Bin = FREQ_BIN tells us which output bin should peak.
    --   With FFT_LENGTH=1024 and Fs=any, a sine that completes FREQ_BIN
    --   full cycles over the frame appears in bin FREQ_BIN.
    constant FREQ_BIN     : integer := 50;       -- expect peak here
    constant SINE_AMP     : real    := 0.5;       -- 0.5 of full scale
    constant DC_OFFSET    : real    := 0.0;       -- no DC

    ------------------------------------------------------------------------
    -- DUT signals
    signal aclk    : std_logic := '0';
    signal aresetn : std_logic := '0';

    signal s_axis_tdata  : std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tlast  : std_logic := '0';
    signal s_axis_tkeep  : std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0) := (others => '1');

    signal m_axis_tdata  : std_logic_vector(C_AXI_STREAM_DATA_WIDTH-1 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic := '1';   -- downstream always ready
    signal m_axis_tlast  : std_logic;
    signal m_axis_tkeep  : std_logic_vector((C_AXI_STREAM_DATA_WIDTH/8)-1 downto 0);

    signal fft_tdata  : std_logic_vector(AUDIO_DATA_WIDTH * 2-1 downto 0);
    signal fft_tvalid : std_logic;
    signal fft_tlast  : std_logic;
    signal fft_index  : std_logic_vector(FFT_LENGTH_LOG2-1 downto 0);
    signal fft_real, fft_imag   : std_logic_vector(AUDIO_DATA_WIDTH - 1 downto 0); 
    

    ------------------------------------------------------------------------
    -- Convert real-valued sample to signed 24-bit fixed-point
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

    ------------------------------------------------------------------------
    -- Clock
    aclk <= not aclk after CLK_PERIOD / 2;
    
    fft_real <= fft_tdata(AUDIO_DATA_WIDTH - 1 downto 0); 
    fft_imag <= fft_tdata(AUDIO_DATA_WIDTH*2 - 1 downto AUDIO_DATA_WIDTH); 

    ------------------------------------------------------------------------
    -- DUT instantiation
    DUT : entity work.fft_wrapper
        generic map (
            C_AXI_STREAM_DATA_WIDTH => C_AXI_STREAM_DATA_WIDTH,
            AUDIO_DATA_WIDTH => AUDIO_DATA_WIDTH,
            FFT_LENGTH       => FFT_LENGTH,
            FFT_LENGTH_LOG2  => FFT_LENGTH_LOG2
        )
        port map (
            aclk           => aclk,
            aresetn        => aresetn,

            s_axis_tdata   => s_axis_tdata,
            s_axis_tvalid  => s_axis_tvalid,
            s_axis_tready  => s_axis_tready,
            s_axis_tlast   => s_axis_tlast,
            s_axis_tkeep   => s_axis_tkeep,

            m_axis_tdata   => m_axis_tdata,
            m_axis_tvalid  => m_axis_tvalid,
            m_axis_tready  => m_axis_tready,
            m_axis_tlast   => m_axis_tlast,
            m_axis_tkeep   => m_axis_tkeep,

            left_fft_tdata  => fft_tdata,
            left_fft_tvalid => fft_tvalid,
            left_fft_tlast  => fft_tlast,
            left_fft_index  => fft_index,
            
            right_fft_tdata  => open,
            right_fft_tvalid => open,
            right_fft_tlast  => open,
            right_fft_index  => open
        );

    ------------------------------------------------------------------------
    -- Stimulus: drive a sine wave into the input
    stim_proc : process
        variable sample_idx  : integer := 0;
        variable sample_real : real;
        variable phase       : real;
    begin
        -- Hold reset
        aresetn <= '0';
        s_axis_tvalid <= '0';
        wait for 20 * CLK_PERIOD;
        aresetn <= '1';
        wait for 10 * CLK_PERIOD;

        -- Send several frames worth of samples so we get multiple FFT outputs
        report "Starting stimulus" severity note;

        for n in 0 to 4*FFT_LENGTH - 1 loop
            -- Compute the next sample
            phase := 2.0 * MATH_PI * real(FREQ_BIN) * real(sample_idx) / real(FFT_LENGTH);
            sample_real := DC_OFFSET + SINE_AMP * sin(phase);
            s_axis_tdata <= "00000000" & real_to_audio(sample_real);

            s_axis_tvalid <= '1';
            s_axis_tlast  <= '0';   -- not used by the wrapper for framing

            -- Wait for handshake
            wait until rising_edge(aclk);
            while s_axis_tready = '0' loop
                wait until rising_edge(aclk);
            end loop;

            sample_idx := sample_idx + 1;
        end loop;

        s_axis_tvalid <= '0';
        report "Stimulus complete" severity note;

        -- Let any in-flight data drain
        wait for 1000 * CLK_PERIOD;

        assert false report "End of simulation" severity failure;
    end process;

    ------------------------------------------------------------------------
    -- Passthrough sanity check: ensure output audio matches input audio
    -- (one cycle delay is fine, but the data should be identical).
    passthrough_check_proc : process(aclk)
    begin
        if rising_edge(aclk) then
            if m_axis_tvalid = '1' then
                -- For a wrapper that does pure passthrough on the audio path,
                -- m_axis_tdata should equal s_axis_tdata in the same cycle
                -- (since you wired them combinationally). If you ever add a
                -- register, change this to a pipelined comparison.
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