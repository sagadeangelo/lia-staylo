// server.js
const express = require('express');
const axios = require('axios');
const cors = require('cors');

const PORT   = process.env.PORT || 3000;
const LT_BASE = process.env.LT_BASE || 'http://localhost:8010';

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

// Salud simple para el botón de "Health"
app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'api', ltBase: LT_BASE, time: new Date().toISOString() });
});

// Analiza texto plano usando LanguageTool
app.post('/analyze', async (req, res) => {
  try {
    const { text = '', ltLang = 'es' } = req.body || {};
    if (!text || typeof text !== 'string') {
      return res.status(400).json({ ok: false, error: 'missing_text' });
    }

    // LanguageTool /v2/check requiere form-urlencoded
    const params = new URLSearchParams();
    params.set('text', text);
    params.set('language', ltLang); // p.ej. "es" o "en-US"

    const r = await axios.post(`${LT_BASE}/v2/check`, params, {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      timeout: 30_000,
    });

    res.json({ ok: true, languageTool: r.data });
  } catch (err) {
    const status = err.response?.status || 500;
    const detail = err.response?.data || { message: String(err) };
    res.status(status).json({ ok: false, error: 'lt_request_failed', detail });
  }
});

app.listen(PORT, () => {
  console.log(`API up on http://localhost:${PORT} (LT at ${LT_BASE})`);
});
