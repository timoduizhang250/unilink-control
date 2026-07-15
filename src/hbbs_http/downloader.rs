use super::create_http_client_async_with_url;
use hbb_common::{
    bail,
    lazy_static::lazy_static,
    log,
    tokio::{
        self,
        fs::OpenOptions,
        io::AsyncWriteExt,
        sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender},
    },
    ResultType,
};
use serde_derive::Serialize;
use std::{collections::HashMap, path::PathBuf, sync::Mutex, time::Duration};

lazy_static! {
    static ref DOWNLOADERS: Mutex<HashMap<String, Downloader>> = Default::default();
}

const MAX_DOWNLOAD_ATTEMPTS: usize = 8;

#[cfg(not(test))]
fn retry_delay(attempt: usize) -> Duration {
    Duration::from_secs((1_u64 << attempt.min(4)).min(20))
}

#[cfg(test)]
fn retry_delay(_attempt: usize) -> Duration {
    Duration::from_millis(50)
}

fn parse_content_range(value: &str) -> Option<(u64, u64)> {
    let value = value.strip_prefix("bytes ")?;
    let (range, total) = value.split_once('/')?;
    let (start, _) = range.split_once('-')?;
    Some((start.parse().ok()?, total.parse().ok()?))
}

fn response_total_size(response: &reqwest::Response, offset: u64) -> Option<u64> {
    if response.status() == reqwest::StatusCode::PARTIAL_CONTENT {
        let value = response
            .headers()
            .get(reqwest::header::CONTENT_RANGE)?
            .to_str()
            .ok()?;
        let (start, total) = parse_content_range(value)?;
        (start == offset).then_some(total)
    } else {
        response.content_length()
    }
}

