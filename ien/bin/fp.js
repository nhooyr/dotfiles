#!/usr/bin/env node

const cp = require("child_process")

;(async () => {
  try {
    await main()
  } catch (e) {
    console.error(e)
    process.exit(1)
  }
})()

async function main() {
  const [activePorts, activeForwarders] = await Promise.all([getActivePorts(), getActiveForwarders()])

  // Kill unused forwardings.
  activeForwarders.forEach(af => {
    if (activePorts.includes(af.port)) {
      // Active forwarding exists.
      console.log(`forwarding for ${af.port} already active`)
      activePorts.delete(af.port)
      return
    }

    // We try our best to kill the forwarding but any errors should be irrelevant.
    // We'll catch them below anyway when we fail to listen.
    console.log(`killing forwarding for ${af.port}`)
    cp.exec(`kill ${af.pid}`)
  })

  await Promise.all(
    activePorts.map(async port => {
      console.log(`spawning forwarding for ${port}`)

      try {
        await ensurePortAvailable(port)
      } catch {
        return
      }

      const process = cp.spawn("ssh", ["-NT", `-L ${port}:localhost:${port}`, "xayah-unshared"], {
        detached: true,
        stdio: "ignore",
      })
      process.unref()
    }),
  )
}

async function getActiveForwarders() {
  return new Promise((res, rej) => {
    cp.exec("pgrep -l -f 'ssh -NT -L .* xayah-unshared'", (err, stdout, stderr) => {
      // An exit code of 1 from pgrep means it did not find anything which is fine.
      if (err && err.code !== 1) {
        rej(err)
        return
      }

      stdout = stdout.trim()

      if (stdout === "") {
        res([])
        return
      }

      const lines = stdout.split("\n")

      const forwarders = lines.map(l => {
        const fields = l.split(" ")
        const port = fields[4].split(":").pop()
        return {
          pid: fields[0],
          port: port,
        }
      })
      res(forwarders)
    })
  })
}

async function getActivePorts() {
  return new Promise((res, rej) => {
    cp.exec("x ss -ltn --no-header", (err, stdout, stderr) => {
      if (err) {
        rej(err)
        return
      }

      const lines = stdout.trim().split("\n")

      let ports = lines.map(l => {
        // Split on whitespace, fourth field, then string after last colon.
        return l
          .split(/\s+/)[3]
          .split(":")
          .pop()
      })

      // Removes duplicate ports.
      ports = new Set(ports)

      // We do not want to forward the ssh ports.
      ports.delete("22")
      ports.delete("2424")

      res([...ports])
    })
  })
}

async function ensurePortAvailable(port) {
  return new Promise((res, rej) => {
    cp.exec(`netstat -vanp tcp`, (err, stdout, stderr) => {
      if (err) {
        rej(err)
        return
      }
      const lines = stdout.trim().split("\n")
      for (l of lines) {
        if (l.match(port)) {
          rej(`port ${port} is in use by: ${l.split(/\s+/)[8]}`)
        }
      }
      res()
    })
  })
}
