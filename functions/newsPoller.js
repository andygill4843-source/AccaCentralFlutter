/**
 * newsPoller.js — Firebase Cloud Function (v2, scheduled)
 *
 * Refreshes a small cached pool of football headlines every 2 hours,
 * using TheNewsAPI (api.thenewsapi.com). Scores and ranks them, keeps
 * the top 5, writes to Firestore for instant client reads — no client
 * ever calls TheNewsAPI directly, and the key never ships in the app.
 *
 * Add to functions/.env:
 *   NEWS_API_KEY=your_key_here
 *
 * Add to functions/index.js:
 *   exports.newsPoller = require('./newsPoller').newsPoller;
 */

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { getFirestore } = require('firebase-admin/firestore');

const db = getFirestore();
const API_KEY = process.env.NEWS_API_KEY;
// Confirmed correct base + endpoint — the originally supplied code used
// 'https://thenewsapi.com' with no path, which would fail outright.
const BASE_URL = 'https://api.thenewsapi.com/v1/news/all';

// Domain fragments, matching TheNewsAPI's actual `source` field shape
// (a bare domain, e.g. "skysports.com") — NOT human-readable names.
const PRIORITY_SOURCE_DOMAINS = [
  'skysports.com',
  'bbc.co.uk',
  'espn.com',
  'theguardian.com',
];

function scoreArticle(item) {
  const title = (item.title || '').toLowerCase();
  const snippet = (item.snippet || '').toLowerCase();
  const source = (item.source || '').toLowerCase();
  const text = `${title} ${snippet}`;

  let score = 0;

  if (/(premier league|epl|la liga|laliga|bundesliga|serie a|ligue 1)/.test(text)) {
    score += 25;
  } else if (text.includes('championship')) {
    score += 15;
  } else if (/(league one|league 1|league two|league 2)/.test(text)) {
    score += 10;
  } else if (text.includes('national league')) {
    score += 5;
  }

  if (/(sign|transfer|medical|contract|agreed fee|clause|done deal|window|bid)/.test(text)) {
    score += 40;
  } else if (/(injur|sidelined|hamstring|acl|red card|ban|suspend|out for|fitness test|doubt)/.test(text)) {
    score += 35;
  } else if (/(sacked|appointed|manager|coach|resign|takeover)/.test(text)) {
    score += 20;
  }

  if (PRIORITY_SOURCE_DOMAINS.some((d) => source.includes(d))) {
    score += 30;
  }

  return score;
}

exports.newsPoller = onSchedule(
  { schedule: '0 7-21/2 * * *', timeZone: 'Europe/London', timeoutSeconds: 120, memory: '256MiB' },
  async () => {
    if (!API_KEY) {
      console.error('NEWS_API_KEY not set in functions/.env');
      return;
    }

    const rawArticles = [];
    for (let page = 1; page <= 5; page++) {
      try {
        const url = `${BASE_URL}?api_token=${API_KEY}&search=${encodeURIComponent('football OR soccer')}&language=en&sort=published_at&limit=3&page=${page}`;
        const res = await fetch(url);
        if (!res.ok) continue;
        const data = await res.json();
        rawArticles.push(...(data.data ?? []));
      } catch (e) {
        console.error(`News fetch page ${page} failed:`, e.message);
      }
    }

    const scored = rawArticles
      .map((item) => ({ item, score: scoreArticle(item) }))
      .sort((a, b) => b.score - a.score)
      .slice(0, 5)
      .map(({ item }) => ({
        title: item.title || '',
        snippet: item.snippet || '',
        source: item.source || '',
        url: item.url || '',
        // Empty rather than a placeholder webpage URL — the client
        // shows a fallback icon when this is empty, rather than
        // Image.network failing on a non-image URL.
        imageUrl: item.image_url || '',
      }));

    await db.collection('footballNews').doc('latest').set({
      articles: scored,
      updatedAt: new Date(),
    });
  }
);