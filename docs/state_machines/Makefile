# Makefile for generating state machine diagrams from DOT files

# DOT source files
DOT_FILES = uart_tx_fsm.dot \
            uart_rx_fsm.dot \
            axi_write_fsm.dot \
            axi_read_fsm.dot \
            uart_regs_rx_prefetch_fsm.dot

# Output formats
SVG_FILES = $(DOT_FILES:.dot=.svg)
PNG_FILES = $(DOT_FILES:.dot=.png)
PDF_FILES = $(DOT_FILES:.dot=.pdf)

# Graphviz command
DOT = dot

# Default target: generate SVG files (best for web/HTML)
all: svg

# Generate SVG files
svg: $(SVG_FILES)

# Generate PNG files (for presentations)
png: $(PNG_FILES)

# Generate PDF files (for printing)
pdf: $(PDF_FILES)

# Pattern rules
%.svg: %.dot
	@echo "Generating $@ from $<"
	$(DOT) -Tsvg $< -o $@

%.png: %.dot
	@echo "Generating $@ from $<"
	$(DOT) -Tpng -Gdpi=300 $< -o $@

%.pdf: %.dot
	@echo "Generating $@ from $<"
	$(DOT) -Tpdf $< -o $@

# Clean generated files
clean:
	rm -f $(SVG_FILES) $(PNG_FILES) $(PDF_FILES)

# Validate DOT syntax (requires graphviz)
validate:
	@for file in $(DOT_FILES); do \
		echo "Validating $$file..."; \
		$(DOT) -Tsvg $$file -o /dev/null || exit 1; \
	done
	@echo "All DOT files are valid!"

# Display info
info:
	@echo "State Machine Diagram Generator"
	@echo "================================"
	@echo "DOT files: $(DOT_FILES)"
	@echo ""
	@echo "Targets:"
	@echo "  make all       - Generate SVG files (default)"
	@echo "  make svg       - Generate SVG files"
	@echo "  make png       - Generate PNG files"
	@echo "  make pdf       - Generate PDF files"
	@echo "  make clean     - Remove generated files"
	@echo "  make validate  - Check DOT syntax"
	@echo "  make view      - Generate and view SVG files"

# View generated SVG files (requires xdg-open or equivalent)
view: svg
	@for file in $(SVG_FILES); do \
		xdg-open $$file 2>/dev/null || open $$file 2>/dev/null || echo "Please open $$file manually"; \
	done

.PHONY: all svg png pdf clean validate info view
