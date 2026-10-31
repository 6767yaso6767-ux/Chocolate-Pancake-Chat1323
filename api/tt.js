const U = 'https://olnkpxxuzhxdjyuecpsn.supabase.co';
const K = 'sb_publishable_DQdUMdy4u1FBGHLCRo2UcQ_zDEQUgOn';
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Sadece POST' });
  try {
    const v = await fetch(U + '/auth/v1/user', { headers: { apikey: K, Authorization: req.headers.authorization || '' } });
    if (!v.ok) return res.status(401).json({ error: 'Giriş gerekli' });
    const url = String((req.body && req.body.url) || '').trim().slice(0, 300);
    if (!/^https?:\/\/([a-z0-9-]+\.)?tiktok\.com\//i.test(url)) return res.status(400).json({ error: 'Geçerli bir TikTok bağlantısı değil' });
    const r = await fetch('https://www.tiktok.com/oembed?url=' + encodeURIComponent(url));
    if (!r.ok) return res.status(404).json({ error: 'Video bulunamadı' });
    const d = await r.json();
    const m = (d.html || '').match(/data-video-id="(\d+)"/);
    if (!m) return res.status(404).json({ error: 'Video kimliği bulunamadı' });
    res.status(200).json({ id: m[1], title: d.title || '', author: d.author_name || '', thumb: d.thumbnail_url || '' });
  } catch (e) { res.status(500).json({ error: e.message }); }
};
