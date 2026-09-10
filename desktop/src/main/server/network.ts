/**
 * WORKFLOW OF THIS FILE:
 * 1. Reads every network interface on the laptop.
 * 2. Filters out loopback, non-IPv4 and internal addresses.
 * 3. Prefers the Android hotspot subnet (192.168.43.x) if present.
 * 4. Falls back to the first other external IPv4 if no hotspot found.
 * 5. Returns null if no usable address exists.
 *
 * FUNCTIONS:
 *  - detectLocalIp() : returns { host, iface } for the best interface.
 */
import { networkInterfaces } from 'os'

export type LocalAddr = { host: string; iface: string }

export function detectLocalIp(): LocalAddr | null {
  const ifaces = networkInterfaces()
  let fallback: LocalAddr | null = null

  for (const [name, addrs] of Object.entries(ifaces)) {
    if (!addrs) continue
    for (const addr of addrs) {
      // skip non-IPv4 and loopback
      const family = typeof addr.family === 'string' ? addr.family : `IPv${addr.family}`
      if (family !== 'IPv4' || addr.internal) continue

      // prefer Android hotspot subnet
      if (addr.address.startsWith('192.168.43.')) {
        return { host: addr.address, iface: name }
      }
      // skip virtual adapters that often cause confusion
      if (/vmware|virtualbox|veth|docker/i.test(name)) continue
      if (!fallback) fallback = { host: addr.address, iface: name }
    }
  }
  return fallback
}