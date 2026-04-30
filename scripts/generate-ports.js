#!/usr/bin/env node

/**
 * Port Configuration Generator
 * Automatically extracts port mappings from Docker Compose files
 * and generates configuration documentation
 */

const fs = require("fs");
const path = require("path");
const yaml = require("js-yaml");

const WORKSPACE_ROOT = path.join(__dirname, "..");

// Service configurations for NGINX proxy
// Note: Use container ports (not host ports) for Docker internal networking
const NGINX_PROXY_CONFIG = {
  adguardhome: {
    port: 3000,
    domain: "adguard.home.lab",
    cacheAssets: false,
    forcePort: 3000,
    note: "(Web UI on port 3000, not DNS port 53)",
  },
  homeassistant: {
    port: 8123,
    domain: "homeassistant.home.lab",
    cacheAssets: false,
    websocket: true,
  },
  plex: { port: 32400, domain: "plex.home.lab", cacheAssets: false },
  sonarr: { port: 8989, domain: "sonarr.home.lab", cacheAssets: false },
  radarr: { port: 7878, domain: "radarr.home.lab", cacheAssets: false },
  lidarr: { port: 8686, domain: "lidarr.home.lab", cacheAssets: false },
  bazarr: { port: 6767, domain: "bazarr.home.lab", cacheAssets: false },
  prowlarr: { port: 9696, domain: "prowlarr.home.lab", cacheAssets: false },
  qbittorrent: {
    port: 8080,
    domain: "qbittorrent.home.lab",
    cacheAssets: false,
    envVar: "WEBUI_PORT",
  },
  overseerr: { port: 5055, domain: "overseerr.home.lab", cacheAssets: false },
  minecraft: {
    port: 25565,
    domain: "minecraft.home.lab",
    cacheAssets: false,
    protocol: "TCP",
  },
};

// Helper function to read YAML file
function readCompose(filePath) {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    return yaml.load(content);
  } catch (error) {
    console.error(`Error reading ${filePath}:`, error.message);
    return null;
  }
}

// Extract port info from service
function extractPorts(service) {
  const ports = [];
  if (!service.ports) return ports;

  for (const port of service.ports) {
    // Parse port format: "hostPort:containerPort/protocol" or "hostPort:containerPort"
    const match = port.match(/^(\d+):(\d+)(?:\/(.+))?$/);
    if (match) {
      ports.push({
        host: parseInt(match[1]),
        container: parseInt(match[2]),
        protocol: match[3] || "tcp",
      });
    }
  }
  return ports;
}

// Generate port report
function generatePortReport() {
  console.log("\n📊 PORT CONFIGURATION REPORT\n");
  console.log("=".repeat(80));

  const stacks = [
    { path: "adblock-stack/compose.yml", name: "Ad Blocking Stack" },
    { path: "infra-stack/compose.yml", name: "Infrastructure Stack" },
    { path: "homeassistant-stack/compose.yml", name: "Home Assistant Stack" },
    { path: "plex-stack/compose.yml", name: "Plex Stack" },
    {
      path: "minecraft-stack/servers/server-test/compose.yml",
      name: "Minecraft Stack",
    },
  ];

  const allPorts = {};

  for (const stack of stacks) {
    const filePath = path.join(WORKSPACE_ROOT, stack.path);
    if (!fs.existsSync(filePath)) {
      console.log(`⚠️  Skipped: ${stack.path} (not found)`);
      continue;
    }

    const compose = readCompose(filePath);
    if (!compose || !compose.services) continue;

    console.log(`\n🏗️  ${stack.name}`);
    console.log("-".repeat(80));

    for (const [serviceName, service] of Object.entries(compose.services)) {
      const ports = extractPorts(service);
      if (ports.length === 0) continue;

      allPorts[serviceName] = ports;

      const container = service.container_name || serviceName;
      console.log(`  📦 ${serviceName} (${container})`);

      for (const portInfo of ports) {
        console.log(
          `     ${portInfo.host} → ${portInfo.container}/${portInfo.protocol.toUpperCase()}`,
        );
      }
    }
  }

  console.log("\n" + "=".repeat(80));
  return allPorts;
}

// Generate NGINX configuration recommendations
function generateNginxRecommendations(allPorts) {
  console.log("\n🌐 NGINX PROXY MANAGER CONFIGURATION\n");
  console.log(
    "✨ Use these settings for Docker internal networking (NOT host ports):\n",
  );

  const recommendations = [];

  for (const [serviceName, config] of Object.entries(NGINX_PROXY_CONFIG)) {
    // Find the actual container in our ports map
    const found = allPorts[serviceName];
    let containerPort = config.forcePort || config.port;
    let status = "✅";
    let note = "";

    if (!found && !config.forcePort) {
      status = "⚠️ ";
      note = "(Service has no exposed ports - uses internal Docker network)";
    } else if (!found && config.forcePort) {
      note = config.note;
    } else if (found && !config.forcePort) {
      // Get the container port (the destination)
      containerPort = found[0]?.container || config.port;
    }

    if (!note && config.note) {
      note = config.note;
    }

    console.log(`${status} ${config.domain}`);
    console.log(`   Forward Host: ${serviceName}`);
    console.log(`   Forward Port: ${containerPort}`);
    if (config.websocket) console.log(`   WebSocket Support: ON`);
    if (config.protocol) console.log(`   Protocol: ${config.protocol}`);
    if (note) console.log(`   ${note}`);
    console.log();

    recommendations.push({
      serviceName,
      domain: config.domain,
      forwardHost: serviceName,
      forwardPort: containerPort,
      protocol: config.protocol || "HTTP",
      websocket: config.websocket ? "ON" : "OFF",
      cacheAssets: config.cacheAssets ? "ON" : "OFF",
    });
  }

  return recommendations;
}

// Generate AdGuard DNS rewrite recommendations
function generateAdguardDnsRewrites(recommendations) {
  console.log("\n🔍 ADGUARD HOME DNS REWRITES\n");
  console.log("-".repeat(80));
  console.log("Add these rewrites in AdGuard Home: Filters → DNS rewrites\n");

  console.log("| Domain | Answer |");
  console.log("|--------|--------|");

  for (const rec of recommendations) {
    console.log(`| ${rec.domain} | nginx-pm (or container IP) |`);
  }

  console.log();
}

// Validate current NGINX config against compose files
function validateNginxConfig() {
  console.log("\n✔️  VALIDATION\n");

  const readmeNginx = path.join(WORKSPACE_ROOT, "infra-stack/README-NGINX.md");
  if (fs.existsSync(readmeNginx)) {
    const content = fs.readFileSync(readmeNginx, "utf8");

    // Check for any port mismatches
    const issues = [];

    if (
      content.includes('Forward Port": `3000`') &&
      content.includes("adguard")
    ) {
      issues.push(
        "⚠️  AdGuard forward port is 3000 - this is correct for internal Docker networking",
      );
    }

    if (issues.length === 0) {
      console.log("✅ NGINX configuration looks good!");
    } else {
      issues.forEach((issue) => console.log(issue));
    }
  }
}

// Main execution
function main() {
  try {
    const allPorts = generatePortReport();
    const recommendations = generateNginxRecommendations(allPorts);
    generateAdguardDnsRewrites(recommendations);
    validateNginxConfig();

    console.log("\n" + "=".repeat(80));
    console.log("✨ Report generated successfully!\n");
  } catch (error) {
    console.error("❌ Error generating report:", error.message);
    process.exit(1);
  }
}

main();
