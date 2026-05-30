----------------------------------------------------------------------------
--  Lab 2: AXI Stream FIFO and DMA
----------------------------------------------------------------------------
--  ENGS 128 Spring 2026
--	Author: Khaidar Kairbek & Kendall Farnham
----------------------------------------------------------------------------
--	Description: FIFO buffer with AXI stream valid signal
----------------------------------------------------------------------------
-- Library Declarations
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

----------------------------------------------------------------------------
-- Entity definition
entity fifo is
Generic (
    FIFO_DEPTH : integer := 1024;
    DATA_WIDTH : integer := 32);
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
end fifo;

----------------------------------------------------------------------------
-- Architecture Definition 
architecture Behavioral of fifo is
----------------------------------------------------------------------------
-- Define Constants and Signals
----------------------------------------------------------------------------
type mem_type is array (0 to FIFO_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
signal fifo_buf : mem_type := (others => (others => '0'));

signal read_pointer, write_pointer : integer range 0 to FIFO_DEPTH-1 := 0;
signal data_count : integer range 0 to FIFO_DEPTH := 0;
signal empty, full, is_writing, is_reading : std_logic; 
--signal data_out : std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0'); 
----------------------------------------------------------------------------
begin
----------------------------------------------------------------------------
-- Processes and Logic
----------------------------------------------------------------------------

--read_mem_proc: process(clk_i)
--begin 
--    if rising_edge(clk_i) then 
--       if reset_i = '1' then 
--            data_out <= (others => '0');
--       elsif is_reading = '1' then
--            data_out <= fifo_buf(read_pointer); 
--       end if; 
--    end if; 
--end process read_mem_proc;

write_mem_proc: process(clk_i)
begin 
    if rising_edge(clk_i) then 
        if is_writing = '1' then
            fifo_buf(write_pointer) <= wr_data_i;
        end if;
    end if; 
end process;

read_pointer_proc: process(clk_i)
begin 
    if (rising_edge(clk_i)) then 
        if reset_i = '1' then
            read_pointer <= 0;
        elsif is_reading = '1' then 
            if (read_pointer = FIFO_DEPTH - 1) then
                read_pointer <= 0;
            else 
                read_pointer <= read_pointer + 1;  
            end if; 
        end if;
    end if; 
end process read_pointer_proc; 

write_pointer_proc: process(clk_i)
begin 
    if (rising_edge(clk_i)) then
        if reset_i = '1' then
            write_pointer <= 0;
        elsif is_writing = '1' then 
            if (write_pointer = FIFO_DEPTH - 1) then
                write_pointer <= 0;
            else 
                write_pointer <= write_pointer + 1;  
            end if;
        end if;  
    end if; 
end process write_pointer_proc; 

counter_proc: process(clk_i) 
begin 
    if rising_edge(clk_i) then
        if reset_i = '1' then 
            data_count <= 0; 
        elsif is_writing = '1' and is_reading = '0' then
            data_count <= data_count + 1; 
        elsif is_reading = '1' and is_writing = '0' then 
            data_count <= data_count - 1; 
        end if;
    end if;  
end process counter_proc; 

is_writing <= wr_en_i and not full; 
is_reading <= rd_en_i and not empty; 

empty <= '1' when data_count = 0 else '0';
full <= '1' when data_count = FIFO_DEPTH else '0'; 

full_o <= full;
empty_o <= empty;
rd_data_o <= fifo_buf(read_pointer); 


end Behavioral;
