.PHONY: release install
release:
	# For darwin arm64
	zig build --release=fast -Dtarget=aarch64-macos
	cp ./zig-out/bin/type-chimpanzee ./type-chimpanzee_darwin_arm64
	# For linux x86_64
	zig build --release=fast -Dtarget=x86_64-linux
	cp ./zig-out/bin/type-chimpanzee ./type-chimpanzee_linux_x86_64

install:
	zig build --release=fast
	cp ./zig-out/bin/type-chimpanzee ~/.local/bin/
