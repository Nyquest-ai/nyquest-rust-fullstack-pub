pub mod engine;
pub mod format;
pub mod minify;
pub mod rules;
pub mod telegraph;

pub use engine::{compress_request, CompressionResult, CompressionStats};
