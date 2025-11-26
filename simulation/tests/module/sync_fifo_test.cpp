/*
 * sync_fifo Module Tests
 *
 * Tests synchronous FIFO with registered output
 *
 * Test Coverage:
 * - Empty/full flag behavior
 * - Write-then-read sequences
 * - Simultaneous read/write
 * - Wraparound (pointer rollover)
 * - Level counting
 * - Corner cases (fill/drain completely)
 * - Registered output latency (1 cycle)
 *
 * CRITICAL: FIFO has registered output, so read data
 * appears 1 cycle AFTER rd_en assertion
 */

#include "Vsync_fifo.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>
#include <vector>
#include <random>

BOOST_AUTO_TEST_SUITE(SyncFIFO_ModuleTests)

struct SyncFIFOFixture {
    Vsync_fifo* dut;
    static const int DEPTH = 8;  // Default FIFO depth

    SyncFIFOFixture() {
        dut = new Vsync_fifo;
        dut->clk = 0;
        dut->rst_n = 0;
        dut->wr_en = 0;
        dut->wr_data = 0;
        dut->rd_en = 0;
    }

    ~SyncFIFOFixture() {
        delete dut;
    }

    void tick() {
        dut->clk = 0;
        dut->eval();
        dut->clk = 1;
        dut->eval();
    }

    void reset() {
        dut->rst_n = 0;
        dut->wr_en = 0;
        dut->rd_en = 0;
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
    }

    // Helper: Write single byte to FIFO
    void write(uint8_t data) {
        dut->wr_data = data;
        dut->wr_en = 1;
        tick();
        dut->wr_en = 0;
    }

    // Helper: Read single byte from FIFO (returns data after latency)
    uint8_t read() {
        dut->rd_en = 1;
        tick();
        dut->rd_en = 0;
        // Data valid this cycle (registered output)
        return dut->rd_data;
    }
};

// Define static member (required for ODR-usage)
const int SyncFIFOFixture::DEPTH;

// Test 1: Reset state
BOOST_FIXTURE_TEST_CASE(fifo_reset_state, SyncFIFOFixture) {
    reset();

    // After reset: empty, not full, level=0
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
    BOOST_CHECK_EQUAL(dut->wr_full, 0);
    BOOST_CHECK_EQUAL(dut->level, 0);
}

// Test 2: Single write and read
BOOST_FIXTURE_TEST_CASE(fifo_single_write_read, SyncFIFOFixture) {
    reset();

    // Write one byte
    write(0xAB);

    // FIFO should not be empty anymore
    BOOST_CHECK_EQUAL(dut->rd_empty, 0);
    BOOST_CHECK_EQUAL(dut->level, 1);

    // Read the byte (registered output, data valid same cycle as read)
    uint8_t data = read();
    BOOST_CHECK_EQUAL(data, 0xAB);

    // FIFO should be empty again
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
    BOOST_CHECK_EQUAL(dut->level, 0);
}

// Test 3: Multiple writes then reads
BOOST_FIXTURE_TEST_CASE(fifo_multiple_writes_then_reads, SyncFIFOFixture) {
    reset();

    std::vector<uint8_t> test_data = {0x11, 0x22, 0x33, 0x44};

    // Write all data
    for (auto byte : test_data) {
        BOOST_CHECK_EQUAL(dut->wr_full, 0); // Should not be full
        write(byte);
    }

    BOOST_CHECK_EQUAL(dut->level, test_data.size());

    // Read all data back
    for (auto expected : test_data) {
        BOOST_CHECK_EQUAL(dut->rd_empty, 0); // Should not be empty
        uint8_t received = read();
        BOOST_CHECK_EQUAL(received, expected);
    }

    // FIFO should be empty
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
    BOOST_CHECK_EQUAL(dut->level, 0);
}

// Test 4: Fill FIFO completely
BOOST_FIXTURE_TEST_CASE(fifo_fill_completely, SyncFIFOFixture) {
    reset();

    // Write DEPTH bytes
    for (int i = 0; i < DEPTH; i++) {
        BOOST_CHECK_EQUAL(dut->wr_full, 0); // Should not be full yet
        write(i);
    }

    // Now FIFO should be full
    BOOST_CHECK_EQUAL(dut->wr_full, 1);
    BOOST_CHECK_EQUAL(dut->level, DEPTH);

    // Try to write one more (should be ignored)
    write(0xFF);
    BOOST_CHECK_EQUAL(dut->level, DEPTH); // Level unchanged
}

// Test 5: Empty FIFO completely and check flags
BOOST_FIXTURE_TEST_CASE(fifo_drain_completely, SyncFIFOFixture) {
    reset();

    // Fill with 4 bytes
    for (int i = 0; i < 4; i++) {
        write(i);
    }

    BOOST_CHECK_EQUAL(dut->level, 4);

    // Drain all 4 bytes
    for (int i = 0; i < 4; i++) {
        BOOST_CHECK_EQUAL(dut->rd_empty, 0); // Not empty yet
        read();
    }

    // Now should be empty
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
    BOOST_CHECK_EQUAL(dut->level, 0);
}

// Test 6: Simultaneous read and write (FIFO not full, not empty)
BOOST_FIXTURE_TEST_CASE(fifo_simultaneous_read_write, SyncFIFOFixture) {
    reset();

    // Pre-fill with 2 bytes
    write(0xAA);
    write(0xBB);

    BOOST_CHECK_EQUAL(dut->level, 2);

    // Simultaneous read and write
    dut->wr_data = 0xCC;
    dut->wr_en = 1;
    dut->rd_en = 1;
    tick();
    dut->wr_en = 0;
    dut->rd_en = 0;

    // Level should stay same (one in, one out)
    BOOST_CHECK_EQUAL(dut->level, 2);

    // Read data should be 0xAA (first one written)
    BOOST_CHECK_EQUAL(dut->rd_data, 0xAA);
}

