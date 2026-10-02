import express from 'express';

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '64kb' }));

const PORT = Number(process.env.PORT || 10000);
const VERSION = process.env.MILTV_VERSION || '5.42.0';
const SERVICE = 'miltv-backend';

app.get('/health', (_req, res) => {
  res.status(200).json({
    ok: true,
    service: SERVICE,
    app: 'MILTV',
    version: VERSION,
    environment: process.env.NODE_ENV || 'production',
    timestamp: new Date().toISOString()
  });
});

app.get('/', (_req, res) => {
  res.status(200).json({ service: SERVICE, app: 'MILTV', version: VERSION, health: '/health' });
});

app.use((_req, res) => res.status(404).json({ error: 'not_found' }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`MILTV backend listening on ${PORT}`);
});
