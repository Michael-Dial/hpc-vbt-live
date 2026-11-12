# Host and network

Type: grilling
Status: open
Blocked by:

## Question

How is the Host built and how do Stations and the iPad talk to it?

Decide:

- Host hardware and OS. v1 does no GPU work, so any laptop or mini PC qualifies.
- Docker Compose versus native services on the Host.
- Configuration of the isolated router (no internet route) and how Stations and the iPad join it.
- How Stations find the Host (Bonjour), and iOS's local network permission prompt.
- How live Reps reach the Host (WebSocket) and how Recordings upload after a Session.
- Queueing on the Station while the network is down, and replay on reconnect.
- Clock alignment between Stations and the Host.
- What the iPad loads: the Host's web UI.

Constraint: live feedback on the Station never depends on the network.
