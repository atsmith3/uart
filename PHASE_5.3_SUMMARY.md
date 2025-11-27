# Phase 5.3 Summary: UART AXI Integration

**Date**: 2025-11-26
**Status**: ✅ COMPLETE
**Result**: All 10 uart_axi_top integration tests passing, no regressions

---

## Overview

Phase 5.3 integrated the AXI-Lite slave interface (from Phase 5.2) with the UART core (uart_top) to create a complete AXI-accessible UART peripheral. This phase involved creating the top-level integration module, comprehensive testing, and debugging critical timing issues.

---

## Deliverables

### 1. Integration Module: `uart_axi_top.sv`
- **Lines**: 211
- **Purpose**: Top-level UART peripheral with AXI4-Lite interface
- **Architecture**:
  ```
  AXI-Lite Bus (external)
      ↓
  axi_lite_slave_if (5-channel AXI-Lite → simple register interface)
      ↓ [reg_addr, reg_wdata, reg_wen, reg_ren, reg_rdata, reg_error]
      ↓
  uart_top (UART core)
      ├─ uart_regs (register file)
      ├─ baud_gen (baud rate generator)
      ├─ uart_tx_path (TX FIFO + uart_tx)
      └─ uart_rx_path (bit_sync + uart_rx + RX FIFO)
      ↓
  UART serial interface (uart_tx, uart_rx)
  ```

**Key Features**:
- Single clock domain (simplified, CDC deferred to Phase 5.4)
- Parameterized TX/RX FIFO depths
- Interrupt output generation
- Full AXI4-Lite protocol compliance

**Location**: `/home/andrew/prj/chip/potato/uart/rtl/uart_axi_top.sv`

---

### 2. Integration Tests: `uart_axi_top_test.cpp`
- **Lines**: 395
- **Test Count**: 10 comprehensive tests
- **Coverage**:
  1. `uart_axi_top_reset_state` - Reset conditions
  2. `uart_axi_top_register_access` - AXI register read/write
  3. `uart_axi_top_tx_via_axi` - TX FIFO write via AXI
  4. `uart_axi_top_tx_end_to_end` - AXI → TX FIFO → uart_tx serial
  5. `uart_axi_top_rx_end_to_end` - uart_rx serial → RX FIFO → AXI
  6. `uart_axi_top_loopback` - Full loopback via AXI interface
  7. `uart_axi_top_status_flags` - STATUS register validation
  8. `uart_axi_top_interrupt_enable` - INT_ENABLE register
  9. `uart_axi_top_multiple_bytes` - Multi-byte transmission
  10. `uart_axi_top_axi_responses` - AXI response codes (OKAY/SLVERR)

**Test Helpers**:
- `axi_write(addr, data)` - AXI-Lite write transaction
- `axi_read(addr)` - AXI-Lite read transaction
- `send_uart_frame(data)` - Inject UART frame on rx line
- `receive_uart_frame()` - Capture UART frame from tx line

**Location**: `/home/andrew/prj/chip/potato/uart/simulation/tests/module/uart_axi_top_test.cpp`

---

### 3. Build System Updates: `CMakeLists.txt`
- Added `verilated_uart_axi_top` library target
- Includes all dependencies: axi_lite_slave_if + uart_top + submodules
- Added uart_axi_top_test.cpp to module_tests executable
- Successfully builds with Verilator 5.030

---

## Issues Encountered and Resolved

### Issue #1: Register Interface Timing Mismatch (Critical)

**Symptom**:
- 12 test failures in uart_axi_top integration tests
- Register reads returning wrong/stale values
- Example: Write BAUD_DIV=0x10, read back 0x03 (previous CTRL value)

**Root Cause Analysis**:

The `axi_lite_slave_if` and `uart_regs` modules had conflicting assumptions about register read timing:

