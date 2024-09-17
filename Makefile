.PHONY: all build build-dbg clean format

all: clean format build build-dbg
	@echo "Done!"

clean:
	@rm -f ./scripts/*.plutus

format:
	@aiken fmt

build:
	@aiken build -u
	# @aiken blueprint convert --validator key.revoke > ./scripts/key_validator.plutus
