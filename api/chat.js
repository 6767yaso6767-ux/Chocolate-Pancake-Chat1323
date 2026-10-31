const U = 'https://olnkpxxuzhxdjyuecpsn.supabase.co';
const K = 'sb_publishable_DQdUMdy4u1FBGHLCRo2UcQ_zDEQUgOn';
const SYS = 'Sen Claude’sun ve bu sohbet sitesinde samimi bir üyesin. Türkçe, kısa ve doğal konuş.';
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Sadece POST' });
  if (!process.env.ANTHROPIC_API_KEY) return res.status(500).json({ error: 'ANTHROPIC_API_KEY tanımlı değil' });
  try {
    const v = await fetch(U + '/auth/v1/user', { headers: { apikey: K, Authorization: req.headers.authorization || '' } });
    if (!v.ok) return res.status(401).json({ error: 'Giriş gerekli' });
    const { messages } = req.body || {};
    if (!Array.isArray(messages) || !messages.length) return res.status(400).json({ error: 'Mesaj yok' });
    const clean = messages.slice(-20).map(m => ({ role: m.role === 'assistant' ? 'assistant' : 'user', content: String(m.content || '').slice(0, 4000) }));
    const r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': process.env.ANTHROPIC_API_KEY, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: 'claude-sonnet-5-5', max_tokens: 800, system: SYS, messages: clean })
    });
    const d = await r.json();
    if (!r.ok) return res.status(502).json({ error: (d.error && d.error.message) || 'API hatası' });
    res.status(200).json({ text: (d.content || []).filter(c => c.type === 'text').map(c => c.text).join('\n') });
  } catch (e) { res.status(500).json({ error: e.message }); }
};
