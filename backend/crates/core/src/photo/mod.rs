// Co-authored-by: deepseek-v4-flash (opencode-go)
pub mod aggregate;
pub mod binding;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use aggregate::PhotoAggregate;
pub use binding::PhotoBinding;
pub use commands::{
    DeletePhoto, GenerateVariant, MarkVariantFailed, NormalizeOriginal, UploadPhoto,
};
pub use error::PhotoError;
pub use events::PhotoEvent;
pub use ports::{PhotoCommands, PhotoRepository, PhotoStorage};
pub use views::{PhotoBytes, PhotoGcConfig, PhotoMetadata, PhotoVariantView, PhotoView};
