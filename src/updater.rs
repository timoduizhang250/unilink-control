use crate::{common::do_check_software_update, hbbs_http::downloader};
use hbb_common::{
    bail, config, log,
    sha2::{Digest, Sha256},
    ResultType,
};
use std::{
    io::Read,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{channel, Receiver, Sender},
        Mutex,
    },
    time::{Duration, Instant},
};

enum UpdateMsg {
    CheckUpdate,
    Exit,
}

lazy_static::lazy_static! {
    static ref TX_MSG : Mutex<Sender<UpdateMsg>> = Mutex::new(start_auto_update_check());
}

static CONTROLLING_SESSION_COUNT: AtomicUsize = AtomicUsize::new(0);

const DUR_ONE_DAY: Duration = Duration::from_secs(60 * 60 * 24);

pub fn update_controlling_session_count(count: usize) {
    CONTROLLING_SESSION_COUNT.store(count, Ordering::SeqCst);
}

#[allow(dead_code)]
pub fn start_auto_update() {
    let _sender = TX_MSG.lock().unwrap();
}

#[allow(dead_code)]
pub fn manually_check_update() -> ResultType<()> {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::CheckUpdate)?;
    Ok(())
}

#[allow(dead_code)]
pub fn stop_auto_update() {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::Exit).unwrap_or_default();
}

#[inline]
fn has_no_active_conns() -> bool {
    let conns = crate::Connection::alive_conns();
    conns.is_empty() && has_no_controlling_conns()
}

fn allow_auto_update() -> bool {
    let key = config::keys::OPTION_ALLOW_AUTO_UPDATE;
    let value = config::Config::get_option(key);
    let is_unilink = crate::common::get_app_name()
        .to_lowercase()
        .contains("unilink");
    if is_unilink {
        // UniLink should default to auto-update unless the user explicitly turns it off.
        value.is_empty() || value == "Y"
    } else {
        config::option2bool(key, &value)
    }
}

#[cfg(any(not(target_os = "windows"), feature = "flutter"))]
fn has_no_controlling_conns() -> bool {
    CONTROLLING_SESSION_COUNT.load(Ordering::SeqCst) == 0
}

#[cfg(not(any(not(target_os = "windows"), feature = "flutter")))]
fn has_no_controlling_conns() -> bool {
    let app_exe = format!("{}.exe", crate::get_app_name().to_lowercase());
    for arg in [
        "--connect",
        "--play",
        "--file-transfer",
        "--view-camera",
        "--port-forward",
        "--rdp",
    ] {
        if !crate::platform::get_pids_of_process_with_first_arg(&app_exe, arg).is_empty() {
            return false;
        }
    }
    true
}

fn start_auto_update_check() -> Sender<UpdateMsg> {
    let (tx, rx) = channel();
    std::thread::spawn(move || start_auto_update_check_(rx));
    return tx;
}

fn start_auto_update_check_(rx_msg: Receiver<UpdateMsg>) {
    const MIN_INTERVAL: Duration = Duration::from_secs(60 * 10);
    const RETRY_INTERVAL: Duration = Duration::from_secs(60 * 30);

    std::thread::sleep(Duration::from_secs(30));
    let initial_failed = if let Err(e) = check_update(false) {
        log::error!("Error checking for updates: {}", e);
        true
    } else {
        false
    };
    let mut last_check_time = Instant::now();
    let mut check_interval = if initial_failed {
        RETRY_INTERVAL
    } else {
        DUR_ONE_DAY
    };
    loop {
        let recv_res = rx_msg.recv_timeout(check_interval);
        match &recv_res {
            Ok(UpdateMsg::CheckUpdate) | Err(_) => {
                let manually = matches!(&recv_res, Ok(UpdateMsg::CheckUpdate));
                if !manually && last_check_time.elapsed() < MIN_INTERVAL {
                    // log::debug!("Update check skipped due to minimum interval.");
                    continue;
                }
                // Don't check update if there are alive connections.
                if !has_no_active_conns() {
                    check_interval = RETRY_INTERVAL;
                    continue;
                }
                if let Err(e) = check_update(manually) {
                    log::error!("Error checking for updates: {}", e);
                    check_interval = RETRY_INTERVAL;
                } else {
                    last_check_time = Instant::now();
                    check_interval = DUR_ONE_DAY;
                }
            }
            Ok(UpdateMsg::Exit) => break,
        }
    }
}

fn expected_update_sha256() -> String {
    crate::common::SOFTWARE_UPDATE_SHA256
        .lock()
        .unwrap()
        .clone()
}

pub fn verify_downloaded_update(path: &Path) -> ResultType<()> {
    let expected = expected_update_sha256();
    if expected.is_empty() {
        return Ok(());
    }

    let actual = downloaded_update_sha256(path)?;
    if actual != expected {
        bail!(
            "Downloaded update checksum mismatch: expected {}, got {}",
            expected,
            actual
        );
    }
    Ok(())
}

fn downloaded_update_sha256(path: &Path) -> ResultType<String> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

fn download_update_file(download_url: &str, file_path: &Path) -> ResultType<()> {
    if file_path.exists() {
        if !expected_update_sha256().is_empty() && verify_downloaded_update(file_path).is_ok() {
            return Ok(());
        }
        std::fs::remove_file(file_path)?;
    }

    let id =
        downloader::download_file(download_url.to_owned(), Some(file_path.to_path_buf()), None)?;
    loop {
        let data = downloader::get_download_data(&id)?;
        if let Some(error) = data.error {
            downloader::remove(&id);
            std::fs::remove_file(file_path).ok();
            bail!("{}", error);
        }
        if let Some(total_size) = data.total_size {
            if total_size == data.downloaded_size {
                downloader::remove(&id);
                if let Err(error) = verify_downloaded_update(file_path) {
                    std::fs::remove_file(file_path).ok();
                    return Err(error);
                }
                return Ok(());
            }
        }
        std::thread::sleep(Duration::from_millis(250));
    }
}