/// This struct is used to return the download data to the caller.
/// The caller should check if the file is downloaded successfully and remove the job from the map.
/// If the file is not downloaded successfully, the `data` field will be empty.
/// If the file is downloaded successfully, the `data` field will contain the downloaded data if `path` is None.
#[derive(Serialize, Debug)]
pub struct DownloadData {
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub data: Vec<u8>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<PathBuf>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub total_size: Option<u64>,
    pub downloaded_size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

struct Downloader {
    data: Vec<u8>,
    path: Option<PathBuf>,
    // Some file may be empty, so we use Option<u64> to indicate if the size is known
    total_size: Option<u64>,
    downloaded_size: u64,
    error: Option<String>,
    finished: bool,
    tx_cancel: UnboundedSender<()>,
}

// The caller should check if the file is downloaded successfully and remove the job from the map.
pub fn download_file(
    url: String,
    path: Option<PathBuf>,
    auto_del_dur: Option<Duration>,
) -> ResultType<String> {
    let id = url.clone();
    // First pass: if a non-error downloader exists for this URL, reuse it.
    // If an errored downloader exists, remove it so this call can retry.
    let mut stale_path = None;
    {
        let mut downloaders = DOWNLOADERS.lock().unwrap();
        if let Some(downloader) = downloaders.get(&id) {
            if downloader.error.is_none() {
                return Ok(id);
            }
            stale_path = downloader.path.clone();
            downloaders.remove(&id);
        }
    }
    if let Some(p) = stale_path {
        if p.exists() {
            if let Err(e) = std::fs::remove_file(&p) {
                log::warn!(
                    "Failed to remove stale download file {}: {}",
                    p.display(),
                    e
                );
            }
        }
    }

    if let Some(path) = path.as_ref() {
        if path.exists() {
            bail!("File {} already exists", path.display());
        }
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
    }
    let (tx, rx) = unbounded_channel();
    let downloader = Downloader {
        data: Vec::new(),
        path: path.clone(),
        total_size: None,
        downloaded_size: 0,
        error: None,
        tx_cancel: tx,
        finished: false,
    };
    // Second pass (atomic with insert) to avoid race with another concurrent caller.
    let mut stale_path_after_check = None;
    {
        let mut downloaders = DOWNLOADERS.lock().unwrap();
        if let Some(existing) = downloaders.get(&id) {
            if existing.error.is_none() {
                return Ok(id);
            }
            stale_path_after_check = existing.path.clone();
            downloaders.remove(&id);
        }
        downloaders.insert(id.clone(), downloader);
    }
    if let Some(p) = stale_path_after_check {
        if p.exists() {
            if let Err(e) = std::fs::remove_file(&p) {
                log::warn!(
                    "Failed to remove stale download file {}: {}",
                    p.display(),
                    e
                );
            }
        }
    }

    let id2 = id.clone();
    std::thread::spawn(
        move || match do_download(&id2, url, path, auto_del_dur, rx) {
            Ok(is_all_downloaded) => {
                let mut downloaded_size = 0;
                let mut total_size = 0;
                DOWNLOADERS.lock().unwrap().get_mut(&id2).map(|downloader| {
                    downloaded_size = downloader.downloaded_size;
                    total_size = downloader.total_size.unwrap_or(0);
                });
                log::info!(
                    "Download {} end, {}/{}, {:.2} %",
                    &id2,
                    downloaded_size,
                    total_size,
                    if total_size == 0 {
                        0.0
                    } else {
                        downloaded_size as f64 / total_size as f64 * 100.0
                    }
                );

                let is_canceled = !is_all_downloaded;
                if is_canceled {
                    if let Some(downloader) = DOWNLOADERS.lock().unwrap().remove(&id2) {
                        if let Some(p) = downloader.path {
                            if p.exists() {
                                std::fs::remove_file(p).ok();
                            }
                        }
                    }
                }
            }
            Err(e) => {
                let err = e.to_string();
                log::error!("Download {}, failed: {}", &id2, &err);
                DOWNLOADERS.lock().unwrap().get_mut(&id2).map(|downloader| {
                    downloader.error = Some(err);
                });
            }
        },
    );

    Ok(id)
}

#[tokio::main(flavor = "current_thread")]
async fn do_download(
    id: &str,
    url: String,
    path: Option<PathBuf>,
    auto_del_dur: Option<Duration>,
    mut rx_cancel: UnboundedReceiver<()>,
) -> ResultType<bool> {
    let mut downloaded_size = 0_u64;
    let mut last_error = "download did not start".to_owned();

    for attempt in 0..MAX_DOWNLOAD_ATTEMPTS {
        if attempt > 0 {
            let delay = retry_delay(attempt - 1);
            log::warn!(
                "Retrying download {} from byte {} in {:?} (attempt {}/{})",
                id,
                downloaded_size,
                delay,
                attempt + 1,
                MAX_DOWNLOAD_ATTEMPTS
            );
            tokio::select! {
                _ = rx_cancel.recv() => return Ok(false),
                _ = tokio::time::sleep(delay) => {}
            }
        }

        let client = tokio::select! {
            _ = rx_cancel.recv() => return Ok(false),
            client = create_http_client_async_with_url(&url) => client,
        };
        let mut request = client.get(&url);
        if downloaded_size > 0 {
            request = request.header(reqwest::header::RANGE, format!("bytes={downloaded_size}-"));
        }
        let response = tokio::select! {
            _ = rx_cancel.recv() => return Ok(false),
            response = request.send() => response,
        };
        let mut response = match response {
            Ok(response) => response,
            Err(error) => {
                last_error = error.to_string();
                log::warn!(
                    "Download request {} failed on attempt {}/{}: {}",
                    id,
                    attempt + 1,
                    MAX_DOWNLOAD_ATTEMPTS,
                    last_error
                );
                continue;
            }
        };
        if !response.status().is_success() {
            bail!("Failed to download file: {}", response.status());
        }

        let append =
            downloaded_size > 0 && response.status() == reqwest::StatusCode::PARTIAL_CONTENT;
        let Some(response_total) = response_total_size(&response, downloaded_size) else {
            last_error = "Download response has no valid total size".to_owned();
            continue;
        };
        let total_size = Some(response_total);

        if downloaded_size > 0 && !append {
            log::warn!(
                "Server ignored the range request for {}, restarting from byte 0",
                id
            );
            downloaded_size = 0;
            if path.is_none() {
                if let Some(downloader) = DOWNLOADERS.lock().unwrap().get_mut(id) {
                    downloader.data.clear();
                    downloader.downloaded_size = 0;
                }
            }
        }
        if let Some(downloader) = DOWNLOADERS.lock().unwrap().get_mut(id) {
            downloader.total_size = total_size;
            downloader.downloaded_size = downloaded_size;
        }

        let mut dest = if let Some(path) = path.as_ref() {
            let mut options = OpenOptions::new();
            options.create(true).write(true);
            if append {
                options.append(true);
            } else {
                options.truncate(true);
            }
            Some(options.open(path).await?)
        } else {
            None
        };

        let mut stream_error = None;
        loop {
            let chunk = tokio::select! {
                _ = rx_cancel.recv() => return Ok(false),
                chunk = response.chunk() => chunk,
            };
            match chunk {
                Ok(Some(chunk)) => {
                    if let Some(file) = dest.as_mut() {
                        file.write_all(&chunk).await?;
                    }
                    downloaded_size += chunk.len() as u64;
                    if let Some(downloader) = DOWNLOADERS.lock().unwrap().get_mut(id) {
                        if path.is_none() {
                            downloader.data.extend_from_slice(&chunk);
                        }
                        downloader.downloaded_size = downloaded_size;
                    }
                }
                Ok(None) => break,
                Err(error) => {
                    stream_error = Some(error.to_string());
                    break;
                }
            }
        }
        if let Some(file) = dest.as_mut() {
            file.flush().await?;
        }

        if let Some(error) = stream_error {
            last_error = error;
            log::warn!(
                "Download stream {} stopped at byte {} on attempt {}/{}: {}",
                id,
                downloaded_size,
                attempt + 1,
                MAX_DOWNLOAD_ATTEMPTS,
                last_error
            );
            continue;
        }
        if Some(downloaded_size) == total_size {
            if let Some(downloader) = DOWNLOADERS.lock().unwrap().get_mut(id) {
                downloader.finished = true;
            }
            let id_del = id.to_string();
            if let Some(dur) = auto_del_dur {
                tokio::spawn(async move {
                    tokio::time::sleep(dur).await;
                    DOWNLOADERS.lock().unwrap().remove(&id_del);
                });
            }
            return Ok(true);
        }
        last_error = format!(
            "Download ended at byte {} of {}",
            downloaded_size,
            total_size.unwrap_or_default()
        );
    }

    bail!(
        "Download failed after {} attempts: {}",
        MAX_DOWNLOAD_ATTEMPTS,
        last_error
    )
}

pub fn get_download_data(id: &str) -> ResultType<DownloadData> {
    let downloaders = DOWNLOADERS.lock().unwrap();
    if let Some(downloader) = downloaders.get(id) {
        // Do not let polling clients launch the installer before the final
        // file flush and response-completion checks have finished.
        let downloaded_size = if !downloader.finished
            && downloader.total_size == Some(downloader.downloaded_size)
            && downloader.downloaded_size > 0
        {
            downloader.downloaded_size - 1
        } else {
            downloader.downloaded_size
        };
        let total_size = downloader.total_size.clone();
        let error = downloader.error.clone();
        let data = if total_size.unwrap_or(0) == downloaded_size && downloader.path.is_none() {
            downloader.data.clone()
        } else {
            Vec::new()
        };
        let path = downloader.path.clone();
        let download_data = DownloadData {
            data,
            path,
            total_size,
            downloaded_size,
            error,
        };
        Ok(download_data)
    } else {
        bail!("Downloader not found")
    }
}

pub fn cancel(id: &str) {
    if let Some(downloader) = DOWNLOADERS.lock().unwrap().get(id) {
        // downloader.is_canceled.store(true, Ordering::SeqCst);
        // The receiver may not be able to receive the cancel signal, so we also set the atomic bool to true
        let _ = downloader.tx_cancel.send(());
    }
}

pub fn remove(id: &str) {
    let _ = DOWNLOADERS.lock().unwrap().remove(id);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        thread,
        time::{Instant, SystemTime, UNIX_EPOCH},
    };

