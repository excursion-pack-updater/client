#![allow(non_snake_case, non_upper_case_globals)]

use std::collections::HashMap;
use std::fmt::Write as _;
use std::io::{Read as _, Write as _};
use std::path::{Path, PathBuf};
use std::process::exit;
use std::{env, fs, io};

use anyhow::{anyhow, Result as AResult};
use log::{debug, error, info, logger, warn, LevelFilter};
use reqwest::{Response, Url};
use serde::Deserialize;
use sha1::Digest;
use tokio::task::LocalSet;

const logFileName: &'static str = "epu_client.log";
const configFileName: &'static str = "epu_client.json";
const versionFileName: &'static str = "epu_pack_version.txt";

#[derive(Clone, Deserialize)]
pub struct Config {
	pub backendUrl: String,
	pub packId: String,
	pub apiKey: String,
}

#[derive(Clone, Deserialize)]
pub struct UpdateInfo {
	pub download: Vec<String>,
	pub delete: Vec<String>,
	pub hashes: HashMap<String, String>,
}

fn main() {
	#[cfg(debug_assertions)]
	if !env::vars().any(|(k, _)| k == "RUST_LOG") {
		env::set_var("RUST_LOG", "trace");
	}

	let logfile = fs::OpenOptions::new()
		.append(true)
		.create(true)
		.open(logFileName)
		.expect(&format!("Could not open log file `{logFileName}`"));
	env_logger::builder()
		.filter_level(LevelFilter::Info)
		.parse_default_env()
		.target(env_logger::fmt::Target::Pipe(Box::new(
			StderrAndFileLogger::from(logfile),
		)))
		.init();

	// delimit separate runs in the log
	info!("==============================");
	info!("EPU client started.");
	info!("Working directory: {:?}", env::current_dir().unwrap());

	let config = fs::read_to_string(configFileName).unwrap_or_else(|_| {
		error!("Could not read `{configFileName}`, aborting!");
		exit(1)
	});
	let config: Config = serde_json::from_str(&config).unwrap_or_else(|err| {
		error!("Malformed configuration file, aborting! ({err})");
		exit(1)
	});

	let rt = tokio::runtime::Builder::new_current_thread()
		.enable_io()
		.enable_time()
		.build()
		.unwrap();
	let _rtCtx = rt.enter();

	let tasks = LocalSet::new();
	if let Err(err) = rt.block_on(tasks.run_until(logic(config))) {
		error!("Unexpected error when attempting to update: {err}");
		debug!("backtrace:\n{}", err.backtrace());
		exit(2);
	}
	drop(rt);

	// drop logger and in turn flush buffered log lines, otherwise what's buffered
	// is lost. safe so long as no `'static`s do any logging in their `Drop` impls
	unsafe { Box::<dyn log::Log>::from_raw(std::mem::transmute(logger())) };
}

async fn logic(config: Config) -> AResult<()> {
	let baseUrl = format!("{}/pack/{}", config.backendUrl, config.packId);
	let client = HttpClient::new(baseUrl, config.apiKey)?;

	let localVersion = fs::read_to_string(versionFileName).ok();
	let remoteVersion = client
		.get(client.build_url(["version"]))
		.await?
		.text()
		.await?;
	if localVersion
		.map(|v| v.trim() == remoteVersion.trim())
		.unwrap_or(false)
	{
		info!("Everything up to date!");
		return Ok(());
	}
	info!("Updating to version `{remoteVersion}`");

	let UpdateInfo {
		download,
		delete,
		hashes,
	} = client
		.get(client.build_url(["changelist"]))
		.await?
		.json::<UpdateInfo>()
		.await?;

	for file in download {
		let path = make_absolute(file.as_ref());

		// skip files that may already exist, e.g. when transitioning an existing pack
		// to EPU
		if path.exists() {
			let expectedHash = hashes
				.get(&file)
				.ok_or(anyhow!(
					"Couldn't find hash for file `{file}` in download set"
				))?
				.as_str();
			let actualHash = digest_file_sha1(&path).await?;
			if actualHash.eq_ignore_ascii_case(expectedHash) {
				info!("File `{file}` already exists and hash matches -- skipping");
				continue;
			} else {
				warn!("File `{file}` already exists but its hash does not match -- overwriting");
			}
		}

		fs::create_dir_all(path.parent().ok_or(anyhow!(
			"Couldn't determine parent directory for path `{path:?}`"
		))?)?;
		client
			.download(client.build_url(["get", &file]), &path)
			.await?;
	}

	for file in delete {
		fs::remove_file(file)?;
	}

	let mut ver = remoteVersion.trim().to_owned();
	ver += "\n";
	fs::write(versionFileName, ver)?;

	Ok(())
}

async fn digest_file_sha1(file: &Path) -> AResult<String> {
	let mut file = fs::OpenOptions::new().read(true).open(file)?;

	let mut buf = [0u8; 8192];
	let mut hasher = sha1::Sha1::new();
	while let Ok(bytesRead) = file.read(&mut buf[..]) {
		if bytesRead == 0 {
			break;
		}
		let slice = &buf[0 .. bytesRead];
		hasher.update(slice);
	}

	let hash = hasher.finalize();
	let mut res = String::new();
	hash.into_iter()
		.try_for_each(|b| write!(&mut res, "{b:02X}"))?;
	Ok(res)
}

fn make_absolute(path: &Path) -> PathBuf {
	let mut full = env::current_dir().unwrap();
	full.push(path);
	full
}

struct HttpClient {
	client: reqwest::Client,
	baseUrl: Url,
	apiKey: String,
}

impl HttpClient {
	pub fn new(baseUrl: String, apiKey: String) -> AResult<Self> {
		Ok(Self {
			client: reqwest::Client::new(),
			baseUrl: Url::parse(&baseUrl)?,
			apiKey,
		})
	}

	pub fn build_url(&self, components: impl IntoIterator<Item = impl AsRef<str>>) -> Url {
		let mut res = self.baseUrl.clone();
		res.path_segments_mut().unwrap().extend(components);
		res
	}

	async fn request(&self, url: Url) -> AResult<Response> {
		Ok(self
			.client
			.get(url)
			.header("X-EPU-Key", &self.apiKey)
			.send()
			.await?
			.error_for_status()?)
	}

	pub async fn get(&self, url: Url) -> AResult<Response> {
		info!("Fetching `{url}`");
		self.request(url).await
	}

	pub async fn download(&self, url: Url, dest: &Path) -> AResult<()> {
		info!("Downloading `{url}` to `{dest:?}`");
		let resp = self.request(url).await?;
		let bytes = resp.bytes().await?;
		Ok(fs::write(dest, &bytes[..])?)
	}
}

struct StderrAndFileLogger(io::BufWriter<fs::File>);

impl From<fs::File> for StderrAndFileLogger {
	fn from(file: fs::File) -> Self {
		Self(io::BufWriter::new(file))
	}
}

impl Drop for StderrAndFileLogger {
	fn drop(&mut self) {
		self.0.flush().unwrap();
	}
}

impl io::Write for StderrAndFileLogger {
	fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
		io::stderr().write_all(bytes)?;
		self.0.write_all(bytes)?;
		Ok(bytes.len())
	}

	fn flush(&mut self) -> io::Result<()> {
		self.0.flush()
	}
}
