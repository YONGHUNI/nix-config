//! On-demand hotspot supervisor. No external Rust dependencies.
use std::{env, fs, io::{self, BufRead, BufReader, Read, Write}, net::Ipv4Addr,
    os::unix::fs::{OpenOptionsExt, PermissionsExt}, path::{Path, PathBuf},
    process::{Child, Command, Stdio}, sync::mpsc, thread, time::{Duration, Instant}};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
const AP: &str = "ipad-ap";
const RUN: &str = "/run/ipad-hotspot";
const STATE: &str = "/var/lib/ipad-hotspot";
const TABLE: &str = "ipad_display";
const AP_COOLDOWN_MS: u64 = 5_000;
const AP_ATTEMPTS_PER_WIDTH: u32 = 3;
const AP_RETRY_DELAY: Duration = Duration::from_secs(2);
fn err(s: &str) -> Box<dyn std::error::Error> { io::Error::other(s.to_owned()).into() }
fn path(s: &str) -> PathBuf { Path::new(RUN).join(s) }
fn run(args: &[&str]) -> Result<String> {
    let o = Command::new(args[0]).args(&args[1..]).output()?;
    if !o.status.success() { return Err(err(&format!("{} failed: {}", args[0], String::from_utf8_lossy(&o.stderr).trim()))); }
    Ok(String::from_utf8(o.stdout)?)
}
fn ok(args: &[&str]) -> bool { run(args).is_ok() }
fn write(path: &Path, value: &str, mode: u32) -> Result<()> {
    let mut f = fs::OpenOptions::new().write(true).create(true).truncate(true).mode(mode).open(path)?;
    f.set_permissions(fs::Permissions::from_mode(mode))?;
    f.write_all(value.as_bytes())?;
    Ok(())
}
fn mark(s: &str) -> Result<()> { write(&path(s), "", 0o600) }
fn remove(s: &str) { let _ = fs::remove_file(path(s)); }
fn sysctl(iface: &str, key: &str) -> PathBuf {
    Path::new("/proc/sys/net/ipv4/conf").join(iface).join(key)
}
fn set_forward(iface: &str, v: &str) -> Result<()> {
    fs::write(sysctl(iface, "forwarding"), v)?;
    Ok(())
}
fn ap_exists() -> bool { Path::new("/sys/class/net").join(AP).exists() }
fn boot_millis() -> Result<u64> {
    let uptime = fs::read_to_string("/proc/uptime")?;
    let seconds: f64 = uptime.split_whitespace().next().ok_or_else(|| err("Missing uptime"))?.parse()?;
    Ok(u64::try_from(Duration::try_from_secs_f64(seconds)?.as_millis())?)
}
fn cooldown_remaining(now: u64, last: u64) -> Duration {
    Duration::from_millis(AP_COOLDOWN_MS.saturating_sub(now.saturating_sub(last)))
}
fn wait_ap_cooldown() -> Result<()> {
    let last = match fs::read_to_string(path("last-ap-stop-ms")) {
        Ok(value) => value.trim().parse::<u64>()?,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(e) => return Err(e.into()),
    };
    let delay = cooldown_remaining(boot_millis()?, last);
    if !delay.is_zero() {
        eprintln!("AP restart cooldown: {} ms", delay.as_millis());
        thread::sleep(delay);
    }
    Ok(())
}
fn element(set: &str, iface: &str) -> Result<()> {
    run(&["nft","add","element","inet",TABLE,set,"{", &format!("\"{iface}\""), "}"])?;
    Ok(())
}
fn clear(set: &str) -> Result<()> {
    run(&["nft","flush","set","inet",TABLE,set])?;
    Ok(())
}
struct Config { wifi: String, ssid: String, host: String, client: String }
impl Config {
    fn read() -> Result<Self> {
        let wifi = env::var("IPAD_UPSTREAM")?;
        let ssid = env::var("IPAD_SSID")?;
        let prefix = env::var("IPAD_PREFIX")?;
        if wifi.is_empty() || wifi == AP || !wifi.bytes().all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
            || ssid.is_empty() || ssid.len() > 32 || !ssid.bytes().all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b)) {
            return Err(err("Invalid interface or SSID"));
        }
        let host = format!("{prefix}.1").parse::<Ipv4Addr>()?.to_string();
        let client = format!("{prefix}.2").parse::<Ipv4Addr>()?.to_string();
        Ok(Self { wifi, ssid, host, client })
    }
}
fn route_overlap(line: &str, host: Ipv4Addr) -> bool {
    let fields: Vec<&str> = line.split_whitespace().collect();
    if fields.windows(2).any(|w| w == ["dev", AP]) { return false; }
    let Some(first) = fields.first() else { return false };
    let dst = if ["local","broadcast","unreachable","blackhole","prohibit","throw","nat","multicast","unicast","anycast"].contains(first) {
        fields.get(1).copied().unwrap_or("")
    } else { first };
    let (address, bits) = dst.split_once('/').unwrap_or((dst, "32"));
    let (Ok(addr), Ok(bits)) = (address.parse::<Ipv4Addr>(), bits.parse::<u32>()) else { return false };
    if !(2..=32).contains(&bits) { return false; } // ignore default / split-default
    let mask = u32::MAX << (32 - bits.min(24));
    u32::from(addr) & mask == u32::from(host) & mask
}
fn check_routes(c: &Config) -> Result<()> {
    let host = c.host.parse()?;
    for line in run(&["ip","-4","route","show","table","all"])?.lines() {
        if route_overlap(line, host) { return Err(err(&format!("Hotspot subnet overlaps route: {line}"))); }
    }
    Ok(())
}
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
struct Channel { number: u32, freq: u32, width: u32, center: u32 }
fn parse_channel(info: &str) -> Result<Channel> {
    let line = info.lines().find(|l| l.trim_start().starts_with("channel ")).ok_or_else(|| err("No active Wi-Fi channel"))?;
    let words: Vec<_> = line.split(|c: char| c.is_whitespace() || "(),:".contains(c)).filter(|s| !s.is_empty()).collect();
    let get = |key: &str| -> Result<u32> {
        Ok(words.iter().position(|w| *w == key).and_then(|i| words.get(i+1)).ok_or_else(|| err("Incomplete channel information"))?.parse()?)
    };
    Ok(Channel { number: get("channel")?, freq: words.get(2).ok_or_else(|| err("Missing frequency"))?.parse()?, width: get("width")?, center: get("center1")? })
}
fn channel(c: &Config) -> Result<Channel> {
    if !run(&["iw","dev",&c.wifi,"link"])?.contains("Connected to ") { return Err(err("Connect Gram to Wi-Fi first.")); }
    parse_channel(&run(&["iw","dev",&c.wifi,"info"])?)
}
fn variants(ch: Channel) -> Result<Vec<String>> {
    let mut v = Vec::new();
    if (5000..5900).contains(&ch.freq) {
        if let Some(start) = [36,52,100,116,132,149].into_iter().find(|s| (0..4).any(|i| *s+4*i == ch.number)) {
            let side = if (ch.number-start)%8 == 0 { "+" } else { "-" };
            if ch.width >= 80 { v.push(format!("ieee80211ac=1\nht_capab=[HT40{side}]\nvht_oper_chwidth=1\nvht_oper_centr_freq_seg0_idx={}\n",start+6)); }
            if ch.width >= 40 { v.push(format!("ht_capab=[HT40{side}]\n")); }
        }
    } else if !(2400..2500).contains(&ch.freq) || ch.number == 14 { return Err(err("Unsupported Wi-Fi channel")); }
    v.push(String::new());
    Ok(v)
}
fn password() -> Result<String> {
    let p = Path::new(STATE).join("password");
    if !p.exists() {
        let mut bytes = [0u8;12];
        fs::File::open("/dev/urandom")?.read_exact(&mut bytes)?;
        let secret: String = bytes.iter().map(|x| format!("{x:02x}")).collect();
        write(&p, &secret, 0o600)?;
    }
    let s = fs::read_to_string(p)?.trim().to_owned();
    if s.len()!=24 || !s.bytes().all(|b| b.is_ascii_hexdigit()) { return Err(err("Invalid stored password")); }
    Ok(s)
}
fn stop_child(child: &mut Child) {
    if matches!(child.try_wait(), Ok(Some(_))) { return; }
    let _ = run(&["kill","-TERM",&child.id().to_string()]);
    for _ in 0..15 {
        if matches!(child.try_wait(), Ok(Some(_))) { return; }
        thread::sleep(Duration::from_millis(100));
    }
    let _ = child.kill(); let _ = child.wait();
}
fn spawn(args: &[&str]) -> Result<Child> {
    Ok(Command::new(args[0]).args(&args[1..]).stdin(Stdio::null()).spawn()?)
}
fn hostapd(c: &Config, ch: Channel, secret: &str) -> Result<Child> {
    let control = path("ctrl");
    fs::create_dir_all(&control)?;
    let conf = path("hostapd.conf");
    let mut first = true;
    for extra in variants(ch)? {
        let width = if extra.contains("vht_oper_chwidth=1") { 80 }
            else if extra.contains("HT40") { 40 } else { 20 };
        let hw = if ch.freq >= 5000 { "a" } else { "g" };
        let text = format!("interface={AP}\ndriver=nl80211\nssid={}\nhw_mode={hw}\nchannel={}\nieee80211n=1\nwmm_enabled=1\nwpa=2\nwpa_key_mgmt=WPA-PSK\nrsn_pairwise=CCMP\nwpa_passphrase={secret}\nctrl_interface={RUN}/ctrl\nctrl_interface_group=0\nmax_num_sta=1\n{extra}",c.ssid,ch.number);
        write(&conf,&text,0o600)?;
        for attempt in 1..=AP_ATTEMPTS_PER_WIDTH {
            if !first {
                thread::sleep(AP_RETRY_DELAY);
                if let Err(e) = run(&["ip","link","set",AP,"down"])
                    .and_then(|_| run(&["iw","dev",AP,"set","type","__ap"])) {
                    eprintln!("AP {width} MHz attempt {attempt}: interface preparation failed: {e}");
                    continue;
                }
            }
            first = false;
            if channel(c)? != ch { return Err(err("Upstream channel changed during AP startup")); }
            eprintln!("AP {width} MHz attempt {attempt}/{AP_ATTEMPTS_PER_WIDTH}");
            let mut child = spawn(&["hostapd",conf.to_str().unwrap()])?;
            for _ in 0..30 {
                if child.try_wait()?.is_some() { break; }
                if run(&["hostapd_cli","-p",control.to_str().unwrap(),"-i",AP,"status"]).is_ok_and(|s| s.lines().any(|l| l=="state=ENABLED")) {
                    eprintln!("AP enabled with requested {width} MHz configuration");
                    return Ok(child);
                }
                thread::sleep(Duration::from_millis(200));
            }
            stop_child(&mut child);
            eprintln!("AP {width} MHz attempt {attempt} failed");
        }
    }
    Err(err("AP failed on this channel; use Existing Wi-Fi"))
}
fn local_session() -> Result<bool> {
    for line in run(&["loginctl","list-sessions","--no-legend","--no-pager"])?.lines() {
        let Some(id) = line.split_whitespace().next() else { continue };
        let p = run(&["loginctl","show-session",id,"-p","Type","-p","Remote","-p","State","-p","Class"]).unwrap_or_default();
        if (p.contains("Type=wayland") || p.contains("Type=x11")) && p.contains("Remote=no") &&
            p.lines().any(|l| l=="Class=user" || l=="Class=user-early") && !p.contains("State=closing") { return Ok(true); }
    }
    Ok(false)
}
fn guard_ok(shared: bool, legacy: Option<&str>) -> Result<()> {
    run(&["nft","list","chain","inet",TABLE,"input"])?;
    run(&["nft","list","chain","inet",TABLE,"output"])?;
    run(&["nft","list","chain","inet",TABLE,"forward"])?;
    run(&["nft","list","chain","inet",TABLE,"nat"])?;
    let s = run(&["nft","list","set","inet",TABLE,"shared"])?;
    if s.contains(&format!("\"{AP}\"")) != shared { return Err(err("Firewall sharing state changed")); }
    let lan = run(&["nft","list","set","inet",TABLE,"legacy"])?;
    // nft omits the elements field when a set is empty.
    let present = lan.lines().any(|l| l.trim_start().starts_with("elements ="));
    match legacy {
        Some(iface) if present && lan.contains(&format!("\"{iface}\"")) => (),
        None if !present => (),
        _ => return Err(err("Legacy streaming policy changed")),
    }
    Ok(())
}
fn json(s: &str) -> String {
    let mut out = String::from("\"");
    for ch in s.chars() {
        match ch { '"' => out.push_str("\\\""), '\\' => out.push_str("\\\\"), '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"), '\t' => out.push_str("\\t"),
            c if c.is_control() => out.push_str(&format!("\\u{:04x}",c as u32)), c => out.push(c) }
    }
    out.push('"'); out
}
fn report(c: &Config, shared: bool) -> Result<()> {
    let info = run(&["iw","dev",AP,"info"])?;
    let line = info.lines().find(|l| l.trim_start().starts_with("channel ")).unwrap_or("").trim();
    let route = run(&["ip","-4","route","get","1.1.1.1","from",&c.client,"iif",AP]).unwrap_or_default();
    let available = route.split_whitespace().collect::<Vec<_>>().windows(2).any(|w| w[0]=="dev" && w[1]==c.wifi.as_str());
    let stations = run(&["iw","dev",AP,"station","dump"])?.lines().filter(|l| l.trim_start()=="authorized:\tyes" || l.split_whitespace().collect::<Vec<_>>() == ["authorized:","yes"]).count();
    let state = format!("{{\"mode\":{},\"ssid\":{},\"ip\":{},\"channel\":{},\"internet\":{},\"stations\":{stations}}}",
        json(if shared {"shared"} else {"direct"}),json(&c.ssid),json(&c.host),json(line),
        json(if !shared {"off"} else if available {"route-available"} else {"paused"}));
    if fs::read_to_string(path("status.json")).ok().as_deref()!=Some(&state) {
        write(&path("status.tmp"),&state,0o644)?;
        fs::rename(path("status.tmp"),path("status.json"))?;
    }
    Ok(())
}
fn monitor(args: &[&str], tx: mpsc::Sender<()>) -> Result<Child> {
    let mut child = Command::new("stdbuf").arg("-oL").args(args).stdin(Stdio::null()).stdout(Stdio::piped()).spawn()?;
    let stdout = child.stdout.take().ok_or_else(|| err("Monitor pipe unavailable"))?;
    thread::spawn(move || {
        for line in BufReader::new(stdout).lines() {
            if line.is_err() || tx.send(()).is_err() { return; }
        }
        let _ = tx.send(());
    });
    Ok(child)
}
fn cleanup(c: &Config) -> Result<()> {
    // ExecStopPost runs after the whole service cgroup is stopped, even on failure.
    if !path("owned").exists() { return Ok(()); }
    let share_closed = clear("shared").is_ok(); // fail closed before touching forwarding/interface
    if !share_closed { eprintln!("Unable to close sharing set; removing AP immediately"); }
    remove("status.json"); remove("qr.txt");
    if path("owned-ap").exists() && ap_exists() {
        let _ = run(&["ip","link","set",AP,"down"]);
        run(&["iw","dev",AP,"del"])?;
    }
    // Record the teardown even if the kernel removed our AP before cleanup.
    if path("owned-ap").exists() {
        write(&path("last-ap-stop-ms"), &boot_millis()?.to_string(), 0o600)?;
    }
    if path("wifi-forward").exists() {
        if fs::read_to_string("/proc/sys/net/ipv4/ip_forward")?.trim()=="0" && sysctl(&c.wifi,"forwarding").exists() {
            set_forward(&c.wifi,"0\n")?;
        }
    }
    clear("owned_forward")?;
    for file in ["owned","owned-ap","wifi-forward","hostapd.conf","status.tmp"] { remove(file); }
    Ok(())
}
fn start(c: &Config, shared: bool) -> Result<()> {
    if path("owned").exists() { return Err(err("Previous hotspot cleanup incomplete; reboot or inspect logs")); }
    if ap_exists() { return Err(err("Manual AP exists; reboot before first use")); }
    guard_ok(false, None)?;
    if !local_session()? { return Err(err("No local desktop session")); }
    wait_ap_cooldown()?;
    check_routes(c)?;
    let ch = channel(c)?;
    let secret = password()?;
    mark("owned")?;
    run(&["iw","dev",&c.wifi,"interface","add",AP,"type","__ap"])?;
    mark("owned-ap")?;
    // NetworkManager is declaratively configured to leave this interface unmanaged.
    run(&["ip","link","set",AP,"down"])?;
    run(&["iw","dev",AP,"set","type","__ap"])?;
    fs::write(format!("/proc/sys/net/ipv6/conf/{AP}/disable_ipv6"),"1\n")?;
    set_forward(AP,"0\n")?;
    run(&["ip","addr","add",&format!("{}/24",c.host),"dev",AP])?;
    let mut ap = hostapd(c,ch,&secret)?;
    run(&["ip","link","set",AP,"up"])?;
    if shared {
        if fs::read_to_string(sysctl(&c.wifi,"forwarding"))?.trim()=="0" {
            element("owned_forward",&c.wifi)?;
            mark("wifi-forward")?;
            set_forward(&c.wifi,"1\n")?;
        }
        set_forward(AP,"1\n")?;
        element("shared",AP)?;
    }
    let range = format!("--dhcp-range={},{},255.255.255.0,12h",c.client,c.client);
    let router = if shared {format!("--dhcp-option=option:router,{}",c.host)} else {"--dhcp-option=option:router".into()};
    let dns = if shared {"--dhcp-option=option:dns-server,1.1.1.1,1.0.0.1"} else {"--dhcp-option=option:dns-server"};
    let mut dhcp = spawn(&["dnsmasq","--conf-file=/dev/null","--keep-in-foreground","--port=0",
        "--interface=ipad-ap","--except-interface=lo","--bind-interfaces",&range,&router,dns,"--leasefile-ro","--log-dhcp"])?;
    thread::sleep(Duration::from_millis(500));
    if dhcp.try_wait()?.is_some() { return Err(err("DHCP failed to start")); }
    write(&path("qr.txt"),&format!("WIFI:T:WPA;S:{};P:{secret};;",c.ssid),0o640)?;
    run(&["chgrp","wheel",path("qr.txt").to_str().unwrap()])?;
    let (tx, rx) = mpsc::channel();
    let mut monitors = vec![
        monitor(&["ip","monitor","link","address","route","rule"],tx.clone())?,
        monitor(&["iw","event"],tx.clone())?,
        monitor(&["nft","monitor"],tx.clone())?,
        monitor(&["busctl","--system","monitor","org.freedesktop.login1"],tx)?,
    ];
    report(c,shared)?;
    run(&["systemd-notify","--ready"])?;
    loop {
        // Wait for kernel/network/session events. Slow watchdog catches lost events
        // and unexpected child exits; it is not the previous two-second polling loop.
        let _ = rx.recv_timeout(Duration::from_secs(30));
        let deadline = Instant::now()+Duration::from_millis(250);
        while let Some(left) = deadline.checked_duration_since(Instant::now()) {
            if rx.recv_timeout(left).is_err() { break; }
        }
        if ap.try_wait()?.is_some() || dhcp.try_wait()?.is_some() { return Err(err("AP or DHCP exited")); }
        for m in &mut monitors { if m.try_wait()?.is_some() { return Err(err("Network event monitor exited")); } }
        guard_ok(shared, None)?;
        check_routes(c)?;
        if channel(c)? != ch { return Err(err("Upstream channel changed; restart display")); }
        if !local_session()? { return Ok(()); }
        report(c,shared)?;
    }
}
fn start_wifi(c: &Config) -> Result<()> {
    // Explicit fallback only. The guard is closed on exit or failed startup.
    guard_ok(false, None)?;
    if ap_exists() || path("owned").exists() { return Err(err("Hotspot cleanup incomplete")); }
    if !local_session()? { return Err(err("No local desktop session")); }
    mark("owned-legacy")?;
    element("legacy", &c.wifi)?;
    guard_ok(false, Some(&c.wifi))?;
    let (tx, rx) = mpsc::channel();
    let mut watcher = monitor(&["busctl","--system","monitor","org.freedesktop.login1"],tx)?;
    run(&["systemd-notify","--ready"])?;
    loop {
        let _ = rx.recv_timeout(Duration::from_secs(30));
        if watcher.try_wait()?.is_some() { return Err(err("Session monitor exited")); }
        guard_ok(false, Some(&c.wifi))?;
        if !local_session()? { return Ok(()); }
    }
}
fn cleanup_wifi() -> Result<()> {
    if path("owned-legacy").exists() {
        clear("legacy")?;
        remove("owned-legacy");
    }
    Ok(())
}
fn main() {
    let result = (|| -> Result<()> {
        let c = Config::read()?;
        match env::args().nth(1).as_deref() {
            Some("direct") => start(&c,false),
            Some("shared") => start(&c,true),
            Some("cleanup") => cleanup(&c),
            Some("wifi") => start_wifi(&c),
            Some("wifi-cleanup") => cleanup_wifi(),
            _ => Err(err("Usage: ipad-hotspotd wifi|direct|shared|cleanup|wifi-cleanup"))
        }
    })();
    if let Err(e) = result { eprintln!("ipad-hotspotd: {e}"); std::process::exit(1); }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn channel44() {
        let ch = parse_channel("channel 44 (5220 MHz), width: 80 MHz, center1: 5210 MHz").unwrap();
        let v = variants(ch).unwrap();
        assert!(v[0].contains("seg0_idx=42"));
        assert!(v[0].contains("HT40+"));
        assert_eq!(v.len(),3);
    }
    #[test] fn channel48() {
        let ch = parse_channel("channel 48 (5240 MHz), width: 80 MHz, center1: 5210 MHz").unwrap();
        assert!(variants(ch).unwrap()[0].contains("HT40-"));
    }
    #[test] fn channel6() {
        let ch = parse_channel("channel 6 (2437 MHz), width: 20 MHz, center1: 2437 MHz").unwrap();
        assert_eq!(variants(ch).unwrap(),vec![String::new()]);
    }
    #[test] fn cooldown() {
        assert_eq!(cooldown_remaining(10_000, 10_000), Duration::from_secs(5));
        assert_eq!(cooldown_remaining(12_000, 10_000), Duration::from_secs(3));
        assert_eq!(cooldown_remaining(15_000, 10_000), Duration::ZERO);
        assert_eq!(cooldown_remaining(20_000, 10_000), Duration::ZERO);
        assert_eq!(cooldown_remaining(9_000, 10_000), Duration::from_secs(5));
    }
    #[test] fn routes() {
        let host = "10.42.0.1".parse().unwrap();
        assert!(route_overlap("10.0.0.0/8 dev tun0",host));
        assert!(route_overlap("10.42.0.2 dev tun0",host));
        assert!(!route_overlap("10.42.0.0/24 dev ipad-ap",host));
        assert!(!route_overlap("0.0.0.0/1 dev tun0",host));
        assert!(!route_overlap("192.168.0.0/24 dev homewg",host));
    }
}