    #[test]
    fn parses_content_range_total() {
        assert_eq!(
            parse_content_range("bytes 1024-2047/4096"),
            Some((1024, 4096))
        );
        assert_eq!(parse_content_range("bytes */4096"), None);
        assert_eq!(parse_content_range("invalid"), None);
    }

    #[test]
    fn resumes_a_file_after_the_server_drops_the_first_response() {
        let payload: Vec<u8> = (0..(128 * 1024)).map(|index| (index % 251) as u8).collect();
        let split_at = payload.len() / 2;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let address = listener.local_addr().unwrap();
        let server_payload = payload.clone();
        let server = thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(10);
            let mut sent_partial_response = false;
            while Instant::now() < deadline {
                let (mut stream, _) = match listener.accept() {
                    Ok(value) => value,
                    Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10));
                        continue;
                    }
                    Err(error) => panic!("test server accept failed: {error}"),
                };
                stream
                    .set_read_timeout(Some(Duration::from_secs(2)))
                    .unwrap();
                let mut request = Vec::new();
                let mut buffer = [0_u8; 2048];
                while !request.windows(4).any(|value| value == b"\r\n\r\n") {
                    let read = stream.read(&mut buffer).unwrap();
                    if read == 0 {
                        break;
                    }
                    request.extend_from_slice(&buffer[..read]);
                }
                let request = String::from_utf8_lossy(&request);
                if request.starts_with("HEAD ") {
                    write!(
                        stream,
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        server_payload.len()
                    )
                    .unwrap();
                    continue;
                }

                let range_start = request.lines().find_map(|line| {
                    line.strip_prefix("Range: bytes=")
                        .or_else(|| line.strip_prefix("range: bytes="))
                        .and_then(|value| value.split('-').next())
                        .and_then(|value| value.parse::<usize>().ok())
                });
                if !sent_partial_response && range_start.is_none() {
                    write!(
                        stream,
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                        server_payload.len()
                    )
                    .unwrap();
                    stream.write_all(&server_payload[..split_at]).unwrap();
                    stream.flush().unwrap();
                    sent_partial_response = true;
                    continue;
                }

                let start = range_start.expect("resumed request did not include a Range header");
                write!(
                    stream,
                    "HTTP/1.1 206 Partial Content\r\nContent-Length: {}\r\nContent-Range: bytes {}-{}/{}\r\nConnection: close\r\n\r\n",
                    server_payload.len() - start,
                    start,
                    server_payload.len() - 1,
                    server_payload.len()
                )
                .unwrap();
                stream.write_all(&server_payload[start..]).unwrap();
                stream.flush().unwrap();
                return;
            }
            panic!("test server timed out before receiving the resumed request");
        });

        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "unilink-downloader-resume-{}-{unique}.bin",
            std::process::id()
        ));
        std::fs::remove_file(&path).ok();
        let url = format!("http://{address}/update.bin");
        let id = download_file(url, Some(path.clone()), None).unwrap();
        let deadline = Instant::now() + Duration::from_secs(15);
        loop {
            let data = get_download_data(&id).unwrap();
            if let Some(error) = data.error {
                panic!("download failed instead of resuming: {error}");
            }
            if data.total_size == Some(payload.len() as u64)
                && data.downloaded_size == payload.len() as u64
            {
                break;
            }
            assert!(Instant::now() < deadline, "resumed download timed out");
            thread::sleep(Duration::from_millis(25));
        }

        assert_eq!(std::fs::read(&path).unwrap(), payload);
        remove(&id);
        std::fs::remove_file(path).unwrap();
        server.join().unwrap();
    }
}
