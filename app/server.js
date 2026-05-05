const http = require('http');
const { CosmosClient } = require('@azure/cosmos');

const PORT     = process.env.PORT     || 8080;
const REGION   = process.env.REGION   || 'unknown';
const ENDPOINT = process.env.COSMOS_ENDPOINT;
const KEY      = process.env.COSMOS_KEY;
const DATABASE = process.env.COSMOS_DATABASE || 'appdb';

const cosmos = new CosmosClient({ endpoint: ENDPOINT, key: KEY });
const container = cosmos.database(DATABASE).container('events');

const server = http.createServer(async (req, res) => {
  if (req.url === '/health' && req.method === 'GET') {
    // Front Door probes this. Must return 200 when healthy.
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', region: REGION }));
    return;
  }

  if (req.url === '/write' && req.method === 'POST') {
    // Write a record stamped with this region — used to prove Cosmos
    // multi-write kept accepting writes during the chaos window.
    const doc = {
      id:           `${REGION}-${Date.now()}`,
      regionOrigin: REGION,
      timestamp:    new Date().toISOString(),
    };
    await container.items.create(doc);
    res.writeHead(201, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ written: doc }));
    return;
  }

  res.writeHead(404);
  res.end('not found');
});

server.listen(PORT, () =>
  console.log(`[${REGION}] listening on :${PORT}`)
);