fn check_update(manually: bool) -> ResultType<()> {
    #[cfg(target_os = "windows")]
    let update_msi = crate::platform::is_msi_installed()? && !crate::is_custom_client();
    if !(manually || allow_auto_update()) {
        log::debug!(
            "Skipping software update check: manual={manually}, allow_auto_update={}, app={}",
            allow_auto_update(),
            crate::common::get_app_name(),
        );
        return Ok(());
    }
    if let Err(error) = do_check_software_update() {
        if crate::common::get_app_name()
            .to_lowercase()
            .contains("unilink")
        {
            return Err(error);
        }
        return Ok(());
    }

    let update_url = crate::common::SOFTWARE_UPDATE_URL.lock().unwrap().clone();
    if update_url.is_empty() {
        log::debug!("No update available.");
    } else {
        let direct_download_url = crate::common::SOFTWARE_UPDATE_DOWNLOAD_URL
            .lock()
            .unwrap()
            .clone();
        let version = update_url.rsplit('/').next().unwrap_or_default();
        let download_url = if direct_download_url.is_empty() {
            update_url.replace("tag", "download")
        } else {
            direct_download_url
        };
        #[cfg(target_os = "windows")]
        let download_url = if !crate::common::SOFTWARE_UPDATE_DOWNLOAD_URL
            .lock()
            .unwrap()
            .is_empty()
        {
            download_url
        } else if cfg!(feature = "flutter") {
            let Some(arch) = crate::platform::windows::release_arch_suffix() else {
                bail!(
                    "Unsupported Windows release architecture: {}",
                    std::env::consts::ARCH
                );
            };
            format!(
                "{}/rustdesk-{}-{}.{}",
                download_url,
                version,
                arch,
                if update_msi { "msi" } else { "exe" }
            )
        } else {
            format!("{}/rustdesk-{}-x86-sciter.exe", download_url, version)
        };
        log::debug!("New version available: {}", &version);
        let Some(file_path) = get_download_file_from_url(&download_url) else {
            bail!("Failed to get the file path from the URL: {}", download_url);
        };
        download_update_file(&download_url, &file_path)?;
        // We have checked if the `conns` is empty before, but we need to check again.
        // No need to care about the downloaded file here, because it's rare case that the `conns` are empty
        // before the download, but not empty after the download.
        if has_no_active_conns() {
            #[cfg(target_os = "windows")]
            update_new_version(update_msi, &version, &file_path);
        }
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn update_new_version(update_msi: bool, version: &str, file_path: &PathBuf) {
    log::debug!(
        "New version is downloaded, update begin, update msi: {update_msi}, version: {version}, file: {:?}",
        file_path.to_str()
    );
    if let Some(p) = file_path.to_str() {
        if let Some(session_id) = crate::platform::get_current_process_session_id() {
            if update_msi {
                match crate::platform::update_me_msi(p, true) {
                    Ok(_) => {
                        log::debug!("New version \"{}\" updated.", version);
                    }
                    Err(e) => {
                        log::error!(
                            "Failed to install the new msi version  \"{}\": {}",
                            version,
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                    }
                }
            } else {
                let custom_client_staging_dir = if crate::is_custom_client() {
                    let custom_client_staging_dir =
                        crate::platform::get_custom_client_staging_dir();
                    if let Err(e) = crate::platform::handle_custom_client_staging_dir_before_update(
                        &custom_client_staging_dir,
                    ) {
                        log::error!(
                            "Failed to handle custom client staging dir before update: {}",
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                        return;
                    }
                    Some(custom_client_staging_dir)
                } else {
                    // Clean up any residual staging directory from previous custom client
                    let staging_dir = crate::platform::get_custom_client_staging_dir();
                    hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                        &staging_dir
                    ));
                    None
                };
                let update_launched = match crate::platform::launch_privileged_process(
                    session_id,
                    &format!("{} --update", p),
                ) {
                    Ok(h) => {
                        if h.is_null() {
                            log::error!("Failed to update to the new version: {}", version);
                            false
                        } else {
                            log::debug!("New version \"{}\" is launched.", version);
                            true
                        }
                    }
                    Err(e) => {
                        log::error!("Failed to run the new version: {}", e);
                        false
                    }
                };
                if !update_launched {
                    if let Some(dir) = custom_client_staging_dir {
                        hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                            &dir
                        ));
                    }
                    std::fs::remove_file(&file_path).ok();
                }
            }
        } else {
            log::error!(
                "Failed to get the current process session id, Error {}",
                std::io::Error::last_os_error()
            );
            std::fs::remove_file(&file_path).ok();
        }
    } else {
        // unreachable!()
        log::error!(
            "Failed to convert the file path to string: {}",
            file_path.display()
        );
    }
}

pub fn get_download_file_from_url(url: &str) -> Option<PathBuf> {
    let filename = url.split('/').last()?;
    Some(std::env::temp_dir().join(filename))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn calculates_downloaded_update_sha256() {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "unilink-update-sha-{}-{unique}.bin",
            std::process::id()
        ));
        std::fs::write(&path, b"abc").unwrap();
        assert_eq!(
            downloaded_update_sha256(&path).unwrap(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        std::fs::remove_file(path).unwrap();
    }
}
