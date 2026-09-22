use super::{ModelProvider, ProviderCredential};
use anyhow::Context as _;
use std::fs::{File, OpenOptions};
use std::io::{Read as _, Write as _};
use std::path::{Path, PathBuf};
use std::time::Duration;
use xai_grok_shell_base::util::secure_file::ensure_owner_only_permissions;

fn directory(home: &Path) -> PathBuf {
    home.join("provider-auth")
}

fn path(home: &Path, provider: ModelProvider) -> PathBuf {
    directory(home).join(format!("{}.json", provider.as_str()))
}

fn prepare_directory(home: &Path) -> anyhow::Result<()> {
    let dir = directory(home);
    xai_grok_config::create_dir_all_owner_only(&dir)
        .context("Cannot create private provider credential directory")
}

fn secure_options() -> OpenOptions {
    let mut options = OpenOptions::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt as _;
        options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
    }
    options
}

pub(super) fn read(
    home: &Path,
    provider: ModelProvider,
) -> anyhow::Result<Option<ProviderCredential>> {
    let path = path(home, provider);
    let mut file = match secure_options().read(true).open(&path) {
        Ok(file) => file,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e).context("Cannot read provider credential file"),
    };
    ensure_owner_only_permissions(&path)
        .context("Cannot secure provider credential file permissions")?;
    let mut data = Vec::new();
    (&mut file).take(1024 * 1024 + 1).read_to_end(&mut data)?;
    anyhow::ensure!(
        data.len() <= 1024 * 1024,
        "Provider credential file is too large"
    );
    // Do not propagate serde errors: a malformed field value could contain a secret.
    let credential: ProviderCredential = serde_json::from_slice(&data)
        .map_err(|_| anyhow::anyhow!("Invalid {provider} credential file"))?;
    credential.validate(provider)?;
    Ok(Some(credential))
}

pub(super) fn write(home: &Path, credential: &ProviderCredential) -> anyhow::Result<()> {
    prepare_directory(home)?;
    let destination = path(home, credential.provider);
    let temporary = directory(home).join(format!(".{}.tmp", uuid::Uuid::new_v4()));
    let result = (|| -> anyhow::Result<()> {
        let mut file = secure_options()
            .write(true)
            .create_new(true)
            .open(&temporary)?;
        // On Windows the ACL must be tightened before writing secret material.
        ensure_owner_only_permissions(&temporary)?;
        serde_json::to_writer_pretty(&mut file, credential)?;
        file.write_all(b"\n")?;
        file.sync_all()?;
        drop(file);
        std::fs::rename(&temporary, &destination)?;
        #[cfg(unix)]
        File::open(directory(home))?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    result.context("Cannot save provider credential")
}

pub(super) fn remove(home: &Path, provider: ModelProvider) -> anyhow::Result<()> {
    match std::fs::remove_file(path(home, provider)) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e).context("Cannot remove provider credential"),
    }
}

/// The OS releases this advisory lock on cancellation, errors, or process exit.
/// Lock files are never unlinked, so all processes continue locking the same inode.
pub(super) async fn lock(home: &Path, provider: ModelProvider) -> anyhow::Result<File> {
    prepare_directory(home)?;
    let path = directory(home).join(format!("{}.lock", provider.as_str()));
    let file = secure_options()
        .read(true)
        .write(true)
        .create(true)
        .open(&path)?;
    ensure_owner_only_permissions(&path)?;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(45);
    loop {
        match fs2::FileExt::try_lock_exclusive(&file) {
            Ok(()) => return Ok(file),
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
            Err(e) => return Err(e).context("Cannot lock provider credential file"),
        }
        if tokio::time::Instant::now() >= deadline {
            anyhow::bail!("Timed out waiting for {provider} credential refresh lock");
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}
