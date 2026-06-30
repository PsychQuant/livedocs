import Foundation
import MCP

// Entry point for che-livedocs-mcp. Network-only server (no TCC permissions),
// so unlike the Apple-app MCPs there's no onboarding/permission divert here —
// straight to the stdio server.
let server = CheLiveDocsMCPServer()
try await server.run()
