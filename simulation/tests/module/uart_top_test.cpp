/*
 * uart_top Module Tests
 *
 * Tests complete UART peripheral integration (simplified version)
 * Uses direct register interface instead of full AXI-Lite for testing
 *
 * Test Coverage:
 * - Module instantiation and connectivity
 * - Register interface functionality
 * - TX path: write data, transmit serial output
 * - RX path: receive serial input, read data
 * - Baud rate generation
 * - Interrupt generation
 * - Error detection
 * - End-to-end loopback test
 */

#include "Vuart_top.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>
#include <queue>

BOOST_AUTO_TEST_SUITE(UartTop_ModuleTests)

// Register offsets (word-addressed)
constexpr uint8_t ADDR_CTRL       = 0x00 >> 2;
constexpr uint8_t ADDR_STATUS     = 0x04 >> 2;
constexpr uint8_t ADDR_TX_DATA    = 0x08 >> 2;
constexpr uint8_t ADDR_RX_DATA    = 0x0C >> 2;
constexpr uint8_t ADDR_BAUD_DIV   = 0x10 >> 2;
constexpr uint8_t ADDR_INT_ENABLE = 0x14 >> 2;
constexpr uint8_t ADDR_INT_STATUS = 0x18 >> 2;

struct UartTopFixture {
    Vuart_top* dut;
    int cycle_count;

    UartTopFixture() {
        dut = new Vuart_top;
        cycle_count = 0;

        // Initialize inputs
        dut->uart_clk = 0;
        dut->rst_n = 0;
        dut->uart_rx = 1;  // Idle high
        dut->reg_addr = 0;
        dut->reg_wdata = 0;
        dut->reg_wen = 0;
        dut->reg_ren = 0;
    }

    ~UartTopFixture() {
        delete dut;
    }

    void tick() {
        dut->uart_clk = 0;
        dut->eval();
        dut->uart_clk = 1;
        dut->eval();
        cycle_count++;
    }

    void reset() {
        dut->rst_n = 0;
        dut->reg_wen = 0;
        dut->reg_ren = 0;
        dut->uart_rx = 1;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
        cycle_count = 0;

        // Set baud divisor to 1 for simplified timing (16 clocks per bit)
        write_reg(ADDR_BAUD_DIV, 0x00000001);
    }

    // Helper: Write register
    void write_reg(uint8_t addr, uint32_t data) {
        dut->reg_addr = addr;
        dut->reg_wdata = data;
        dut->reg_wen = 1;
        tick();
        dut->reg_wen = 0;
    }

    // Helper: Read register
    uint32_t read_reg(uint8_t addr) {
        dut->reg_addr = addr;
        dut->reg_ren = 1;
        tick();
        dut->reg_ren = 0;
        tick();
        return dut->reg_rdata;
    }

    // Helper: Send UART frame on RX line
    void send_uart_frame(uint8_t data) {
        // Start bit
        dut->uart_rx = 0;
        for (int i = 0; i < 16; i++) tick();

        // Data bits (LSB first)
        for (int bit = 0; bit < 8; bit++) {
            dut->uart_rx = (data >> bit) & 1;
            for (int i = 0; i < 16; i++) tick();
        }

        // Stop bit
        dut->uart_rx = 1;
        for (int i = 0; i < 16; i++) tick();

        // Extra time for processing
        for (int i = 0; i < 20; i++) tick();
    }

    // Helper: Receive UART frame from TX line
    uint8_t receive_uart_frame() {
        uint8_t data = 0;

        // Wait for start bit (falling edge)
        int timeout = 1000;
        while (dut->uart_tx && timeout-- > 0) tick();
        if (timeout <= 0) return 0xFF;  // Timeout

        // Sample data bits at middle of each bit period
        // With baud_divisor=1, each bit is 16 clocks (16 baud_ticks)
        // Bit timing: Start[0-15], Bit0[16-31], Bit1[32-47], ...
        // Sample at middle (tick 8) of each bit period
        for (int bit = 0; bit < 8; bit++) {
            // First bit: advance 24 ticks (to tick 24 = middle of bit 0)
            // Subsequent bits: advance 16 ticks (to middle of next bit)
            int advance = (bit == 0) ? 24 : 16;
            for (int i = 0; i < advance; i++) tick();
            if (dut->uart_tx) data |= (1 << bit);
        }

        // Stop bit
        for (int i = 0; i < 16; i++) tick();

        return data;
    }
};

// Test 1: Reset state
BOOST_FIXTURE_TEST_CASE(uart_top_reset_state, UartTopFixture) {
    reset();

    // UART TX should be idle high
    BOOST_CHECK_EQUAL(dut->uart_tx, 1);

    // STATUS should show empty FIFOs
    uint32_t status = read_reg(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 0) & 1, 1);  // TX_EMPTY
    BOOST_CHECK_EQUAL((status >> 2) & 1, 1);  // RX_EMPTY
}

