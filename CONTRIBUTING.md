# Contributing to Nyquest

Thank you for your interest in contributing to Nyquest!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/nyquest-rust-fullstack-pub.git`
3. Create a branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Run tests: `cargo test`
6. Commit with a descriptive message
7. Push and open a Pull Request

## Development Setup

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Build
cargo build --release

# Run tests
cargo test

# Run the engine
./target/release/nyquest serve
```

## Guidelines

- Follow existing code style (rustfmt)
- Add tests for new functionality
- Keep PRs focused on a single change
- Update documentation for user-facing changes

## Reporting Issues

Please use GitHub Issues with a clear description, steps to reproduce, and expected vs actual behavior.

## License

By contributing, you agree that your contributions will be licensed under the MIT/Apache-2.0 dual license.
