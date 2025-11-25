# Hardware Development Guidelines

## Table of Contents
1. [Five Golden Rules](#five-golden-rules)
2. [Interface Definition Requirements](#interface-definition-requirements)
3. [Hierarchical Decomposition](#hierarchical-decomposition)
4. [RTL Directory Organization](#rtl-directory-organization)
5. [Development Phase Gates](#development-phase-gates)
6. [Change Control Process](#change-control-process)
7. [Test Strategy](#test-strategy)
8. [Hardware Code Review Checklist](#hardware-code-review-checklist)
9. [Test Infrastructure Validation](#test-infrastructure-validation)
10. [Recovery Procedures](#recovery-procedures)
11. [Project-Specific Learnings: UART](#project-specific-learnings-uart)
12. [Templates and Examples](#templates-and-examples)

---

## Five Golden Rules

### 1. Test Before You Integrate
**Never integrate untested components.** Every module must pass standalone tests before integration.

**Bad:**
- Write async_fifo.sv
- Drop it into uart_tx_path.sv
- Debug failures in system tests

**Good:**
- Write async_fifo.sv
- Create async_fifo_test.cpp
- Verify all corner cases (empty, full, wrap, power-of-2 depths)
- Tag commit as `async_fifo_validated`
- Then integrate into uart_tx_path.sv

### 2. One Change at a Time
**Make orthogonal changes in separate commits.** If you can't describe the change in one sentence, it's too big.

**Bad:**
- Change FIFO type from sync to async
- Add prefetch logic
- Fix baud rate divider
- All in one commit

**Good:**
- Commit 1: "Add async_fifo module with tests"
- Commit 2: "Replace sync_fifo with async_fifo in TX path"
- Commit 3: "Add TX prefetch holding register"
- Commit 4: "Fix TX baud rate divider"

### 3. Know Your Baseline
**Always maintain a known-good state.** Tag commits that represent working milestones.

**Required tags:**
```bash
git tag -a module_tests_pass -m "All module tests passing"
git tag -a integration_pass -m "Integration tests passing"
git tag -a system_validated -m "Full system validation complete"
```

### 4. Validate Don't Patch
**Tests exist to validate requirements, not to pass.** If a test fails, understand why before changing it.

**Bad workflow:**
- Module test expects start bit = 0
- Test sees start bit = 1
- Change test to expect start bit = 1
- Move on

**Good workflow:**
- Module test expects start bit = 0 (requirement)
- Test sees start bit = 1 (failure)
- Debug: Why is TX outputting wrong start bit?
- Fix: TX state machine has wrong initial state
- Verify: Test now passes with start bit = 0

### 5. Test Your Tests
**Test infrastructure must be validated before DUT testing.** Clock generators, monitors, and drivers are code too.

**Required validation:**
- Clock duty cycle verification
- Clock frequency measurement
- Bus protocol compliance checking
- Timing relationship validation

---

## Interface Definition Requirements

### Overview
**All module interfaces must be fully documented before implementation begins.** Interface specifications prevent integration issues and enable parallel development.

### Required Interface Documentation

Every module interface must include:

1. **Signal Table**
   - Signal name
   - Direction (input/output)
   - Width
   - Clock domain
   - Protocol (AXI, ready/valid, etc.)
   - Reset value

2. **Timing Diagrams**
   - Clock relationships
   - Setup/hold times
   - Valid data windows
   - Handshake sequences

3. **Protocol Description**
   - Handshake rules (who waits for whom)
   - Valid/ready semantics
   - Stall behavior
   - Error conditions

4. **Clock Domain Crossing (CDC) Documentation**
   - Which signals cross domains
   - Synchronization method
   - Latency characteristics
   - Metastability handling

### Interface Definition Template

```systemverilog
/*
 * Module: <module_name>
 *
 * Interface Specification:
 *
 * Clock Domains:
 *   - clk_a: <frequency, source, description>
 *   - clk_b: <frequency, source, description>
 *
 * Signal Groups:
 *
 * 1. <Group Name> (Clock: <domain>)
 *    Signal         | Dir | Width | Protocol      | Reset Value | Description
 *    ---------------|-----|-------|---------------|-------------|------------------
 *    group_valid    | I   | 1     | ready/valid   | 0           | Data valid strobe
 *    group_ready    | O   | 1     | ready/valid   | 0           | Ready to accept
 *    group_data     | I   | 8     | ready/valid   | X           | Data payload
 *
 * Timing Requirements:
 *   - group_valid → group_ready: Max 5 cycles
 *   - group_data must be stable when group_valid=1
 *
 * CDC Boundaries:
 *   - <signal_name>: crosses from clk_a to clk_b via <sync method>
 *
 * Protocol Rules:
 *   - Ready/valid handshake: Transaction occurs when both valid & ready
 *   - Once valid asserted, must stay high until ready
 *   - Ready may be asserted before valid
 */
```

### Interface Examples

**Good Interface Documentation:**
```systemverilog
/*
 * TX FIFO Write Interface (axi_clk domain)
 *
 * Protocol: Standard FIFO write with full flag
 *
 * Signal        | Dir | Width | Reset | Description
 * --------------|-----|-------|-------|--------------------------------------
 * fifo_wr_en    | I   | 1     | 0     | Write enable (pulse)
 * fifo_wr_data  | I   | 8     | X     | Write data (valid when wr_en=1)
 * fifo_wr_full  | O   | 1     | 0     | FIFO full flag (no writes allowed)
 *
 * Timing:
 *   - Check fifo_wr_full BEFORE asserting fifo_wr_en
 *   - Data written on rising edge when wr_en=1 and wr_full=0
 *   - fifo_wr_full updated 1 cycle after write
 *
 * Error Conditions:
 *   - Writing when wr_full=1 → Data lost, no error flag
 */
```

**Bad Interface Documentation:**
```systemverilog
// TX FIFO interface
input logic fifo_wr_en;
input logic [7:0] fifo_wr_data;
output logic fifo_wr_full;
// Use these to write data
```

### Interface Review Checklist

Before implementation starts, verify:
- [ ] All signals documented with direction, width, reset value
- [ ] Clock domain specified for every signal
- [ ] CDC boundaries identified and synchronization method specified
- [ ] Timing diagrams provided for complex handshakes
- [ ] Protocol rules explicitly stated
- [ ] Error conditions documented
- [ ] Latency characteristics specified
- [ ] Interface reviewed by at least one other engineer

---

## Hierarchical Decomposition

### When to Create Submodules

**Guideline: A module should do ONE thing.** If you can describe functionality with "and" or "or", decompose it.

**Decomposition triggers:**
- Module exceeds 500 lines
- Multiple distinct functions in one module
- Reusable functionality that could be shared
- Clear architectural boundaries (PHY vs MAC, datapath vs control)
- Different clock domains

### Decomposition Principles

#### 1. Separation of Concerns

**Bad: Monolithic uart.sv**
```systemverilog
module uart (
    // Everything in one module:
    // - AXI register interface
    // - TX serialization
    // - RX deserialization
    // - Baud rate generation
    // - FIFOs
    // - CDC synchronizers
);
```

**Good: Hierarchical decomposition**
```
uart_top.sv                  // Top-level integration
├── uart_regs.sv            // AXI-Lite register interface
├── uart_tx_path.sv         // TX datapath
│   ├── async_fifo.sv       // TX FIFO (CDC)
│   └── uart_tx.sv          // TX serializer
├── uart_rx_path.sv         // RX datapath
│   ├── async_fifo.sv       // RX FIFO (CDC)
│   ├── cdc_synchronizer.sv // RX input sync
│   └── uart_rx.sv          // RX deserializer
└── baud_gen.sv             // Baud rate generator
```

#### 2. Interface Abstraction Layers

**Principle:** Hide implementation details behind clean interfaces.

**Example: FIFO Interface**
```systemverilog
// Good: Clean FIFO interface regardless of implementation
module uart_tx_path (
    // Write side (AXI clock domain)
    input  logic       fifo_wr_en,
    input  logic [7:0] fifo_wr_data,
    output logic       fifo_wr_full,

    // Read side (UART clock domain)
    input  logic       fifo_rd_en,
    output logic [7:0] fifo_rd_data,
    output logic       fifo_rd_empty
);
    // Implementation could be sync_fifo or async_fifo
    // Users don't need to know which
```

#### 3. Datapath vs Control Separation

**Guideline:** Separate data movement from control decisions.

**Example:**
```systemverilog
// uart_tx_path.sv - Datapath
// - Moves data from FIFO to serializer
// - No decisions about what to transmit

// uart_regs.sv - Control
// - Decides when to enable TX
// - Handles software interface
// - Sets configuration
```

#### 4. Reusable Components

**Extract reusable blocks:**
- Clock domain crossing synchronizers
- FIFOs (sync and async)
- Gray code converters
- Edge detectors
- Debounce circuits

**Create library structure:**
```
rtl/
├── lib/
│   ├── cdc/
│   │   ├── cdc_synchronizer.sv
│   │   ├── cdc_pulse.sv
│   │   └── async_fifo.sv
│   ├── fifos/
│   │   ├── sync_fifo.sv
│   │   └── async_fifo.sv
│   └── utils/
│       ├── edge_detector.sv
│       └── gray_code.sv
└── uart/
    └── <uart modules>
```

### Decomposition Anti-Patterns

**Anti-pattern 1: Over-decomposition**
```systemverilog
// Bad: One-line modules
module and_gate (input a, b, output c);
    assign c = a & b;
endmodule
```

**Anti-pattern 2: Leaky abstractions**
```systemverilog
// Bad: Exposing internal state
module uart_tx_path (
    output logic [3:0] internal_state,  // Leaks implementation
    output logic [4:0] bit_counter      // Should be private
);
```

**Anti-pattern 3: God modules**
```systemverilog
// Bad: One module that does everything
module uart_and_spi_and_i2c_and_gpio (...);
```

---

## RTL Directory Organization

### Small Projects (< 10 modules)

**Flat structure acceptable:**
```
rtl/
├── uart_top.sv
├── uart_tx.sv
├── uart_rx.sv
├── baud_gen.sv
└── sync_fifo.sv
```

### Medium Projects (10-30 modules)

**Group by function:**
```
rtl/
├── uart_top.sv
├── tx/
│   ├── uart_tx_path.sv
│   └── uart_tx.sv
├── rx/
│   ├── uart_rx_path.sv
│   └── uart_rx.sv
├── common/
│   ├── baud_gen.sv
│   └── uart_regs.sv
└── lib/
    ├── async_fifo.sv
    └── cdc_synchronizer.sv
```

### Large Projects (30+ modules)

**Deep hierarchy with shared libraries:**
```
rtl/
├── top/
│   ├── chip_top.sv
│   └── uart_subsystem.sv
├── uart/
│   ├── uart_top.sv
│   ├── datapath/
│   │   ├── tx/
│   │   │   ├── uart_tx_path.sv
│   │   │   ├── uart_tx.sv
│   │   │   └── tx_checksum.sv
│   │   └── rx/
│   │       ├── uart_rx_path.sv
│   │       ├── uart_rx.sv
│   │       └── rx_checksum.sv
│   ├── control/
│   │   ├── uart_regs.sv
│   │   ├── interrupt_controller.sv
│   │   └── dma_interface.sv
│   └── common/
│       └── baud_gen.sv
├── lib/
│   ├── cdc/
│   │   ├── cdc_synchronizer.sv
│   │   ├── cdc_pulse.sv
│   │   └── async_fifo.sv
│   ├── fifos/
│   │   ├── sync_fifo.sv
│   │   └── async_fifo.sv
│   ├── axi/
│   │   ├── axi_lite_slave.sv
│   │   └── axi_cdc_bridge.sv
│   └── utils/
│       ├── edge_detector.sv
│       ├── gray_code.sv
│       └── reset_sync.sv
└── README.md  # Directory structure documentation
```

### Organization Rules

#### Rule 1: Group by Function, Not Type
**Bad:**
```
rtl/
├── state_machines/
├── datapaths/
└── registers/
```

**Good:**
```
rtl/
├── uart/      # All UART logic
├── spi/       # All SPI logic
└── lib/       # Shared components
```

#### Rule 2: Shared Code Goes in lib/
**Guideline:** If 2+ modules use it, move to lib/

**Examples:**
- CDC synchronizers → `lib/cdc/`
- FIFOs → `lib/fifos/`
- Bus interfaces → `lib/axi/`, `lib/apb/`
- Common utilities → `lib/utils/`

#### Rule 3: One Module Per File
**Exception:** Tightly coupled helper modules can share a file if clearly documented.

**Good:**
```systemverilog
// gray_code.sv

// Binary to Gray
module bin2gray #(parameter WIDTH = 4) (...);
endmodule

// Gray to Binary
module gray2bin #(parameter WIDTH = 4) (...);
endmodule
```

#### Rule 4: Match Directory Name to Module Prefix
**Pattern:** `rtl/<module>/` contains `<module>_*.sv` files

**Example:**
```
rtl/uart/
├── uart_top.sv
├── uart_tx_path.sv
├── uart_rx_path.sv
└── uart_regs.sv
```

### File Naming Conventions

**Modules:**
- Use snake_case: `uart_tx_path.sv`
- Include hierarchy in name: `uart_tx_path.sv` (not just `tx_path.sv`)
- Match module name to file name exactly

**Packages:**
- Use `_pkg` suffix: `uart_defs_pkg.sv`

**Testbenches:**
- Use `_tb` suffix: `uart_tx_tb.sv`
- Place in separate `tb/` or `tests/` directory

### Documentation Files

**Required in each directory:**

**rtl/README.md:**
```markdown
# RTL Directory Structure

## Overview
This directory contains all synthesizable RTL code.

## Subdirectories
- `uart/` - UART peripheral (8N1, 115200 baud)
- `spi/` - SPI master interface
- `lib/` - Reusable components

## Module Hierarchy
(Include block diagram or text hierarchy)

## Dependencies
- All modules depend on lib/cdc/ for clock domain crossing
- UART uses lib/fifos/async_fifo.sv
```

**rtl/uart/README.md:**
```markdown
# UART Module

## Files
- `uart_top.sv` - Top-level integration
- `uart_regs.sv` - AXI-Lite register interface
- `uart_tx_path.sv` - Transmit datapath
- `uart_rx_path.sv` - Receive datapath

## Dependencies
- `../lib/cdc/async_fifo.sv`
- `../lib/cdc/cdc_synchronizer.sv`

## Block Diagram
(Include or reference diagram)
```

---

## Development Phase Gates

### Phase 1: Design Review (MANDATORY)

**Entrance criteria:**
- Interface specifications complete (see Interface Definition Requirements)
- Block diagram reviewed
- Timing requirements documented
- CDC boundaries identified

**Exit criteria:**
- Design review meeting held
- All review comments addressed
- Interfaces approved by at least one other engineer

**Deliverables:**
- Interface specification document
- Block diagram
- Timing analysis
- Design review sign-off

**Git tag:** `design_review_approved`

### Phase 2: Module Development

**For each module:**

1. **Write module test first**
   ```cpp
   // Create tests/<module>_test.cpp before writing <module>.sv
   BOOST_AUTO_TEST_CASE(test_basic_function) {
       // Test the basic requirements
   }
   ```

2. **Implement module**
   - Follow coding standards
   - Add assertions for internal consistency
   - Include synthesis pragmas for simulation-only debug

3. **Validate module in isolation**
   - All test cases passing
   - Coverage analysis (if applicable)
   - Lint clean
   - Synthesis clean

**Exit criteria:**
- Module tests 100% passing
- Code review complete
- No lint warnings
- Module tagged as validated

**Git tag:** `<module_name>_validated` (e.g., `async_fifo_validated`)

### Phase 3: Integration

**Process:**

1. **Create integration test**
   - Test the interface between modules
   - Don't retest module internals

2. **Integrate ONE module at a time**
   ```bash
   git checkout integration_base
   git checkout async_fifo_validated -- rtl/async_fifo.sv tests/async_fifo_test.cpp
   # Update parent module to instantiate async_fifo
   # Run integration tests
   git commit -m "Integrate async_fifo into uart_tx_path"
   ```

3. **Validate after each integration**
   - Integration tests pass
   - Previous tests still pass (regression)

**Exit criteria:**
- All integration tests passing
- All module tests still passing (no regression)
- Integration reviewed

**Git tag:** `<subsystem>_integration_pass` (e.g., `uart_tx_integration_pass`)

### Phase 4: System Validation

**Process:**

1. **System-level test development**
   - End-to-end functionality
   - Multi-module interactions
   - Error injection and recovery

2. **Performance validation**
   - Throughput testing
   - Latency measurement
   - Resource utilization

3. **Regression suite**
   - All tests from all phases
   - Automated nightly runs

**Exit criteria:**
- System tests 100% passing
- Performance requirements met
- No known bugs (or documented/waived)
- Regression suite passing

**Git tag:** `system_validated`

### Gate Enforcement

**HARD RULE: Cannot proceed to next phase without exit criteria met.**

**Automated gate checks:**
```bash
#!/bin/bash
# pre-push hook: Verify current phase complete

if [ ! -f .current_phase ]; then
    echo "No phase file found - run ./scripts/set_phase.sh"
    exit 1
fi

PHASE=$(cat .current_phase)

if [ "$PHASE" == "module_dev" ]; then
    # Check all module tests pass
    ./build/module_tests --log_level=error || exit 1
fi

if [ "$PHASE" == "integration" ]; then
    # Check module + integration tests pass
    ./build/module_tests --log_level=error || exit 1
    ./build/integration_tests --log_level=error || exit 1
fi

echo "Phase gate passed: $PHASE"
```

---

## Change Control Process

### Before Making Changes

**Question checklist:**
1. Is there a known-good baseline to return to? (git tag?)
2. Can I describe this change in one sentence?
3. Do I have tests that validate current behavior?
4. What could break as a result of this change?

### Making Architectural Changes

**Definition:** Architectural changes affect multiple modules or change fundamental assumptions.

**Examples:**
- Changing FIFO type (sync → async)
- Adding clock domain crossings
- Changing bus protocol
- Modifying timing relationships

**MANDATORY process for architectural changes:**

1. **Document the change**
   - Create `docs/arch_change_<name>.md`
   - Describe current state, proposed state, rationale
   - List affected modules
   - Estimate impact (test updates, timing, resources)

2. **Design review**
   - Present to team
   - Get approval before implementation

3. **Create rollback point**
   ```bash
   git tag -a before_arch_change_<name> -m "Baseline before <change>"
   git push --tags
   ```

4. **Incremental implementation**
   - Implement in smallest possible steps
   - Validate after each step
   - Commit frequently with clear messages

5. **Validation**
   - All tests updated and passing
   - Performance validation
   - Documentation updated

### Making Bug Fixes

**Process:**

1. **Reproduce the bug**
   - Add test case that fails
   - Commit failing test with clear description

2. **Root cause analysis**
   - Document findings in commit message or issue

3. **Fix**
   - Minimal change to address root cause
   - Update tests to verify fix

4. **Regression test**
   - Ensure fix doesn't break other functionality

### Commit Message Standards

**Format:**
```
<type>: <short summary (50 chars)>

<detailed description>

Affected modules: <list>
Tests updated: <yes/no>
Regression status: <pass/fail>
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `refactor:` Code restructuring (no behavior change)
- `test:` Test updates
- `docs:` Documentation
- `arch:` Architectural change

**Example:**
```
fix: RX prefetch FSM rd_en assertion

The rx_rd_en signal only pulsed when transitioning IDLE→FETCHING,
not READY→FETCHING. This caused RX holding register to stick on
first value when reading multiple bytes.

Root cause: rx_rd_en logic didn't account for READY→FETCHING transition.

Solution: Added rx_entering_fetching signal that pulses for both
IDLE→FETCHING and READY→FETCHING transitions.

Affected modules: uart_regs.sv
Tests updated: yes
Regression status: pass
```

---

## Test Strategy

### Test Levels

#### 1. Module Tests (Unit Tests)
**Purpose:** Validate single module in isolation

**Requirements:**
- Test all input combinations
- Test all state transitions
- Test error conditions
- Test corner cases (empty, full, wraparound)

**Example: async_fifo_test.cpp**
```cpp
BOOST_AUTO_TEST_CASE(fifo_empty_flag) {
    // Test FIFO empty flag behavior
}

BOOST_AUTO_TEST_CASE(fifo_full_flag) {
    // Test FIFO full flag behavior
}

BOOST_AUTO_TEST_CASE(fifo_write_read_sequence) {
    // Test basic write then read
}

BOOST_AUTO_TEST_CASE(fifo_wraparound) {
    // Test pointer wraparound
}
```

#### 2. Integration Tests
**Purpose:** Validate module interactions

**Requirements:**
- Test data flow between modules
- Test clock domain crossings
- Test backpressure handling
- Don't retest module internals

**Example: uart_tx_path_integration_test.cpp**
```cpp
BOOST_AUTO_TEST_CASE(axi_to_serial_dataflow) {
    // Write to FIFO via AXI interface
    // Verify data appears on TX serial output
    // Validate CDC timing
}
```

#### 3. System Tests
**Purpose:** Validate complete system functionality

**Requirements:**
- End-to-end user scenarios
- Multi-module interactions
- Performance validation
- Error injection and recovery

**Example: uart_loopback_tests.cpp**
```cpp
BOOST_AUTO_TEST_CASE(loopback_multiple_bytes) {
    // Write bytes via AXI
    // Verify they arrive via RX path
    // Measure latency
}
```

### Test Development Rules

**Rule 1: Write Tests Before Implementation**
```bash
# Correct order:
1. Write failing test
2. Implement module
3. Test passes

# Wrong order:
1. Implement module
2. Write test to match implementation
```

**Rule 2: Test Requirements Not Implementation**
```cpp
// Good: Tests requirement
BOOST_CHECK_EQUAL(start_bit, 0);  // UART start bit must be 0

// Bad: Tests implementation detail
BOOST_CHECK_EQUAL(internal_state, 3);  // Who cares about state encoding?
```

**Rule 3: One Concept Per Test**
```cpp
// Good: Focused tests
BOOST_AUTO_TEST_CASE(start_bit_is_zero) { ... }
BOOST_AUTO_TEST_CASE(stop_bit_is_one) { ... }

// Bad: Kitchen sink test
BOOST_AUTO_TEST_CASE(uart_works) {
    // Tests start bit, stop bit, data, parity, timing, etc.
}
```

### Test Fixture Best Practices

**DRY principle for test setup:**
```cpp
struct UARTModuleFixture {
    Vuart_tx* dut;

    UARTModuleFixture() {
        dut = new Vuart_tx;
        // Common initialization
        reset();
    }

    ~UARTModuleFixture() {
        delete dut;
    }

    void reset() {
        dut->rst_n = 0;
        tick(5);
        dut->rst_n = 1;
        tick(1);
    }

    void tick(int n = 1) {
        for (int i = 0; i < n; i++) {
            dut->uart_clk = 0; dut->eval();
            dut->uart_clk = 1; dut->eval();
        }
    }
};
```

### Coverage Goals

**Module tests:**
- Line coverage: 100%
- Branch coverage: 100%
- FSM state coverage: 100%
- FSM transition coverage: 100%

**Integration tests:**
- Interface coverage: 100% (all handshake combinations)
- CDC path coverage: 100%

**System tests:**
- Feature coverage: 100%
- Error path coverage: 90%+

---

## Hardware Code Review Checklist

### General

- [ ] Module has clear single responsibility
- [ ] Interface fully documented (signals, timing, protocol)
- [ ] All parameters documented with valid ranges
- [ ] Clock domains clearly identified
- [ ] Reset strategy documented and consistent

### Clocking and Reset

- [ ] All sequential logic uses single clock edge (no mixed edge)
- [ ] Reset polarity consistent across design
- [ ] Asynchronous resets properly synchronized
- [ ] No derived clocks (use clock enables instead)
- [ ] No combinatorial feedback loops

### Clock Domain Crossing (CDC)

- [ ] All CDC paths identified and documented
- [ ] Multi-bit buses use Gray code or async FIFO
- [ ] Single-bit signals use 2-FF synchronizer
- [ ] Pulse signals use CDC pulse synchronizer
- [ ] No combinatorial paths across clock domains
- [ ] Metastability recovery time adequate (2+ stages)

### Finite State Machines (FSMs)

- [ ] State encoding explicitly defined
- [ ] All states reachable from reset
- [ ] All transitions defined (no incomplete case)
- [ ] Default case catches illegal states
- [ ] State register separate from next-state logic
- [ ] Outputs registered (Moore) or carefully controlled (Mealy)

Example:
```systemverilog
// Good FSM structure
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= IDLE;
    else
        state <= next_state;
end

always_comb begin
    next_state = state;  // Default: hold state
    case (state)
        IDLE:    if (start) next_state = ACTIVE;
        ACTIVE:  if (done) next_state = IDLE;
        default: next_state = IDLE;  // Recovery
    endcase
end
```

### FIFOs

- [ ] Depth is power-of-2 (for pointer wraparound)
- [ ] Empty/full flags properly generated
- [ ] No writes when full (check or ignore)
- [ ] No reads when empty (check or block)
- [ ] Read output registered for timing (async FIFO)
- [ ] Gray code used for pointer CDC (async FIFO)

### Data Paths

- [ ] No arithmetic overflow possible
- [ ] Bit widths sized appropriately
- [ ] Shift registers shift correct direction
- [ ] LSB/MSB first explicitly documented
- [ ] Proper handling of sign extension

### Interfaces

- [ ] Ready/valid handshakes follow standard rules:
  - Data stable when valid=1
  - valid cannot wait for ready
  - ready can wait for valid
  - Transaction completes when both high
- [ ] AXI compliance (if using AXI)
- [ ] No combinatorial paths through module

### Simulation and Debug

- [ ] Assertions for internal consistency
- [ ] Debug displays use `synthesis translate_off` pragmas
- [ ] No simulation-only logic in synthesizable code
- [ ] Meaningful signal names (not `tmp`, `sig1`, etc.)

### Synthesis Considerations

- [ ] No latches (incomplete assignments)
- [ ] No `initial` blocks (non-synthesizable)
- [ ] No delays (`#10`) in synthesizable code
- [ ] No `$time`, `$display` without pragma guards
- [ ] Multipliers/dividers appropriate for target
- [ ] RAM inference correct (registered read address)

---

## Test Infrastructure Validation

### Clock Generator Validation

**MANDATORY before DUT testing:**

**Test 1: Frequency accuracy**
```cpp
BOOST_AUTO_TEST_CASE(clock_frequency_validation) {
    ClockDriver clk(&signal, 8000000);  // 8 MHz

    int edges = 0;
    uint64_t start_time = 0;
    uint64_t end_time = 0;

    // Count rising edges for 1 ms
    for (uint64_t t = 0; t < 1000000; t++) {
        bool prev = signal;
        clk.update(t);
        if (!prev && signal) {
            if (edges == 0) start_time = t;
            edges++;
        }
    }
    end_time = current_time;

    // Should see ~8000 edges in 1 ms at 8 MHz
    BOOST_CHECK_CLOSE(edges, 8000, 1.0);  // 1% tolerance
}
```

**Test 2: Duty cycle**
```cpp
BOOST_AUTO_TEST_CASE(clock_duty_cycle_validation) {
    ClockDriver clk(&signal, 8000000);

    uint64_t high_time = 0;
    uint64_t total_time = 1000;  // 1 us = 8 periods

    for (uint64_t t = 0; t < total_time; t++) {
        clk.update(t);
        if (signal) high_time++;
    }

    double duty_cycle = (double)high_time / total_time;
    BOOST_CHECK_CLOSE(duty_cycle, 0.5, 1.0);  // 50% ± 1%
}
```

**Test 3: Clock relationship**
```cpp
BOOST_AUTO_TEST_CASE(clock_ratio_validation) {
    ClockDriver fast_clk(&fast_sig, 8000000);
    ClockDriver slow_clk(&slow_sig, 1000000);

    int fast_edges = 0, slow_edges = 0;

    for (uint64_t t = 0; t < 1000000; t++) {  // 1 ms
        bool prev_fast = fast_sig, prev_slow = slow_sig;
        fast_clk.update(t);
        slow_clk.update(t);
        if (!prev_fast && fast_sig) fast_edges++;
        if (!prev_slow && slow_sig) slow_edges++;
    }

    // 8 MHz / 1 MHz = 8:1 ratio
    BOOST_CHECK_CLOSE((double)fast_edges / slow_edges, 8.0, 1.0);
}
```

### Protocol Checker Validation

**For any bus monitor/checker, validate it separately:**

```cpp
BOOST_AUTO_TEST_CASE(axi_checker_validation) {
    // Generate known-good AXI transactions
    // Verify checker accepts them

    // Generate known-bad AXI transactions
    // Verify checker flags errors
}
```

### Timing Verifier Validation

**If measuring timing relationships, validate the measurement:**

```cpp
BOOST_AUTO_TEST_CASE(timing_measurement_validation) {
    // Generate signal with known timing
    // Measure timing with test infrastructure
    // Verify measurement accuracy
}
```

---

## Recovery Procedures

### When Tests Start Failing

**Step 1: Identify baseline**
```bash
git tag  # Find last known-good tag
git log --oneline --decorate
```

**Step 2: Bisect if needed**
```bash
git bisect start
git bisect bad HEAD
git bisect good <last-known-good-tag>
# Git will check out commits
# Run tests and mark: git bisect good / git bisect bad
```

**Step 3: Analyze the breaking change**
- What was changed?
- What tests are failing?
- What is the root cause?

**Step 4: Choose recovery path**

**Option A: Fix forward (preferred for small issues)**
- Understand the bug
- Fix the root cause
- Validate fix with tests

**Option B: Rollback and re-implement (for large issues)**
```bash
git reset --hard <last-known-good-tag>
git checkout -b rework_<feature>
# Re-implement incrementally with validation
```

### When Architecture Change Goes Wrong

**Scenario: Changed from sync_fifo to async_fifo, now 19 tests fail**

**DON'T DO THIS:**
- Try to debug all 19 failures simultaneously
- Patch tests to make them pass
- Keep making changes hoping something works

**DO THIS:**

**Step 1: Rollback to last known-good**
```bash
git reset --hard module_tests_pass  # Baseline tag
```

**Step 2: Validate baseline**
```bash
./build/module_tests  # Should show 0 failures
./build/system_tests  # Should pass
```

**Step 3: Validate new component in isolation**
```bash
git checkout arch_change_branch -- rtl/async_fifo.sv tests/async_fifo_test.cpp
./build/module_tests --run_test=AsyncFIFO_Tests/*
# All async_fifo tests must pass before integration
```

**Step 4: Incremental integration with validation**
```bash
# Integration 1: Update TX path
git checkout arch_change_branch -- rtl/uart_tx_path.sv
# Update instantiation, compile, test
./build/module_tests --run_test=UartTX_*
# STOP if failures - debug before proceeding

# Integration 2: Update RX path
git checkout arch_change_branch -- rtl/uart_rx_path.sv
./build/module_tests --run_test=UartRX_*
# STOP if failures

# Integration 3: System tests
./build/system_tests
```

**Step 5: Tag validated state**
```bash
git tag -a async_fifo_integrated_validated -m "Async FIFO fully integrated and tested"
```

### Recovery Decision Tree

```
Tests failing?
├─ YES → When did they last pass?
│   ├─ Know exact commit →
│   │   └─ git checkout <commit>
│   │       └─ Verify tests pass
│   │           └─ git diff <commit> HEAD
│   │               └─ Analyze changes
│   │                   └─ Fix forward or re-implement
│   └─ Don't know →
│       └─ git bisect
│           └─ Find breaking commit
│               └─ (Follow "Know exact commit" path)
└─ NO → Proceed with development
```

---

## Project-Specific Learnings: UART

### What Went Wrong

**Issue 1: Async FIFO integration without validation**

**What happened:**
- Changed from sync_fifo to async_fifo mid-project
- Did not validate async_fifo in isolation first
- Integrated into uart_tx_path and uart_rx_path simultaneously
- Module tests began failing (19 failures)
- Root cause hard to isolate due to multiple changes

**Root cause:**
- Async FIFO has registered read output (1 cycle latency)
- Sync FIFO had combinatorial read output (0 cycle latency)
- TX/RX paths assumed 0-cycle latency
- Prefetch logic needed but not added during initial integration

**Should have done:**
1. Create async_fifo_test.cpp with comprehensive tests
2. Validate async_fifo in isolation
3. Tag commit: `async_fifo_validated`
4. Document latency difference: sync (0 cyc) vs async (1 cyc)
5. Update TX path with prefetch logic
6. Test TX path integration
7. Update RX path with prefetch logic
8. Test RX path integration
9. System testing

**Issue 2: TX baud rate divider change broke module tests**

**What happened:**
- TX module needed to divide 16× sample_tick to 1× baud_tick
- Added divider to uart_tx.sv
- Module test (uart_tx_test.cpp) broke because it used old timing

**Root cause:**
- Module test was not updated to match new requirements
- Test should have been updated BEFORE implementation

**Should have done:**
1. Update uart_tx_test.cpp to provide 16× sample_tick
2. Verify test fails (red)
3. Implement divider in uart_tx.sv
4. Verify test passes (green)

**Issue 3: RX sample counter initialization broke reception**

**What happened:**
- Set rx sample_counter initial value to 8 (middle of bit)
- RX failed to receive any data

**Root cause:**
- Counter should start at 0 on start bit detection
- RX samples at counter==8 (middle of bit period)
- If counter starts at 8, it immediately samples, causing misalignment

**Lesson:**
- Understand timing requirements fully before changing
- Draw timing diagrams when in doubt
- Test timing-sensitive changes carefully

**Issue 4: Multiple changes without intermediate validation**

**What happened:**
- Made 4 changes to fix RX path
- All committed together
- System tests still failing
- Which change caused new issue?

**Root cause:**
- No incremental validation
- Cannot isolate which change broke what

**Should have done:**
```bash
# Change 1: Add FIFO clear
<make change>
git commit -m "Add FIFO wr_clear/rd_clear ports"
<run tests - verify passing>

# Change 2: Fix RX prefetch
<make change>
git commit -m "Fix RX prefetch rd_en assertion"
<run tests - verify passing>

# Etc.
```

### Key Technical Insights

**CDC with Async FIFOs:**
- Always use registered read output for timing closure
- Document the 1-cycle read latency
- Implement prefetch/holding registers if 0-cycle response needed
- Gray code pointers prevent multi-bit CDC issues

**UART Timing:**
- TX needs 1× baud rate, but convenient to use 16× with divider
- RX needs 16× for oversampling
- Sample counter must align with bit boundaries (reset to 0 on start detect)
- Sample at middle of bit (count 8 of 16)

**Test Infrastructure:**
- Clock generators must be validated before use
- Frequency, duty cycle, and phase relationships critical
- Use time-based simulation for accuracy
- Multiple clock domains need nanosecond-level precision

**Prefetch FSMs:**
- Needed when registered FIFO output creates latency
- Must pulse rd_en for both IDLE→FETCHING and READY→FETCHING
- Track data consumption carefully to avoid stuck states

**Duplicate Write Prevention:**
- rx_valid stays HIGH for multiple cycles (until handshake completes)
- Must use tracking flag to ensure single FIFO write per rx_valid assertion
- Flag clears when rx_valid drops

### UART-Specific Test Strategy

**Module tests:**
1. uart_tx_test.cpp - TX serializer in isolation
2. uart_rx_test.cpp - RX deserializer in isolation
3. baud_gen_test.cpp - Baud rate generator accuracy
4. async_fifo_test.cpp - FIFO corner cases

**Integration tests:**
1. uart_tx_path_test.cpp - AXI write → Serial out
2. uart_rx_path_test.cpp - Serial in → AXI read
3. uart_regs_test.cpp - Register interface

**System tests:**
1. uart_loopback_tests.cpp - TX→RX same device
2. uart_full_duplex_tests.cpp - Simultaneous TX/RX

### Recovery Checklist for This UART Project

If starting over from commit `905ec2e` (module tests passing):

- [ ] **Validate baseline**
  ```bash
  git checkout 905ec2e
  ./build/module_tests  # Expect 0 failures
  ```

- [ ] **Extract and validate async_fifo**
  ```bash
  git checkout -b async_fifo_isolation
  # Copy async_fifo.sv from later commit
  # Create async_fifo_test.cpp
  # Validate all corner cases
  git tag async_fifo_validated
  ```

- [ ] **Integrate TX path incrementally**
  ```bash
  # Update uart_tx_path.sv to use async_fifo
  # Add TX prefetch logic
  # Test TX path
  # Tag: uart_tx_async_validated
  ```

- [ ] **Integrate RX path incrementally**
  ```bash
  # Update uart_rx_path.sv to use async_fifo
  # Add RX prefetch logic
  # Test RX path
  # Tag: uart_rx_async_validated
  ```

- [ ] **Update register file**
  ```bash
  # Connect new prefetch interfaces
  # Test register access
  # Tag: uart_regs_async_validated
  ```

- [ ] **System testing**
  ```bash
  ./build/system_tests
  # Tag: uart_system_async_validated
  ```

---

## Templates and Examples

### Module Test Template

```cpp
/*
 * <Module> Unit Tests
 *
 * Tests <module_name> in isolation.
 *
 * Test coverage:
 * - Basic functionality
 * - Corner cases
 * - Error conditions
 * - State transitions (if FSM)
 */

#include "V<module_name>.h"
#include <boost/test/unit_test.hpp>
#include <verilated.h>

BOOST_AUTO_TEST_SUITE(<Module>_UnitTests)

struct <Module>Fixture {
    V<module_name>* dut;

    <Module>Fixture() {
        dut = new V<module_name>;
        // Initialize inputs
        dut->clk = 0;
        dut->rst_n = 0;
    }

    ~<Module>Fixture() {
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
        tick();
        tick();
        dut->rst_n = 1;
        tick();
    }
};

BOOST_FIXTURE_TEST_CASE(test_reset_state, <Module>Fixture) {
    reset();

    // Verify reset state
    BOOST_CHECK_EQUAL(dut->output_signal, expected_reset_value);
}

BOOST_FIXTURE_TEST_CASE(test_basic_operation, <Module>Fixture) {
    reset();

    // Apply stimulus
    dut->input_signal = value;
    tick();

    // Check response
    BOOST_CHECK_EQUAL(dut->output_signal, expected_value);
}

// Add more test cases...

BOOST_AUTO_TEST_SUITE_END()
```

### Git Tag Template

```bash
# Module validated
git tag -a <module>_validated -m "<Module> module tests passing (N/N tests)"

# Integration complete
git tag -a <subsystem>_integration_pass -m "<Subsystem> integration validated"

# System validated
git tag -a system_validated -m "Full system tests passing"

# Before architectural change
git tag -a before_<change_name> -m "Baseline before <change description>"
```

### Timing Diagram Template

```
Signal Name    | t0  | t1  | t2  | t3  | t4  | t5  |
---------------|-----|-----|-----|-----|-----|-----|
clk            | _/‾ | _/‾ | _/‾ | _/‾ | _/‾ | _/‾ |
valid          | __/ | ‾‾‾ | ‾‾‾ | ‾\_ | ___ | ___ |
ready          | ___ | __/ | ‾‾‾ | ‾‾‾ | ‾‾‾ | ‾‾‾ |
data           | XXX | XXX | [D] | [D] | XXX | XXX |
                            ^^^^^ Transaction completes

Notes:
- valid asserted at t1
- ready asserted at t2
- Transaction completes at t3 (both high)
- data must be stable from t1 to t3
```

### Interface Review Checklist Template

```markdown
# Interface Review: <module_name>

## Review Info
- Reviewer: ___________
- Date: ___________
- Commit: ___________

## Interface Specification
- [ ] All signals documented (name, direction, width, clock domain)
- [ ] Timing diagrams provided for complex handshakes
- [ ] Protocol rules explicitly stated (who waits for whom)
- [ ] Reset values specified
- [ ] Clock domain crossings identified
- [ ] CDC synchronization method specified
- [ ] Latency characteristics documented

## Design Quality
- [ ] Interface is minimal (no unnecessary signals)
- [ ] Interface is complete (no missing functionality)
- [ ] Signal names are clear and consistent
- [ ] No combinatorial paths between input and output

## Integration Concerns
- [ ] Compatible with existing modules
- [ ] CDC paths properly handled
- [ ] Timing constraints achievable
- [ ] Resource utilization acceptable

## Approval
- [ ] Approved for implementation
- [ ] Changes required (see comments below)

## Comments:
(Add detailed feedback here)
```

---

## Summary

These guidelines establish a rigorous process for hardware development focused on:

1. **Incremental validation** - Test at every level (module, integration, system)
2. **Change control** - One change at a time with clear rollback points
3. **Test-driven development** - Write tests first, validate requirements
4. **Clear interfaces** - Document protocols, timing, and CDC boundaries
5. **Hierarchical decomposition** - Separate concerns, create reusable components
6. **Organized structure** - Logical directory hierarchy with documentation

**The golden rule:** If you can't easily rollback to a known-good state, you're doing it wrong.

**Key insight from UART project:** Making architectural changes (sync→async FIFO) without re-validation cascaded into weeks of debugging. Following these guidelines prevents that pain.

**Next steps for this project:**
1. Establish baseline at commit 905ec2e
2. Follow recovery checklist
3. Tag all validated states
4. Maintain known-good baselines going forward
