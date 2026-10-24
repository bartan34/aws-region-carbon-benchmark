# Regenerate every derived file from data/raw and data/coefficients.
PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)

.PHONY: results sci figures check

results: sci figures

sci:
	$(PYTHON) analysis/sci.py

figures:
	$(PYTHON) analysis/figures.py

# Fails if regenerated numbers differ from the committed ones. Figures are not
# compared: PNG bytes vary with matplotlib version and fonts.
check: results
	git diff --exit-code -- data/processed
