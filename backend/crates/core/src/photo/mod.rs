// Co-authored-by: kwaipilot/kat-coder-air-v2.5 (openrouter)
pub mod aggregate;
pub mod binding;
pub mod commands;
pub mod error;
pub mod events;
pub mod ports;
pub mod views;

pub use binding::PhotoBinding;
pub use commands::{
    DeletePhoto, GenerateVariant, MarkVariantFailed, NormalizeOriginal, UploadPhoto,
};
pub use events::PhotoEvent;
pub use ports::{PhotoCommands, PhotoRepository, PhotoStorage};
pub use views::{PhotoBytes, PhotoGcConfig, PhotoMetadata, PhotoVariantView, PhotoView};