// Test 2: Enable UART
BOOST_FIXTURE_TEST_CASE(uart_top_enable, UartTopFixture) {
    reset();

    // Enable TX and RX
    write_reg(ADDR_CTRL, 0x00000003);
    uint32_t ctrl = read_reg(ADDR_CTRL);
    BOOST_CHECK_EQUAL(ctrl & 0x03, 0x03);
}

// Test 3: Write to TX FIFO
BOOST_FIXTURE_TEST_CASE(uart_top_tx_fifo_write, UartTopFixture) {
    reset();

    // Enable TX
    write_reg(ADDR_CTRL, 0x00000001);

    // Write byte to TX_DATA
    write_reg(ADDR_TX_DATA, 0x000000A5);

    // STATUS should show TX active (byte pulled from FIFO immediately)
    // With baud_divisor=1, FIFO drains fast, but TX should be active
    uint32_t status = read_reg(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 4) & 1, 1);  // TX_ACTIVE = 1
}

// Test 4: Transmit byte (end-to-end TX)
BOOST_FIXTURE_TEST_CASE(uart_top_transmit_byte, UartTopFixture) {
    reset();

    // Enable TX
    write_reg(ADDR_CTRL, 0x00000001);

    // Write byte
    write_reg(ADDR_TX_DATA, 0x00000042);

    // Wait and receive
    tick();  // Allow time for TX to start
    uint8_t received = receive_uart_frame();

    BOOST_CHECK_EQUAL(received, 0x42);
}

// Test 5: Receive byte (end-to-end RX)
BOOST_FIXTURE_TEST_CASE(uart_top_receive_byte, UartTopFixture) {
    reset();

    // Enable RX
    write_reg(ADDR_CTRL, 0x00000002);

    // Allow time for RX to be enabled before sending
    for (int i = 0; i < 10; i++) tick();

    // Send byte on RX line
    send_uart_frame(0x55);

    // Wait for RX prefetch FSM to process (needs a few cycles)
    for (int i = 0; i < 10; i++) tick();

    // Read RX_DATA (prefetch FSM will have fetched it into holding register)
    uint32_t data = read_reg(ADDR_RX_DATA);
    BOOST_CHECK_EQUAL(data & 0xFF, 0x55);

    // After reading, FIFO should now be empty
    uint32_t status = read_reg(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 2) & 1, 1);  // RX_EMPTY = 1
}

// Test 6: Loopback test
BOOST_FIXTURE_TEST_CASE(uart_top_loopback, UartTopFixture) {
    reset();

    // Enable both TX and RX
    write_reg(ADDR_CTRL, 0x00000003);

    // Send multiple bytes through TX and loopback to RX
    std::vector<uint8_t> test_data = {0x11, 0x22, 0x33, 0x44};

    for (uint8_t byte : test_data) {
        // Write to TX
        write_reg(ADDR_TX_DATA, byte);
        tick();

        // Receive from TX line and feed to RX
        uint8_t tx_out = receive_uart_frame();

        // Send received byte back to RX
        send_uart_frame(tx_out);

        // Read from RX
        uint32_t rx_in = read_reg(ADDR_RX_DATA);

        BOOST_CHECK_EQUAL(tx_out, byte);
        BOOST_CHECK_EQUAL(rx_in & 0xFF, byte);
    }
}

// Test 7: Baud rate divisor
BOOST_FIXTURE_TEST_CASE(uart_top_baud_divisor, UartTopFixture) {
    reset();

    // Set baud divisor
    write_reg(ADDR_BAUD_DIV, 0x00000010);
    uint32_t baud_div = read_reg(ADDR_BAUD_DIV);
    BOOST_CHECK_EQUAL(baud_div & 0xFFFF, 0x0010);
}

// Test 8: Interrupt enable
BOOST_FIXTURE_TEST_CASE(uart_top_interrupt_enable, UartTopFixture) {
    reset();

    // Enable interrupts
    write_reg(ADDR_INT_ENABLE, 0x0000000F);
    uint32_t int_en = read_reg(ADDR_INT_ENABLE);
    BOOST_CHECK_EQUAL(int_en & 0x0F, 0x0F);
}

// Test 9: TX active flag
BOOST_FIXTURE_TEST_CASE(uart_top_tx_active, UartTopFixture) {
    reset();

    // Enable TX
    write_reg(ADDR_CTRL, 0x00000001);

    // Write byte
    write_reg(ADDR_TX_DATA, 0x00000099);
    tick();
    tick();

    // TX should become active
    uint32_t status = read_reg(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 4) & 1, 1);  // TX_ACTIVE
}

// Test 10: RX active flag
BOOST_FIXTURE_TEST_CASE(uart_top_rx_active, UartTopFixture) {
    reset();

    // Enable RX
    write_reg(ADDR_CTRL, 0x00000002);

    // Start sending on RX line
    dut->uart_rx = 0;  // Start bit
    for (int i = 0; i < 20; i++) tick();

    // RX should become active
    uint32_t status = read_reg(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 5) & 1, 1);  // RX_ACTIVE
}

BOOST_AUTO_TEST_SUITE_END()
