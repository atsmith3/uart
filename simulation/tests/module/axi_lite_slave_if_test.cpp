/*
 * AXI-Lite Slave Interface Module Tests
 *
 * Tests the AXI-Lite slave protocol implementation
 * Converts AXI-Lite 5-channel protocol to simple register interface
 *
 * Test Coverage:
 * - Basic write transaction
 * - Basic read transaction
 * - Back-to-back writes
 * - Back-to-back reads
 * - Interleaved read/write
 * - Invalid address handling
 * - Write response handling
 * - Address decoding
 */

#include "Vaxi_lite_slave_if.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>

BOOST_AUTO_TEST_SUITE(AXILiteSlave_ModuleTests)

// AXI response codes
constexpr uint8_t AXI_RESP_OKAY   = 0b00;
constexpr uint8_t AXI_RESP_SLVERR = 0b10;

struct AXILiteSlaveFixture {
    Vaxi_lite_slave_if* dut;
    int cycle_count;

    AXILiteSlaveFixture() {
        dut = new Vaxi_lite_slave_if;
        cycle_count = 0;

        // Initialize inputs
        dut->clk = 0;
        dut->rst_n = 0;

        // AW channel
        dut->awaddr = 0;
        dut->awvalid = 0;

        // W channel
        dut->wdata = 0;
        dut->wstrb = 0xF;  // All bytes enabled by default
        dut->wvalid = 0;

        // B channel
        dut->bready = 1;  // Always ready by default

        // AR channel
        dut->araddr = 0;
        dut->arvalid = 0;

        // R channel
        dut->rready = 1;  // Always ready by default

        // Register interface
        dut->reg_rdata = 0;
        dut->reg_error = 0;
    }

    ~AXILiteSlaveFixture() {
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
        for (int i = 0; i < 5; i++) tick();
        dut->rst_n = 1;
        tick();
        cycle_count = 0;
    }

    // Helper: Single AXI write transaction
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

    // Helper: Single AXI read transaction
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
};

// Test 1: Reset state
BOOST_FIXTURE_TEST_CASE(axi_slave_reset_state, AXILiteSlaveFixture) {
    reset();

    // All ready signals should be deasserted
    BOOST_CHECK_EQUAL(dut->awready, 0);
    BOOST_CHECK_EQUAL(dut->wready, 0);
    BOOST_CHECK_EQUAL(dut->arready, 0);

    // All valid outputs should be deasserted
    BOOST_CHECK_EQUAL(dut->bvalid, 0);
    BOOST_CHECK_EQUAL(dut->rvalid, 0);

    // Register interface should be idle
    BOOST_CHECK_EQUAL(dut->reg_wen, 0);
    BOOST_CHECK_EQUAL(dut->reg_ren, 0);
}

// Test 2: Single write transaction
BOOST_FIXTURE_TEST_CASE(axi_slave_single_write, AXILiteSlaveFixture) {
    reset();

    // Present write address and data
    dut->awaddr = 0x08;
    dut->awvalid = 1;
    dut->wdata = 0xABCD1234;
    dut->wstrb = 0xF;
    dut->wvalid = 1;
    tick();

    // Check ready signals asserted
    BOOST_CHECK_EQUAL(dut->awready, 1);
    BOOST_CHECK_EQUAL(dut->wready, 1);

    // Check register interface
    BOOST_CHECK_EQUAL(dut->reg_wen, 1);
    BOOST_CHECK_EQUAL(dut->reg_addr, 0x02);  // Byte address 0x08 -> word address 0x02
    BOOST_CHECK_EQUAL(dut->reg_wdata, 0xABCD1234);

    // Deassert valid
    dut->awvalid = 0;
    dut->wvalid = 0;
    tick();

    // Check response
    BOOST_CHECK_EQUAL(dut->bvalid, 1);
    BOOST_CHECK_EQUAL(dut->bresp, AXI_RESP_OKAY);

    // reg_wen should be a pulse
    BOOST_CHECK_EQUAL(dut->reg_wen, 0);
}

// Test 3: Single read transaction
BOOST_FIXTURE_TEST_CASE(axi_slave_single_read, AXILiteSlaveFixture) {
    reset();

    // Set up register response
    dut->reg_rdata = 0x12345678;

    // Present read address
    dut->araddr = 0x04;
    dut->arvalid = 1;
    tick();

    // Check arready asserted
    BOOST_CHECK_EQUAL(dut->arready, 1);

    // Check register interface
    BOOST_CHECK_EQUAL(dut->reg_ren, 1);
    BOOST_CHECK_EQUAL(dut->reg_addr, 0x01);  // Byte address 0x04 -> word address 0x01

    // Deassert arvalid
    dut->arvalid = 0;
    tick();

    // Check read response
    BOOST_CHECK_EQUAL(dut->rvalid, 1);
    BOOST_CHECK_EQUAL(dut->rdata, 0x12345678);
    BOOST_CHECK_EQUAL(dut->rresp, AXI_RESP_OKAY);

    // reg_ren should be a pulse
    BOOST_CHECK_EQUAL(dut->reg_ren, 0);
}