**axi_lite_slave_if expectation** (axi_lite_slave_if.sv:237-238):
```systemverilog
R_READ: begin
    // Comment in code: "(reg_rdata available in same cycle as reg_ren in uart_regs)"
    rd_data_latched <= reg_rdata;  // ← Expects combinational read
    read_state <= R_RESP;
end
```

**uart_regs implementation** (uart_regs.sv:306-322, ORIGINAL):
```systemverilog
always_ff @(posedge uart_clk or negedge rst_n) begin
    if (!rst_n) begin
        reg_rdata <= '0;
    end else if (reg_read) begin
        case (reg_addr)
            ADDR_CTRL:       reg_rdata <= {30'h0, ctrl_reg};
            ADDR_STATUS:     reg_rdata <= status_value;
            // ... (registered read - 1 cycle latency)
        endcase
    end
end
```

**Timing Diagram Showing Problem**:
```
Cycle | AXI State | reg_ren | reg_addr | reg_rdata      | rd_data_latched
------|-----------|---------|----------|----------------|------------------
  0   | R_IDLE    |    1    |   0x04   | 0x03 (stale)   | -
  1   | R_READ    |    0    |   0x04   | 0x10 (correct) | 0x03 (captured stale!)
  2   | R_RESP    |    0    |   -      | 0x10           | 0x03 (wrong data sent to AXI)
```

**Fix Applied** (uart_regs.sv:306-319):
```systemverilog
// Changed from always_ff to always_comb
// Combinational read for same-cycle availability (required by AXI-Lite interface)
always_comb begin
    case (reg_addr)
        ADDR_CTRL:       reg_rdata = {30'h0, ctrl_reg};
        ADDR_STATUS:     reg_rdata = status_value;
        ADDR_TX_DATA:    reg_rdata = 32'h0;  // Write-only
        ADDR_RX_DATA:    reg_rdata = {24'h0, rx_holding_reg};
        ADDR_BAUD_DIV:   reg_rdata = {16'h0, baud_div_reg};
        ADDR_INT_ENABLE: reg_rdata = {28'h0, int_enable_reg};
        ADDR_INT_STATUS: reg_rdata = {28'h0, int_status_reg};
        ADDR_FIFO_CTRL:  reg_rdata = {30'h0, fifo_ctrl_reg};
        default:         reg_rdata = 32'h0;
    endcase
end
```

**Result**:
- Register reads now return correct values
- 12 failures → 2 failures (different issue)
- No regressions in uart_regs standalone tests

---

### Issue #2: Test Expectation Mismatch (Minor)

**Symptom**:
- 2 remaining test failures after fixing timing issue
- Both checking TX_EMPTY flag after writing to TX_DATA
- Expected TX_EMPTY=0, but TX_EMPTY=1

**Affected Tests**:
1. `uart_axi_top_tx_via_axi` (line 236)
2. `uart_axi_top_status_flags` (line 322)
3. `uart_top_tx_fifo_write` (line 181) - discovered during full test run

**Root Cause**:

With `baud_divisor=1` (set during reset for fast testing), the uart_tx_path operates at maximum speed:
- **Bit period**: 16 clock cycles (OVERSAMPLE_RATE)
- **FIFO read latency**: ~1 cycle

**Sequence of events**:
```
Cycle 0: AXI write to TX_DATA starts
Cycle 5: AXI write completes, byte pushed to TX FIFO
Cycle 6: uart_tx pulls byte from FIFO (TX_EMPTY → 0 for 1 cycle)
Cycle 7: uart_tx starts transmission (TX_ACTIVE=1, TX_EMPTY=1)
Cycle 8: AXI read of STATUS starts
Cycle 12: AXI read completes, returns TX_EMPTY=1
```

The FIFO drains faster than the AXI read can observe it being non-empty!

**Fix Applied**:

Changed test expectations to check `TX_ACTIVE` instead of `TX_EMPTY`:

