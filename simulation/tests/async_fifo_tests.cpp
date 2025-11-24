/*
 * Async FIFO Tests
 *
 * Tests the async_fifo module with different clock frequencies
 * to verify Gray code synchronization and CDC handling
 */

#include "Vasync_fifo.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <iostream>
#include <queue>
#include <vector>

BOOST_AUTO_TEST_SUITE(Async_FIFO_Tests)

// Test fixture for async FIFO tests
struct AsyncFIFOFixture {
    Vasync_fifo* dut;
    uint64_t time_counter;

    AsyncFIFOFixture() : time_counter(0) {
        dut = new Vasync_fifo;
        dut->wr_clk = 0;
        dut->wr_rst_n = 0;
        dut->rd_clk = 0;
        dut->rd_rst_n = 0;
        dut->wr_en = 0;
        dut->rd_en = 0;
        dut->wr_data = 0;
    }

    ~AsyncFIFOFixture() {
        delete dut;
    }

    void tick_wr() {
        dut->wr_clk = 0;
        dut->eval();
        time_counter++;
        dut->wr_clk = 1;
        dut->eval();
        time_counter++;
    }

    void tick_rd() {
        dut->rd_clk = 0;
        dut->eval();
        time_counter++;
        dut->rd_clk = 1;
        dut->eval();
        time_counter++;
    }

    void tick_both() {
        dut->wr_clk = 0;
        dut->rd_clk = 0;
        dut->eval();
        time_counter++;
        dut->wr_clk = 1;
        dut->rd_clk = 1;
        dut->eval();
        time_counter++;
    }

    void reset() {
        dut->wr_rst_n = 0;
        dut->rd_rst_n = 0;
        for (int i = 0; i < 5; i++) {
            tick_both();
        }
        dut->wr_rst_n = 1;
        dut->rd_rst_n = 1;
        for (int i = 0; i < 5; i++) {
            tick_both();
        }
    }

    void write_byte(uint8_t data) {
        dut->wr_data = data;
        dut->wr_en = 1;
        tick_wr();
        dut->wr_en = 0;
    }

    uint8_t read_byte() {
        // With registered read, rd_data is valid 1 cycle after rd_en
        // Assert rd_en, tick, then sample data
        dut->rd_en = 1;
        tick_rd();
        dut->rd_en = 0;
        uint8_t data = dut->rd_data;
        return data;
    }
};

// Test 1: Basic write and read with same clock
BOOST_FIXTURE_TEST_CASE(async_fifo_basic_same_clock, AsyncFIFOFixture) {
    reset();

    // Initially empty
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
    BOOST_CHECK_EQUAL(dut->wr_full, 0);

    // Write one byte
    write_byte(0xAB);

    // Allow synchronization (2-3 clocks)
    for (int i = 0; i < 5; i++) {
        tick_both();
    }

    // Should not be empty now
    BOOST_CHECK_EQUAL(dut->rd_empty, 0);

    // Read the byte
    uint8_t data = read_byte();
    std::cout << "Read data: 0x" << std::hex << (int)data << std::dec << std::endl;
    BOOST_CHECK_EQUAL(data, 0xAB);

    // Allow synchronization
    for (int i = 0; i < 5; i++) {
        tick_both();
    }

    // Should be empty again
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
}

// Test 2: Multiple writes and reads
BOOST_FIXTURE_TEST_CASE(async_fifo_multiple_bytes, AsyncFIFOFixture) {
    reset();

    std::vector<uint8_t> test_data = {0x00, 0x55, 0xAA, 0xFF, 0x12, 0x34, 0x56, 0x78};

    // Write all bytes
    for (uint8_t byte : test_data) {
        BOOST_CHECK_EQUAL(dut->wr_full, 0);
        write_byte(byte);
    }

    // Allow synchronization
    for (int i = 0; i < 10; i++) {
        tick_both();
    }

    // Should be full now
    BOOST_CHECK_EQUAL(dut->wr_full, 1);
    BOOST_CHECK_EQUAL(dut->rd_empty, 0);

    // Read all bytes back
    for (uint8_t expected : test_data) {
        BOOST_CHECK_EQUAL(dut->rd_empty, 0);
        uint8_t received = read_byte();
        std::cout << "Expected: 0x" << std::hex << (int)expected
                  << ", Received: 0x" << (int)received << std::dec << std::endl;
        BOOST_CHECK_EQUAL(received, expected);
    }

    // Allow synchronization
    for (int i = 0; i < 10; i++) {
        tick_both();
    }

    // Should be empty again
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
}

