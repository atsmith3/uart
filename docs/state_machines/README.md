# UART State Machine Diagrams

This directory contains DOT (Graphviz) source files for all UART state machines.

## Files

### Core UART State Machines
- **`uart_tx_fsm.dot`** - TX serializer state machine (IDLE → START → DATA → STOP)
- **`uart_rx_fsm.dot`** - RX deserializer with 16× oversampling

### AXI-Lite Protocol State Machines
- **`axi_write_fsm.dot`** - AXI-Lite write path (3 channels: AW, W, B)
- **`axi_read_fsm.dot`** - AXI-Lite read path (2 channels: AR, R)

### Register Interface State Machines
- **`uart_regs_rx_prefetch_fsm.dot`** - RX FIFO prefetch to hide read latency

## Generating Diagrams

### Prerequisites
```bash
sudo apt-get install graphviz
```

### Generate All SVG Diagrams
```bash
make all
```

### Generate Individual Diagram
```bash
dot -Tsvg uart_tx_fsm.dot -o uart_tx_fsm.svg
```

### Generate PNG (for documentation)
```bash
dot -Tpng uart_tx_fsm.dot -o uart_tx_fsm.png
```

### Generate PDF (high quality)
```bash
dot -Tpdf uart_tx_fsm.dot -o uart_tx_fsm.pdf
```

## Usage in Implementation

These state machines are **normative specifications**. When implementing RTL:

1. **Use the DOT file as reference** - States and transitions are exact
2. **Match state names** - Use same enum names in SystemVerilog
3. **Verify all transitions** - Every edge in the diagram must be in the code
4. **Check conditions** - Transition conditions must match exactly

## State Machine Design Rules

### General Rules
- All state machines are **Moore machines** (outputs depend only on state, not inputs)
- Exceptions noted explicitly (e.g., combinatorial outputs)
- All state registers use synchronous reset
- Default state is first listed (double circle in diagram)

### UART Specific Rules
- TX and RX operate on different tick rates (baud_tick vs sample_tick)
- All transitions are gated by tick signals (not every clock cycle)
- Sample counter values are critical (especially RX: sample at count=8)

### AXI-Lite Specific Rules
- Write and read paths are independent FSMs (can operate concurrently)
- Ready signals can be combinatorial or registered (registered preferred)
- Response must wait for master ready signal (bready/rready)

## Validation

Before implementation, verify:
- [ ] All states are reachable from reset
- [ ] No deadlock states (all states have exit path)
- [ ] All input combinations covered (no unhandled cases)
- [ ] Outputs defined for every state

## Tool Support

### Verification
- Use formal verification tools to check state machine properties
- Verify against DOT specification

### Simulation
- Generate test vectors from state transition graph
- Achieve 100% state and transition coverage

### Documentation
- Include generated diagrams in design review documents
- Update DOT files when state machine changes

## Revision History

| Date       | Author | Change |
|------------|--------|--------|
| 2025-11-26 | Claude | Initial state machine diagrams for clean restart |