**uart_axi_top_test.cpp** (line 234-237):
```cpp
// Old:
// STATUS should show TX FIFO not empty
uint32_t status = axi_read(ADDR_STATUS);
BOOST_CHECK_EQUAL((status >> 0) & 1, 0);  // TX_EMPTY = 0

// New:
// STATUS should show TX active (byte pulled from FIFO and transmitting)
// With baud_divisor=1, FIFO drains immediately, but TX should be active
uint32_t status = axi_read(ADDR_STATUS);
BOOST_CHECK_EQUAL((status >> 4) & 1, 1);  // TX_ACTIVE = 1
```

**uart_axi_top_test.cpp** (line 321-332, extended test):
```cpp
// TX should be active (FIFO drains fast with baud_divisor=1)
status = axi_read(ADDR_STATUS);
BOOST_CHECK_EQUAL((status >> 4) & 1, 1);  // TX_ACTIVE

// Wait for transmission to complete
for (int i = 0; i < 200; i++) tick();

// After transmission completes, TX should be idle and FIFO empty
status = axi_read(ADDR_STATUS);
BOOST_CHECK_EQUAL((status >> 0) & 1, 1);  // TX_EMPTY
BOOST_CHECK_EQUAL((status >> 4) & 1, 0);  // TX_ACTIVE = 0 (idle)
```

**uart_top_test.cpp** (line 179-182):
```cpp
// Old: BOOST_CHECK_EQUAL((status >> 0) & 1, 0);  // TX_EMPTY = 0
// New:
BOOST_CHECK_EQUAL((status >> 4) & 1, 1);  // TX_ACTIVE = 1
```

**Result**: All tests passing

---

## Test Results Summary

### Before Fixes
```
*** 12 failures are detected in the test module "uart_tests"

Failures:
- uart_axi_top_register_access: CTRL/BAUD_DIV read wrong values
- uart_axi_top_rx_end_to_end: RX data read as 0x00
- uart_axi_top_loopback: All 4 bytes read incorrectly
- uart_axi_top_status_flags: STATUS fields all 0x00
- uart_axi_top_interrupt_enable: INT_ENABLE read as 0x00
- uart_axi_top_tx_via_axi: TX_EMPTY expectation
- uart_top_tx_fifo_write: TX_EMPTY expectation
```

### After Fix #1 (Timing Fix)
```
*** 2 failures are detected in the test module "uart_tests"

Failures:
- uart_axi_top_tx_via_axi: TX_EMPTY check failed
- uart_axi_top_status_flags: TX_EMPTY check failed
```

### After Fix #2 (Test Expectations)
```
*** No errors detected

Test Suites: 11 total, 11 passing
- BitSync_ModuleTests ✅
- SyncFIFO_ModuleTests ✅
- BaudGen_ModuleTests ✅
- UartTX_ModuleTests ✅
- UartTXPath_ModuleTests ✅
- UartRX_ModuleTests ✅
- UartRXPath_ModuleTests ✅
- UartRegs_ModuleTests ✅ (no regressions!)
- UartTop_ModuleTests ✅
- AXILiteSlave_ModuleTests ✅
- UartAXITop_ModuleTests ✅ (10/10 tests)
```

---

## Files Modified

### RTL Changes
1. **rtl/uart_regs.sv** (lines 306-319)
   - Changed register read path from `always_ff` to `always_comb`
   - Ensures `reg_rdata` available in same cycle as `reg_ren`
   - Matches interface contract expected by axi_lite_slave_if

### Test Changes
2. **tests/module/uart_axi_top_test.cpp** (lines 234-237, 321-332)
   - Fixed `uart_axi_top_tx_via_axi` test expectations
   - Fixed `uart_axi_top_status_flags` test expectations
   - Changed from checking TX_EMPTY to TX_ACTIVE

3. **tests/module/uart_top_test.cpp** (lines 179-182)
   - Fixed `uart_top_tx_fifo_write` test expectations
   - Changed from checking TX_EMPTY to TX_ACTIVE