// Test 4: Back-to-back writes
BOOST_FIXTURE_TEST_CASE(axi_slave_back_to_back_writes, AXILiteSlaveFixture) {
    reset();

    axi_write(0x00, 0xAAAAAAAA);
    axi_write(0x04, 0xBBBBBBBB);
    axi_write(0x08, 0xCCCCCCCC);

    // All writes should complete successfully
    BOOST_CHECK_EQUAL(dut->bvalid, 0);  // Last bvalid should be deasserted
}

// Test 5: Back-to-back reads
BOOST_FIXTURE_TEST_CASE(axi_slave_back_to_back_reads, AXILiteSlaveFixture) {
    reset();

    dut->reg_rdata = 0x11111111;
    uint32_t data1 = axi_read(0x00);

    dut->reg_rdata = 0x22222222;
    uint32_t data2 = axi_read(0x04);

    dut->reg_rdata = 0x33333333;
    uint32_t data3 = axi_read(0x08);

    BOOST_CHECK_EQUAL(data1, 0x11111111);
    BOOST_CHECK_EQUAL(data2, 0x22222222);
    BOOST_CHECK_EQUAL(data3, 0x33333333);
}

// Test 6: Interleaved read and write
BOOST_FIXTURE_TEST_CASE(axi_slave_interleaved_access, AXILiteSlaveFixture) {
    reset();

    axi_write(0x00, 0xDEADBEEF);

    dut->reg_rdata = 0xCAFEBABE;
    uint32_t data = axi_read(0x04);

    axi_write(0x08, 0x12345678);

    BOOST_CHECK_EQUAL(data, 0xCAFEBABE);
}

// Test 7: Write with byte enables
BOOST_FIXTURE_TEST_CASE(axi_slave_byte_enables, AXILiteSlaveFixture) {
    reset();

    // Write only lower 2 bytes (wstrb = 0b0011)
    dut->awaddr = 0x10;
    dut->awvalid = 1;
    dut->wdata = 0x12345678;
    dut->wstrb = 0x03;  // Only bytes 0-1 enabled
    dut->wvalid = 1;
    tick();

    // Interface should receive full data (byte masking done by register file)
    BOOST_CHECK_EQUAL(dut->reg_wdata, 0x12345678);

    dut->awvalid = 0;
    dut->wvalid = 0;
    tick();
}

// Test 8: Register error handling
BOOST_FIXTURE_TEST_CASE(axi_slave_register_error, AXILiteSlaveFixture) {
    reset();

    // Set register error
    dut->reg_error = 1;

    // Attempt write
    dut->awaddr = 0x3C;  // Some address
    dut->awvalid = 1;
    dut->wdata = 0xFFFFFFFF;
    dut->wvalid = 1;
    tick();

    dut->awvalid = 0;
    dut->wvalid = 0;
    tick();

    // Should get SLVERR response
    BOOST_CHECK_EQUAL(dut->bvalid, 1);
    BOOST_CHECK_EQUAL(dut->bresp, AXI_RESP_SLVERR);
}

// Test 9: Address decoding (word-aligned)
BOOST_FIXTURE_TEST_CASE(axi_slave_address_decoding, AXILiteSlaveFixture) {
    reset();

    // Test various byte addresses map to correct word addresses
    std::vector<std::pair<uint32_t, uint8_t>> test_cases = {
        {0x00, 0x00},  // Byte 0x00 -> Word 0x00
        {0x04, 0x01},  // Byte 0x04 -> Word 0x01
        {0x08, 0x02},  // Byte 0x08 -> Word 0x02
        {0x0C, 0x03},  // Byte 0x0C -> Word 0x03
        {0x10, 0x04},  // Byte 0x10 -> Word 0x04
        {0x1C, 0x07},  // Byte 0x1C -> Word 0x07
    };

    for (const auto& test : test_cases) {
        dut->awaddr = test.first;
        dut->awvalid = 1;
        dut->wdata = 0x00000000;
        dut->wvalid = 1;
        tick();

        BOOST_CHECK_EQUAL(dut->reg_addr, test.second);

        dut->awvalid = 0;
        dut->wvalid = 0;
        tick();

        // Wait for bvalid to clear
        while (dut->bvalid) tick();
    }
}

// Test 10: Concurrent address and data (best case timing)
BOOST_FIXTURE_TEST_CASE(axi_slave_concurrent_channels, AXILiteSlaveFixture) {
    reset();

    // Both address and data arrive in same cycle
    dut->awaddr = 0x14;
    dut->awvalid = 1;
    dut->wdata = 0x99999999;
    dut->wvalid = 1;
    tick();

    // Should accept both in same cycle
    BOOST_CHECK_EQUAL(dut->awready, 1);
    BOOST_CHECK_EQUAL(dut->wready, 1);
    BOOST_CHECK_EQUAL(dut->reg_wen, 1);
}

BOOST_AUTO_TEST_SUITE_END()