// Test 7: Wraparound (test pointer rollover)
BOOST_FIXTURE_TEST_CASE(fifo_wraparound, SyncFIFOFixture) {
    reset();

    // Pattern: fill, drain, fill again to cause wraparound

    // First fill: write 0-7
    for (int i = 0; i < DEPTH; i++) {
        write(i);
    }

    // Drain 4 bytes
    for (int i = 0; i < 4; i++) {
        uint8_t data = read();
        BOOST_CHECK_EQUAL(data, i);
    }

    BOOST_CHECK_EQUAL(dut->level, 4); // 4 remaining

    // Write 4 more bytes (this causes wraparound)
    for (int i = 0; i < 4; i++) {
        write(0x80 + i);
    }

    BOOST_CHECK_EQUAL(dut->level, 8); // Full again

    // Read remaining original bytes (4-7)
    for (int i = 4; i < 8; i++) {
        uint8_t data = read();
        BOOST_CHECK_EQUAL(data, i);
    }

    // Read wrapped bytes (0x80-0x83)
    for (int i = 0; i < 4; i++) {
        uint8_t data = read();
        BOOST_CHECK_EQUAL(data, 0x80 + i);
    }

    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
}

// Test 8: Level counter accuracy
BOOST_FIXTURE_TEST_CASE(fifo_level_counter, SyncFIFOFixture) {
    reset();

    // Write incrementally and check level
    for (int i = 1; i <= DEPTH; i++) {
        write(i);
        BOOST_CHECK_EQUAL(dut->level, i);
    }

    // Read incrementally and check level
    for (int i = DEPTH; i > 0; i--) {
        read();
        BOOST_CHECK_EQUAL(dut->level, i - 1);
    }
}

// Test 9: Data integrity with full sequence
BOOST_FIXTURE_TEST_CASE(fifo_data_integrity, SyncFIFOFixture) {
    reset();

    std::vector<uint8_t> test_data = {0x00, 0x55, 0xAA, 0xFF, 0x12, 0x34, 0x56, 0x78};

    // Write test pattern
    for (auto byte : test_data) {
        write(byte);
    }

    // Read back and verify
    for (auto expected : test_data) {
        uint8_t received = read();
        BOOST_CHECK_EQUAL(received, expected);
    }
}

// Test 10: Registered output timing - verify 1-cycle latency
BOOST_FIXTURE_TEST_CASE(fifo_registered_output_timing, SyncFIFOFixture) {
    reset();

    // Write data
    write(0xAB);

    // Before asserting rd_en, rd_data is undefined/old
    uint8_t data_before = dut->rd_data;

    // Assert rd_en for 1 cycle
    dut->rd_en = 1;
    tick();
    dut->rd_en = 0;

    // Data should be valid THIS cycle (registered output)
    BOOST_CHECK_EQUAL(dut->rd_data, 0xAB);

    // This confirms the registered output behavior:
    // - rd_en pulse at cycle N
    // - rd_data valid at cycle N+1 (same cycle, registered output)
}

// Test 11: Prevent write when full
BOOST_FIXTURE_TEST_CASE(fifo_write_when_full, SyncFIFOFixture) {
    reset();

    // Fill completely
    for (int i = 0; i < DEPTH; i++) {
        write(i);
    }

    BOOST_CHECK_EQUAL(dut->wr_full, 1);

    // Try to write when full
    write(0xFF);

    // Level should still be DEPTH (write ignored)
    BOOST_CHECK_EQUAL(dut->level, DEPTH);

    // Read first byte, should still be 0 (not 0xFF)
    uint8_t data = read();
    BOOST_CHECK_EQUAL(data, 0);
}

// Test 12: Prevent read when empty
BOOST_FIXTURE_TEST_CASE(fifo_read_when_empty, SyncFIFOFixture) {
    reset();

    // FIFO is empty
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);

    // Try to read when empty
    dut->rd_en = 1;
    tick();
    dut->rd_en = 0;

    // rd_data is undefined (no assertion, just verify no crash)
    // Level should still be 0
    BOOST_CHECK_EQUAL(dut->level, 0);
    BOOST_CHECK_EQUAL(dut->rd_empty, 1);
}

// Test 13: Random operations (stress test)
BOOST_FIXTURE_TEST_CASE(fifo_random_operations, SyncFIFOFixture) {
    reset();

    std::mt19937 rng(42); // Fixed seed for reproducibility
    std::uniform_int_distribution<int> op_dist(0, 1); // 0=read, 1=write
    std::uniform_int_distribution<int> data_dist(0, 255);

    std::vector<uint8_t> written_data;
    size_t read_index = 0;

    // Perform 100 random operations
    for (int i = 0; i < 100; i++) {
        int op = op_dist(rng);

        if (op == 1 && dut->wr_full == 0) {
            // Write operation
            uint8_t data = data_dist(rng);
            write(data);
            written_data.push_back(data);
        } else if (op == 0 && dut->rd_empty == 0) {
            // Read operation
            uint8_t received = read();
            BOOST_REQUIRE(read_index < written_data.size());
            BOOST_CHECK_EQUAL(received, written_data[read_index]);
            read_index++;
        }

        // Sanity check: level should match our tracking
        BOOST_CHECK_EQUAL(dut->level, written_data.size() - read_index);
    }
}

BOOST_AUTO_TEST_SUITE_END()
