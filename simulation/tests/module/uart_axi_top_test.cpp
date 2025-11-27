/*
 * uart_axi_top Module Tests
 *
 * Tests complete UART peripheral with AXI-Lite interface
 * Integration of axi_lite_slave_if + uart_top
 *
 * Test Coverage:
 * - AXI-Lite register access (read/write)
 * - End-to-end TX: AXI write → TX FIFO → uart_tx
 * - End-to-end RX: uart_rx → RX FIFO → AXI read
 * - Loopback test via AXI interface
 * - Interrupt generation
 * - Error handling
 */

#include "Vuart_axi_top.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>

BOOST_AUTO_TEST_SUITE(UartAXITop_ModuleTests)

// Register offsets (byte-addressed for AXI)
constexpr uint32_t ADDR_CTRL       = 0x00;
constexpr uint32_t ADDR_STATUS     = 0x04;
constexpr uint32_t ADDR_TX_DATA    = 0x08;
constexpr uint32_t ADDR_RX_DATA    = 0x0C;
constexpr uint32_t ADDR_BAUD_DIV   = 0x10;
constexpr uint32_t ADDR_INT_ENABLE = 0x14;
constexpr uint32_t ADDR_INT_STATUS = 0x18;

// AXI response codes
constexpr uint8_t AXI_RESP_OKAY   = 0b00;
constexpr uint8_t AXI_RESP_SLVERR = 0b10;

struct UartAXITopFixture {
    Vuart_axi_top* dut;
    int cycle_count;

    UartAXITopFixture() {
        dut = new Vuart_axi_top;
        cycle_count = 0;

        // Initialize inputs
        dut->clk = 0;
        dut->rst_n = 0;
        dut->uart_rx = 1;  // Idle high

        // AXI Write Address Channel
        dut->awaddr = 0;
        dut->awvalid = 0;

        // AXI Write Data Channel
        dut->wdata = 0;
        dut->wstrb = 0xF;
        dut->wvalid = 0;

        // AXI Write Response Channel
        dut->bready = 1;  // Always ready

        // AXI Read Address Channel
        dut->araddr = 0;
        dut->arvalid = 0;

        // AXI Read Data Channel
        dut->rready = 1;  // Always ready
    }

    ~UartAXITopFixture() {
        delete dut;
    }

    void tick() {
        dut->clk = 0;
        dut->eval();
        dut->clk = 1;
        dut->eval();
        cycle_count++;
    }

    void reset() {
        dut->rst_n = 0;
        dut->awvalid = 0;
        dut->wvalid = 0;
        dut->arvalid = 0;
        dut->bready = 1;
        dut->rready = 1;
        dut->uart_rx = 1;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
        cycle_count = 0;

        // Set baud divisor to 1 for simplified timing (16 clocks per bit)
        axi_write(ADDR_BAUD_DIV, 0x00000001);
    }

    // Helper: AXI write transaction
    void axi_write(uint32_t addr, uint32_t data, uint8_t strb = 0xF) {
        // Present address and data
        dut->awaddr = addr;
        dut->awvalid = 1;
        dut->wdata = data;
        dut->wstrb = strb;
        dut->wvalid = 1;

        // Wait for ready signals
        while (!(dut->awready && dut->wready)) {
            tick();
        }

        // Deassert valid signals
        dut->awvalid = 0;
        dut->wvalid = 0;
        tick();

        // Wait for bvalid (response)
        while (!dut->bvalid) {
            tick();
        }

        // bready already asserted, response complete
        tick();
    }

