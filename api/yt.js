const U = 'https://olnkpxxuzhxdjyuecpsn.supabase.co';
const K = 'sb_publishable_DQdUMdy4u1FBGHLCRo2UcQ_zDEQUgOn';
const cache = new Map();
const TOPICS = ['komik', 'müzik', 'oyun', 'spor', 'hayvanlar', 'yemek', 'dans', 'teknoloji', 'sihir', 'araba', 'doğa', 'futbol', 'funny', 'satisfying', 'cats', 'travel', 'diy', 'challenge'];
const ORDERS = ['relevance', 'viewCount', 'date', 'rating'];
const th = s => ((s.thumbnails || {}).medium || (s.thumbnails || {}).default || {}).url || '';
const secs = iso => { const m = /^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/.exec(iso || ''); return m ? (+m[1] || 0) * 3600 + (+m[2] || 0) * 60 + (+m[3] || 0) : 9999; };
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Sadece POST' });
  const yk = process.env.YOUTUBE_API_KEY;
  if (!yk) return res.status(500).json({ error: 'YOUTUBE_API_KEY tanımlı değil (Vercel ayarlarına ekle)' });
  try {
    const v = await fetch(U + '/auth/v1/user', { headers: { apikey: K, Authorization: req.headers.authorization || '' } });
    if (!v.ok) return res.status(401).json({ error: 'Giriş gerekli' });
    const b = req.body || {};
    const yget = async (path, params) => {
      const r = await fetch('https://www.googleapis.com/youtube/v3/' + path + '?' + new URLSearchParams({ ...params, key: yk }));
      const d = await r.json();
      if (!r.ok) throw new Error((d.error && d.error.message) || 'YouTube API hatası');
      return d;
    };
    let items, key;
    if (b.channelId) {
      if (!/^UC[\w-]{22}$/.test(b.channelId)) return res.status(400).json({ error: 'Geçersiz kanal' });
      key = 'c|' + b.channelId;
    } else {
      const rnd = !!b.random, short = rnd || !!b.short;
      let q, order = 'relevance';
      if (rnd) { q = TOPICS[Math.floor(Math.random() * TOPICS.length)] + ' #shorts'; order = ORDERS[Math.floor(Math.random() * ORDERS.length)]; }
      else { q = String(b.q || '').trim().slice(0, 100); if (!q) return res.status(400).json({ error: 'Arama boş' }); if (short) q += ' #shorts'; }
      key = 's|' + q.toLowerCase() + '|' + order + '|' + short;
      const hit = cache.get(key);
      if (hit && Date.now() - hit.t < 600000) return res.status(200).json({ items: hit.items });
      const d = await yget('search', { part: 'snippet', type: 'video', maxResults: short ? '25' : '12', videoEmbeddable: 'true', safeSearch: 'moderate', relevanceLanguage: 'tr', order, q, ...(short ? { videoDuration: 'short' } : {}) });
      items = (d.items || []).filter(i => i.id && i.id.videoId).map(i => ({ id: i.id.videoId, title: i.snippet.title, channel: i.snippet.channelTitle, channelId: i.snippet.channelId, thumb: th(i.snippet) }));
      if (short && items.length) {
        const dd = await yget('videos', { part: 'contentDetails', id: items.map(i => i.id).join(',') });
        const ok = new Set((dd.items || []).filter(x => secs(x.contentDetails.duration) <= 60).map(x => x.id));
        items = items.filter(i => ok.has(i.id));
      }
    }
    if (b.channelId) {
      const hit = cache.get(key);
      if (hit && Date.now() - hit.t < 600000) return res.status(200).json({ items: hit.items });
      const d = await yget('playlistItems', { part: 'snippet', playlistId: 'UU' + b.channelId.slice(2), maxResults: '24' });
      items = (d.items || []).filter(i => i.snippet && i.snippet.resourceId && i.snippet.resourceId.videoId && i.snippet.thumbnails && !/^(Private|Deleted) video$/.test(i.snippet.title))
        .map(i => ({ id: i.snippet.resourceId.videoId, title: i.snippet.title, channel: i.snippet.videoOwnerChannelTitle || i.snippet.channelTitle, channelId: b.channelId, thumb: th(i.snippet) }));
    }
    if (cache.size > 300) cache.clear();
    cache.set(key, { t: Date.now(), items });
    res.status(200).json({ items });
  } catch (e) { res.status(500).json({ error: e.message }); }
};
