#!/usr/bin/env node

const cp = require("child_process")

ignoredPorts = {
  8080: 22,
}

const lines = cp
  .execSync("x ss -ltn --no-header")
  .toString()
  .trim()
  .split("\n")
let ports = lines.map(l => {
  // Split on whitespace, third field, then string after last colon.
  return l
    .split(/\s+/)[3]
    .split(":")
    .pop()
})
ports = new Set(ports)
// We do not want to forward the ssh ports.
ports.delete("22")
ports.delete("2424")

// Remove unused forwardings.
portForwarders().forEach(f => {
  if (ports.has(f.port)) {
    // Active forwarding exists.
    console.log(`forwarding for ${f.port} already active`)
    ports.delete(f.port)
    return
  }
  console.log(`killing forwarding for ${f.port}`)
  cp.exec(`kill ${f.pid}`)
})

ports.forEach(port => {
  console.log(`spawning forwarding for ${port}`)
  const process = cp.spawn("ssh", ["-NT", `-L ${port}:localhost:${port}`, "xayah-unshared"], {
    detached: true,
    stdio: "ignore",
  })
  process.unref()
})

function portForwarders() {
  let lines = []
  try {
    lines = cp
      .execSync("pgrep -l -f 'ssh -NT -L' | grep xayah-unshared")
      .toString()
      .trim()
      .split("\n")
  } catch {}
  return lines.map(l => {
    const fields = l.split(" ")
    const port = fields[4].split(":").pop()
    return {
      pid: fields[0],
      port: port,
    }
  })
}
