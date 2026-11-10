-- Author : Reiyan RM
-- Created on : 10/11/2026
-- Project: UART TX 

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity axi_uart is

    generic (CLK_PER_BIT : integer := 16);

    port (
        clk : in std_logic;
        rst_n : in std_logic ; -- active low reset

        --slave axis 
        s_axis_tdata : in std_logic_vector (7 downto 0);
        s_axis_tvalid : in std_logic ;
        s_axis_tready : out std_logic;

        --master axis
        m_axis_tdata : out std_logic_vector (7 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in std_logic;

        --transfer data
        tx : out std_logic;
        tx_busy : out std_logic;
        tx_enable : in std_logic;

        --receive data
        rx : in std_logic;
        rx_busy : out std_logic;
        rx_enable : in std_logic
    );

end entity;


architecture rtl of axi_uart is

    type state_t is (S_IDLE,S_TX_START,S_TX,S_TX_STOP,S_RX_START,S_RX,S_RX_STOP);

    signal data_tx_reg,data_rx_reg : std_logic_vector (7 downto 0) := (others => '0'); 
    signal clk_counter,next_clk_counter : integer range 0 to CLK_PER_BIT-1 := CLK_PER_BIT-1;
    signal rx_index,tx_index,next_rx_index,next_tx_index : integer range 0 to 7 := 0;
    signal state , next_state : state_t := S_IDLE;
    signal internal_tready : std_logic := '0'; 
    signal internal_tvalid : std_logic := '0';
    signal bit_done : std_logic;
    signal rx_meta,rx_sync : std_logic := '1';   -- 2 flop synchronizer for rx

begin

bit_done <= '1' when clk_counter = 0 else '0';

internal_tready <= '1' when (state = S_IDLE and tx_enable = '1') else '0';
s_axis_tready <= internal_tready;

m_axis_tvalid <= internal_tvalid;
m_axis_tdata <= data_rx_reg;

next_state <= S_TX_START when (state = S_IDLE and internal_tready = '1' and s_axis_tvalid = '1') else
              S_RX_START when (state = S_IDLE and rx_enable = '1' and rx_sync = '0') else
              S_TX       when (state = S_TX_START and bit_done = '1') else
              S_TX_STOP  when (state = S_TX and bit_done = '1' and tx_index = 7) else
              S_IDLE     when (state = S_TX_STOP and bit_done = '1') else
              S_RX       when (state = S_RX_START and bit_done = '1' and rx_sync = '0') else
              S_IDLE     when (state = S_RX_START and bit_done = '1') else   -- false start bit
              S_RX_STOP  when (state = S_RX and bit_done = '1' and rx_index = 7) else
              S_IDLE     when (state = S_RX_STOP and bit_done = '1') else
              state ;

next_rx_index <= rx_index - 1 when (state = S_RX and bit_done = '1' and rx_index /= 0) else
                 7            when (state /= S_RX) else
                 rx_index ;

next_tx_index <= tx_index - 1 when (state = S_TX and bit_done = '1' and tx_index /= 0) else
                 7            when (state /= S_TX) else
                 tx_index ;

next_clk_counter <= CLK_PER_BIT/2 - 1 when (state = S_IDLE and next_state = S_RX_START) else  -- land mid start bit
                    CLK_PER_BIT - 1   when (state = S_IDLE or bit_done = '1') else
                    clk_counter - 1 ;



    process(clk)
        begin
            if rising_edge (clk) then
                if rst_n = '0' then

                    data_rx_reg <= (others => '0');
                    data_tx_reg <= (others => '0');
                    tx <= '1';
                    tx_busy <= '0';
                    rx_busy <= '0';
                    internal_tvalid <= '0';
                    rx_meta <= '1';
                    rx_sync <= '1';
                    state <= S_IDLE;
                    clk_counter <= CLK_PER_BIT-1;
                    rx_index <= 0;
                    tx_index <= 0;

                else 
                    rx_meta <= rx;
                    rx_sync <= rx_meta;

                    state <= next_state ;
                    rx_index <= next_rx_index;
                    tx_index <= next_tx_index;
                    clk_counter <= next_clk_counter;

                    if internal_tvalid = '1' and m_axis_tready = '1' then
                        internal_tvalid <= '0';
                    end if ;

                    case state is

                        when S_IDLE => 
                            tx <= '1';
                            tx_busy <= '0';
                            rx_busy <= '0';
                            if next_state = S_TX_START then
                                data_tx_reg <= s_axis_tdata;
                            end if ;

                        when S_TX_START =>
                            tx <= '0';
                            tx_busy <= '1';
                            rx_busy <= '0';

                        when S_TX =>
                            tx <= data_tx_reg(7-tx_index);
                            tx_busy <= '1';
                            rx_busy <= '0';

                        when S_TX_STOP =>
                            tx <= '1';
                            tx_busy <= '1';
                            rx_busy <= '0';

                        when S_RX_START =>
                            tx_busy <= '0';
                            rx_busy <= '1';

                        when S_RX =>
                            tx_busy <= '0';
                            rx_busy <= '1';
                            if bit_done = '1' then
                                data_rx_reg(7-rx_index) <= rx_sync;
                            end if ;

                        when S_RX_STOP =>
                            tx_busy <= '0';
                            rx_busy <= '1';
                            if bit_done = '1' and rx_sync = '1' then   -- valid stop bit
                                internal_tvalid <= '1';
                            end if ;

                    end case;
                end if ;
            end if;
    end process;
end architecture;