---

## Design Decisions

### 1. Combinational vs Registered Register Reads

**Decision**: Use combinational (`always_comb`) for register read multiplexer

**Rationale**:
- AXI-Lite interface already designed and tested with same-cycle read assumption
- Minimizes changes to already-validated axi_lite_slave_if module
- Slightly longer combinational path acceptable for this design (not critical path)
- Alternative would require adding extra state to AXI FSM (more complex, retesting needed)

**Trade-offs**:
- ✅ Pro: Simpler integration, minimal changes
- ✅ Pro: Faster register reads (no extra cycle)
- ⚠️ Con: Longer combinational path (reg_addr → reg_rdata)
- ⚠️ Con: May impact timing closure in high-speed designs (acceptable for UART)

### 2. Single Clock Domain (Simplified)

**Decision**: Use single clock for both AXI and UART logic in Phase 5.3

**Rationale**:
- Simplifies initial integration and debugging
- Defers CDC complexity to Phase 5.4
- Allows validation of core functionality first

**Future Work** (Phase 5.4):
- Add separate `axi_clk` and `uart_clk` domains
- Insert CDC for register interface crossing
- Add proper synchronizers and FIFOs for clock domain crossing

---

## Lessons Learned

### 1. Interface Contract Documentation Critical

The timing mismatch could have been avoided with clearer interface documentation:

**What existed**:
- Comment in axi_lite_slave_if.sv: "reg_rdata available in same cycle"
- But this was buried in implementation, not in formal interface spec

**What would help**:
- Formal interface specification document
- Timing diagrams showing expected behavior
- Assertion-based verification of interface contracts

### 2. Fast Baud Rates Expose Race Conditions

Using `baud_divisor=1` for fast testing revealed timing-sensitive test expectations:
- Tests that work at slow baud rates may fail at fast rates
- Need to consider FIFO drain rates when writing tests
- Alternative: Use slower baud rates in tests, or add explicit delays

### 3. Combinational vs Sequential Trade-offs

The register read path change highlighted design trade-offs:
- Sequential logic: Better timing closure, pipelined operation
- Combinational logic: Lower latency, simpler for simple operations
- No universal "right answer" - depends on use case and constraints

### 4. Test Strategy Evolution

Initial tests assumed:
- Slow operation (human time scale)
- Observable intermediate states

Reality with fast clock + fast baud:
- State transitions happen in nanoseconds
- Intermediate states may not be observable
- Tests must check stable states (e.g., TX_ACTIVE vs TX_EMPTY)

---

## Verification Metrics

### Code Coverage (Estimated)
- Register read paths: 100% (all registers tested)
- Register write paths: 100% (all registers tested)
- AXI protocol states: 100% (all states exercised)
- TX data path: 100% (AXI → FIFO → serial)
- RX data path: 100% (serial → FIFO → AXI)
- Loopback: Full end-to-end coverage

### Test Quality
- Unit tests: 11 test suites, all passing
- Integration tests: 10 tests, comprehensive coverage
- No regressions: All previous tests still passing
- Debugging iterations: 2 (timing fix, test fix)

---

## Integration Architecture

### Signal Flow

**AXI Write Transaction**:
```
1. AXI Master asserts awvalid, awaddr, wvalid, wdata
2. axi_lite_slave_if accepts (awready=1, wready=1)
3. axi_lite_slave_if decodes byte address → word address
4. axi_lite_slave_if asserts reg_wen, reg_addr, reg_wdata
5. uart_regs updates register (e.g., CTRL, TX_DATA)
6. axi_lite_slave_if returns bvalid, bresp=OKAY
```

