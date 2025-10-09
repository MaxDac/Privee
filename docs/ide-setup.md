# IDE setups

## Zed

To use Zed with WSL2, you need to set up the Zed remote server inside your WSL2 environment. 
Below are the steps to install and configure the Zed remote server.

```sh
# Inside WSL2 (Ubuntu/Debian)
sudo apt update
sudo apt install -y build-essential clang cmake pkg-config libssl-dev git curl

# Install Rust toolchain
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# Build Zed remote server
git clone https://github.com/zed-industries/zed.git
cd zed
# (Optional) make Clang the linker for consistency
export RUSTFLAGS="-C linker=clang"
cargo build -p remote_server --release

# Install where Zed expects the dev build name:
mkdir -p ~/.zed_server
cp target/release/remote_server ~/.zed_server/zed-remote-server-dev-build
chmod +x ~/.zed_server/zed-remote-server-dev-build
```

Then it will be possible to connect to the WSL2 Zed remote server from the Zed desktop app,
by pressing `Ctrl+Alt+Shift+o` and entering `ssh <your-username>@localhost -p <your-port>`.
