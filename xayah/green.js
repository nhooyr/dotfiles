#!/usr/bin/env node

const cp = require("child_process")
const fs = require("fs")

const activeUsers = who()
if (activeUsers != "") {
  console.log("users logged in")
  console.log(`who:\n${activeUsers.trim()}`)
  return
}

const lastActivity = getLastActivity()
if (isNaN(lastActivity)) {
  console.log("last activity is not a valid date")
  process.exit(1)
}

const threshold = new Date()
threshold.setHours(threshold.getHours() - 1)

console.log("last activity", lastActivity)
console.log("threshold", threshold)

if (lastActivity < threshold) {
  console.log("last activity before threshold")
  console.log("powering off")
  cp.exec("poweroff")
  return
}

console.log("last activity after threshold")

function who() {
  // Only returns users logged in remotely by grepping for an IP address.
  try {
    return cp.execSync(String.raw`who | grep -E '\([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\)'`).toString()
  } catch {
    return ""
  }
}

function getLastActivity() {
  // https://linux.die.net/man/5/wtmp
  try {
    return fs.statSync("/var/log/wtmp").mtime
  } catch {
    // Ensures shutdown.
    return new Date(0)
  }
}