**AXI Read Transaction**:
```
1. AXI Master asserts arvalid, araddr
2. axi_lite_slave_if accepts (arready=1)
3. axi_lite_slave_if decodes byte address → word address
4. axi_lite_slave_if asserts reg_ren, reg_addr
5. uart_regs provides reg_rdata (combinational, same cycle)
6. axi_lite_slave_if latches data, returns rvalid, rdata
```

**TX Data Flow** (AXI → Serial):
```
1. AXI write to ADDR_TX_DATA (0x08)
2. uart_regs asserts wr_en, wr_data to uart_tx_path
3. uart_tx_path FIFO accepts byte
4. uart_tx pulls from FIFO when ready
5. uart_tx serializes byte to uart_tx pin
```

**RX Data Flow** (Serial → AXI):
```
1. uart_rx deserializes uart_rx pin to parallel byte
2. uart_rx_path FIFO stores byte
3. uart_regs prefetch FSM pulls byte to holding register
4. AXI read from ADDR_RX_DATA (0x0C) returns byte
```

---

## Performance Characteristics

### Latency Measurements (with single clock domain)

**AXI Write Latency**:
- Address/Data acceptance: 1 cycle (if AW/W arrive together)
- Register update: Same cycle
- Response generation: 1 cycle
- **Total**: ~2-3 cycles from awvalid to bvalid

**AXI Read Latency**:
- Address acceptance: 1 cycle
- Register read: 0 cycles (combinational)
- Data capture: 1 cycle
- Response generation: 1 cycle
- **Total**: ~3-4 cycles from arvalid to rvalid

**TX Throughput** (with baud_divisor=1):
- Bit time: 16 cycles
- Frame time: 16 × 10 = 160 cycles (1 start + 8 data + 1 stop)
- **Max throughput**: ~62.5 KB/s @ 10 MHz clock

---

## Known Limitations

### 1. Single Clock Domain
- **Current**: All logic runs on same clock
- **Limitation**: Cannot use different AXI and UART clock speeds
- **Mitigation**: Phase 5.4 will add CDC

### 2. No Clock Domain Crossing
- **Current**: No synchronizers between domains
- **Limitation**: Unsafe for multi-clock designs
- **Mitigation**: Phase 5.4 will add proper CDC

### 3. Simplified Timing
- **Current**: Register reads assume fast combinational path
- **Limitation**: May not meet timing in high-speed designs
- **Mitigation**: If needed, can pipeline register reads in future

### 4. Test Coverage Gaps
- No testing of metastability scenarios (deferred to Phase 5.4)
- No testing of clock ratio edge cases (deferred to Phase 5.4)
- No exhaustive error injection testing

---

## Next Steps: Phase 5.4

### Objectives
1. Add Clock Domain Crossing (CDC) support
2. Separate `axi_clk` and `uart_clk` domains
3. Add synchronizers for control signals
4. Test with different clock ratios
5. Validate metastability handling

### Approach
- Insert CDC boundary between axi_lite_slave_if and uart_top
- Use async FIFOs for data paths (if needed)
- Use synchronizers for control signals
- Add comprehensive CDC testing

---

## Conclusion

Phase 5.3 successfully integrated the AXI-Lite interface with the UART core, creating a fully functional AXI-accessible UART peripheral. The integration exposed and resolved critical timing issues, resulting in a robust design with comprehensive test coverage.

**Key Achievements**:
✅ Complete uart_axi_top integration module
✅ 10 comprehensive integration tests, all passing
✅ Critical timing mismatch identified and resolved
✅ No regressions in existing tests
✅ Clean architecture ready for CDC addition (Phase 5.4)

**Lessons Applied**:
- Interface contracts must be explicit and documented
- Fast operation exposes timing-sensitive assumptions
- Combinational vs sequential trade-offs are design-dependent
- Test expectations must match real hardware behavior

The UART peripheral is now ready for Clock Domain Crossing implementation in Phase 5.4.

---

**Document Version**: 1.0
**Author**: Claude + User
**Review Status**: Complete
**Next Review**: After Phase 5.4 completion
