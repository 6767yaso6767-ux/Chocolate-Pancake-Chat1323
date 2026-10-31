const U = 'https://olnkpxxuzhxdjyuecpsn.supabase.co';
const K = 'sb_publishable_DQdUMdy4u1FBGHLCRo2UcQ_zDEQUgOn';
const cache = new Map();
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Sadece POST' });
  const yk = process.env.YOUTUBE_API_KEY;
  if (!yk) return res.status(500).json({ error: 'YOUTUBE_API_KEY tanımlı değil (Vercel ayarlarına ekle)' });
  try {
    const v = await fetch(U + '/auth/v1/user', { headers: { apikey: K, Authorization: req.headers.authorization || '' } });
    if (!v.ok) return res.status(401).json({ error: 'Giriş gerekli' });
    const q = String((req.body && req.body.q) || '').trim().slice(0, 100);
    const short = !!(req.body && req.body.short);
    if (!q) return res.status(400).json({ error: 'Arama boş' });
    const key = q.toLowerCase() + '|' + short, hit = cache.get(key);
    if (hit && Date.now() - hit.t < 600000) return res.status(200).json({ items: hit.items });
    const p = new URLSearchParams({ part: 'snippet', type: 'video', maxResults: '12', videoEmbeddable: 'true', safeSearch: 'moderate', relevanceLanguage: 'tr', q: short ? q + ' #shorts' : q, key: yk });
    if (short) p.set('videoDuration', 'short');
    const r = await fetch('https://www.googleapis.com/youtube/v3/search?' + p);
    const d = await r.json();
    if (!r.ok) return res.status(502).json({ error: (d.error && d.error.message) || 'YouTube API hatası' });
    const items = (d.items || []).filter(i => i.id && i.id.videoId).map(i => ({
      id: i.id.videoId, title: i.snippet.title, channel: i.snippet.channelTitle,
      thumb: (i.snippet.thumbnails.medium || i.snippet.thumbnails.default).url
    }));
    if (cache.size > 200) cache.clear();
    cache.set(key, { t: Date.now(), items });
    res.status(200).json({ items });
  } catch (e) { res.status(500).json({ error: e.message }); }
};