// Test 3: Write faster than read (different clock rates)
BOOST_FIXTURE_TEST_CASE(async_fifo_fast_write_slow_read, AsyncFIFOFixture) {
    reset();

    std::queue<uint8_t> expected_data;

    // Write multiple bytes quickly
    for (int i = 0; i < 5; i++) {
        uint8_t data = 0x10 + i;
        expected_data.push(data);
        write_byte(data);
        // Tick write clock a few more times
        tick_wr();
        tick_wr();
    }

    // Allow synchronization
    for (int i = 0; i < 10; i++) {
        tick_both();
    }

    // Read slowly
    while (!expected_data.empty()) {
        BOOST_CHECK_EQUAL(dut->rd_empty, 0);

        uint8_t expected = expected_data.front();
        expected_data.pop();

        uint8_t received = read_byte();
        std::cout << "Expected: 0x" << std::hex << (int)expected
                  << ", Received: 0x" << (int)received << std::dec << std::endl;
        BOOST_CHECK_EQUAL(received, expected);

        // Tick read clock slowly
        for (int j = 0; j < 5; j++) {
            tick_rd();
        }
    }
}

// Test 4: Read faster than write (different clock rates)
BOOST_FIXTURE_TEST_CASE(async_fifo_slow_write_fast_read, AsyncFIFOFixture) {
    reset();

    // Write one byte slowly
    write_byte(0xAB);
    for (int i = 0; i < 10; i++) {
        tick_wr();
    }

    // Allow synchronization with multiple read clocks
    for (int i = 0; i < 20; i++) {
        tick_rd();
    }

    // Read should see the data
    BOOST_CHECK_EQUAL(dut->rd_empty, 0);
    uint8_t data = read_byte();
    BOOST_CHECK_EQUAL(data, 0xAB);

    // More read clocks
    for (int i = 0; i < 10; i++) {
        tick_rd();
    }

    // Should be empty
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
}

// Test 5: Interleaved write and read
BOOST_FIXTURE_TEST_CASE(async_fifo_interleaved, AsyncFIFOFixture) {
    reset();

    // Write, sync, read, sync pattern
    for (int i = 0; i < 4; i++) {
        uint8_t data = 0x20 + i;

        write_byte(data);

        // Synchronization delay
        for (int j = 0; j < 5; j++) {
            tick_both();
        }

        BOOST_CHECK_EQUAL(dut->rd_empty, 0);
        uint8_t received = read_byte();
        std::cout << "Iteration " << i << " - Expected: 0x" << std::hex << (int)data
                  << ", Received: 0x" << (int)received << std::dec << std::endl;
        BOOST_CHECK_EQUAL(received, data);

        // More synchronization
        for (int j = 0; j < 5; j++) {
            tick_both();
        }

        BOOST_CHECK_EQUAL(dut->rd_empty, 1);
    }
}

// Test 6: Fill and drain pattern
BOOST_FIXTURE_TEST_CASE(async_fifo_fill_drain, AsyncFIFOFixture) {
    reset();

    // Fill the FIFO completely (depth = 8)
    for (int i = 0; i < 8; i++) {
        write_byte(0xA0 + i);
    }

    // Allow sync
    for (int i = 0; i < 10; i++) {
        tick_both();
    }

    // Check full
    BOOST_CHECK_EQUAL(dut->wr_full, 1);

    // Drain completely
    for (int i = 0; i < 8; i++) {
        uint8_t received = read_byte();
        std::cout << "Drain[" << i << "]: 0x" << std::hex << (int)received << std::dec << std::endl;
        BOOST_CHECK_EQUAL(received, 0xA0 + i);
    }

    // Allow sync
    for (int i = 0; i < 10; i++) {
        tick_both();
    }

    // Check empty
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
}

// Test 7: Write with read clock much faster
BOOST_FIXTURE_TEST_CASE(async_fifo_clock_ratio_test, AsyncFIFOFixture) {
    reset();

    std::vector<uint8_t> test_data = {0x11, 0x22, 0x33, 0x44};

    for (uint8_t byte : test_data) {
        write_byte(byte);

        // Tick read clock 8 times for every write (simulating 8:1 ratio)
        for (int i = 0; i < 8; i++) {
            tick_rd();
        }
    }

    // Give more time for sync
    for (int i = 0; i < 10; i++) {
        tick_both();
    }

    // Read all back
    for (uint8_t expected : test_data) {
        BOOST_CHECK_EQUAL(dut->rd_empty, 0);
        uint8_t received = read_byte();
        std::cout << "Expected: 0x" << std::hex << (int)expected
                  << ", Received: 0x" << (int)received << std::dec << std::endl;
        BOOST_CHECK_EQUAL(received, expected);
    }
}

// Test 8: Pointer wraparound test
BOOST_FIXTURE_TEST_CASE(async_fifo_wraparound, AsyncFIFOFixture) {
    reset();

    // Do multiple fill/drain cycles to test pointer wraparound
    for (int cycle = 0; cycle < 3; cycle++) {
        std::cout << "Wraparound cycle " << cycle << std::endl;

        // Fill
        for (int i = 0; i < 8; i++) {
            write_byte(0x50 + i);
        }

        // Sync
        for (int i = 0; i < 10; i++) {
            tick_both();
        }

        // Drain
        for (int i = 0; i < 8; i++) {
            uint8_t received = read_byte();
            BOOST_CHECK_EQUAL(received, 0x50 + i);
        }

        // Sync
        for (int i = 0; i < 10; i++) {
            tick_both();
        }

        BOOST_CHECK_EQUAL(dut->rd_empty, 1);
    }
}

BOOST_AUTO_TEST_SUITE_END()
