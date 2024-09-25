.PHONY: all build build-dbg clean format

all: clean format build build-dbg
	@echo "Done!"

clean:
	@rm -f ./scripts/*.plutus

format:
	@aiken fmt

build:
	@aiken build -u
	@aiken blueprint convert --validator bet_ref.spend > ./scripts/bet_ref_spend.plutus
	@aiken blueprint convert --validator always.spend > ./scripts/always_spend.plutus