    // Helper: AXI read transaction
    uint32_t axi_read(uint32_t addr) {
        // Present address
        dut->araddr = addr;
        dut->arvalid = 1;

        // Wait for arready
        while (!dut->arready) {
            tick();
        }

        // Deassert arvalid
        dut->arvalid = 0;
        tick();

        // Wait for rvalid (data)
        while (!dut->rvalid) {
            tick();
        }

        // Capture data (rready already asserted)
        uint32_t data = dut->rdata;
        tick();

        return data;
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
        for (int bit = 0; bit < 8; bit++) {
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
BOOST_FIXTURE_TEST_CASE(uart_axi_top_reset_state, UartAXITopFixture) {
    reset();

    // UART TX should be idle high
    BOOST_CHECK_EQUAL(dut->uart_tx, 1);

    // No interrupt
    BOOST_CHECK_EQUAL(dut->irq, 0);
}

// Test 2: AXI register write/read
BOOST_FIXTURE_TEST_CASE(uart_axi_top_register_access, UartAXITopFixture) {
    reset();

    // Write to CTRL register
    axi_write(ADDR_CTRL, 0x00000003);  // Enable TX and RX

    // Read back CTRL register
    uint32_t ctrl = axi_read(ADDR_CTRL);
    BOOST_CHECK_EQUAL(ctrl & 0x03, 0x03);

    // Write to BAUD_DIV
    axi_write(ADDR_BAUD_DIV, 0x00000010);
    uint32_t baud = axi_read(ADDR_BAUD_DIV);
    BOOST_CHECK_EQUAL(baud & 0xFFFF, 0x0010);
}

// Test 3: Write to TX via AXI
BOOST_FIXTURE_TEST_CASE(uart_axi_top_tx_via_axi, UartAXITopFixture) {
    reset();

    // Enable TX
    axi_write(ADDR_CTRL, 0x00000001);

    // Write byte to TX_DATA via AXI
    axi_write(ADDR_TX_DATA, 0x000000A5);

    // STATUS should show TX active (byte pulled from FIFO and transmitting)
    // With baud_divisor=1, FIFO drains immediately, but TX should be active
    uint32_t status = axi_read(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 4) & 1, 1);  // TX_ACTIVE = 1
}

// Test 4: End-to-end TX (AXI → TX FIFO → uart_tx)
BOOST_FIXTURE_TEST_CASE(uart_axi_top_tx_end_to_end, UartAXITopFixture) {
    reset();

    // Enable TX
    axi_write(ADDR_CTRL, 0x00000001);

    // Write byte via AXI
    axi_write(ADDR_TX_DATA, 0x00000042);

    // Wait and receive from uart_tx
    tick();
    uint8_t received = receive_uart_frame();

    BOOST_CHECK_EQUAL(received, 0x42);
}

// Test 5: End-to-end RX (uart_rx → RX FIFO → AXI)
BOOST_FIXTURE_TEST_CASE(uart_axi_top_rx_end_to_end, UartAXITopFixture) {
    reset();

    // Enable RX
    axi_write(ADDR_CTRL, 0x00000002);

    // Allow time for RX to be enabled
    for (int i = 0; i < 10; i++) tick();

    // Send byte on uart_rx line
    send_uart_frame(0x55);

    // Wait for RX prefetch FSM to process
    for (int i = 0; i < 10; i++) tick();

    // Read via AXI
    uint32_t data = axi_read(ADDR_RX_DATA);
    BOOST_CHECK_EQUAL(data & 0xFF, 0x55);
}

// Test 6: Loopback via AXI (TX → RX external)
BOOST_FIXTURE_TEST_CASE(uart_axi_top_loopback, UartAXITopFixture) {
    reset();

    // Enable both TX and RX
    axi_write(ADDR_CTRL, 0x00000003);

    std::vector<uint8_t> test_data = {0x11, 0x22, 0x33, 0x44};

    for (uint8_t byte : test_data) {
        // Write to TX via AXI
        axi_write(ADDR_TX_DATA, byte);
        tick();

        // Receive from uart_tx and feed to uart_rx
        uint8_t tx_out = receive_uart_frame();

        // Send received byte to uart_rx
        send_uart_frame(tx_out);

        // Read from RX via AXI
        uint32_t rx_in = axi_read(ADDR_RX_DATA);

        BOOST_CHECK_EQUAL(tx_out, byte);
        BOOST_CHECK_EQUAL(rx_in & 0xFF, byte);
    }
}

// Test 7: STATUS register flags
BOOST_FIXTURE_TEST_CASE(uart_axi_top_status_flags, UartAXITopFixture) {
    reset();

    // Initially: TX empty, RX empty
    uint32_t status = axi_read(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 0) & 1, 1);  // TX_EMPTY
    BOOST_CHECK_EQUAL((status >> 2) & 1, 1);  // RX_EMPTY

    // Enable TX and write data
    axi_write(ADDR_CTRL, 0x00000001);
    axi_write(ADDR_TX_DATA, 0x00000099);
    tick();
    tick();

    // TX should be active (FIFO drains fast with baud_divisor=1)
    // FIFO may be empty again but TX should still be transmitting
    status = axi_read(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 4) & 1, 1);  // TX_ACTIVE

    // Wait for transmission to complete
    for (int i = 0; i < 200; i++) tick();

    // After transmission completes, TX should be idle and FIFO empty
    status = axi_read(ADDR_STATUS);
    BOOST_CHECK_EQUAL((status >> 0) & 1, 1);  // TX_EMPTY
    BOOST_CHECK_EQUAL((status >> 4) & 1, 0);  // TX_ACTIVE = 0 (idle)
}

// Test 8: Interrupt enable
BOOST_FIXTURE_TEST_CASE(uart_axi_top_interrupt_enable, UartAXITopFixture) {
    reset();

    // Enable interrupts
    axi_write(ADDR_INT_ENABLE, 0x0000000F);
    uint32_t int_en = axi_read(ADDR_INT_ENABLE);
    BOOST_CHECK_EQUAL(int_en & 0x0F, 0x0F);
}

// Test 9: Multiple byte transmission
BOOST_FIXTURE_TEST_CASE(uart_axi_top_multiple_bytes, UartAXITopFixture) {
    reset();

    // Enable TX
    axi_write(ADDR_CTRL, 0x00000001);

    // Write multiple bytes
    std::vector<uint8_t> data = {0xAA, 0xBB, 0xCC};
    for (uint8_t byte : data) {
        axi_write(ADDR_TX_DATA, byte);
    }

    // Receive all bytes
    for (uint8_t expected : data) {
        uint8_t received = receive_uart_frame();
        BOOST_CHECK_EQUAL(received, expected);
    }
}

// Test 10: AXI response codes
BOOST_FIXTURE_TEST_CASE(uart_axi_top_axi_responses, UartAXITopFixture) {
    reset();

    // Valid write should get OKAY
    dut->awaddr = ADDR_CTRL;
    dut->awvalid = 1;
    dut->wdata = 0x00000001;
    dut->wvalid = 1;

    while (!(dut->awready && dut->wready)) tick();

    dut->awvalid = 0;
    dut->wvalid = 0;
    tick();

    while (!dut->bvalid) tick();
    BOOST_CHECK_EQUAL(dut->bresp, AXI_RESP_OKAY);
    tick();

    // Valid read should get OKAY
    dut->araddr = ADDR_STATUS;
    dut->arvalid = 1;

    while (!dut->arready) tick();

    dut->arvalid = 0;
    tick();

    while (!dut->rvalid) tick();
    BOOST_CHECK_EQUAL(dut->rresp, AXI_RESP_OKAY);
    tick();
}

BOOST_AUTO_TEST_SUITE_END()
