import { useState, useEffect, useRef, useCallback } from 'react';

const API_BASE = 'https://scraper-production-8f07.up.railway.app';

// --- Embedded data (snapshot — fallback when sandbox blocks requests) ---
const EMBEDDED_NOVELS = [
  {
    _id: '1',
    title: 'Shadow Slave',
    novelUrl: 'https://novelfire.net/book/shadow-slave',
    author: 'Guiltythree',
    rank: '1',
    totalChapters: '2854',
    views: '39M',
    bookmarks: '21.8K',
    status: 'Ongoing',
    genres: ['Action', 'Adventure', 'Fantasy', 'Romance'],
    summary:
      "Growing up in poverty, Sunny never expected anything good from life. However, even he did not anticipate being chosen by the Nightmare Spell and becoming one of the Awakened – an elite group of people gifted with supernatural powers. Transported into a ruined magical world, he found himself facing against terrible monsters – and other Awakened – in a deadly battle of survival. What's worse, the divine power he received happened to possess a small, but potentially fatal side effect…",
    chaptersUrl: 'https://novelfire.net/book/shadow-slave/chapters',
    imageUrl: 'https://novelfire.net/server-1/shadow-slave.jpg',
    rating: 4.7
  },
  {
    _id: '6',
    title: 'Lord of the Mysteries',
    novelUrl: 'https://novelfire.net/book/lord-of-the-mysteries',
    author: 'Cuttlefish That Loves Diving',
    rank: '3',
    totalChapters: '1432',
    views: '10.8M',
    bookmarks: '13.7K',
    status: 'Completed',
    genres: ['Xuanhuan', 'Mystery', 'Fantasy', 'Adventure', 'Action', 'Supernatural', 'Shounen'],
    summary:
      'In the waves of steam and machinery, who could achieve extraordinary? In the fogs of history and darkness, who was whispering? I woke up from the realm of mysteries and opened my eyes to the world. Firearms, cannons, battleships, airships, and difference machines. Potions, divination, curses, hanged-man, and sealed artifacts… The lights shone brightly, yet the secrets of the world were never far away. This was a legend of the "Fool".',
    chaptersUrl: 'https://novelfire.net/book/lord-of-the-mysteries/chapters',
    imageUrl: 'https://novelfire.net/server-1/lord-of-the-mysteries.jpg',
    rating: 4.8
  }
];

let useEmbedded = false;

async function fetchNovels({ limit = 25, offset = 0, search = '' } = {}) {
  if (!useEmbedded) {
    try {
      const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
      if (search) params.set('search', search);
      const res = await fetch(`${API_BASE}/novels?${params}`);
      if (!res.ok) throw new Error('API error');
      return res.json();
    } catch {
      useEmbedded = true;
    }
  }
  let novels = [...EMBEDDED_NOVELS];
  if (search) {
    const q = search.toLowerCase();
    novels = novels.filter(
      (n) =>
        n.title.toLowerCase().includes(q) ||
        n.author.toLowerCase().includes(q) ||
        n.genres?.some((g) => g.toLowerCase().includes(q))
    );
  }
  return {
    data: novels.slice(offset, offset + limit),
    meta: { count: novels.length, limit, offset }
  };
}

async function fetchChapters(novelId, { limit = 25, offset = 0 } = {}) {
  if (!useEmbedded) {
    try {
      const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
      const res = await fetch(`${API_BASE}/novels/${novelId}/chapters?${params}`);
      if (!res.ok) throw new Error('API error');
      return res.json();
    } catch {
      useEmbedded = true;
    }
  }
  return { data: [], meta: { count: 0, limit, offset } };
}

async function fetchChapter(chapterId) {
  if (!useEmbedded) {
    try {
      const res = await fetch(`${API_BASE}/chapters/${chapterId}`);
      if (!res.ok) throw new Error('API error');
      return res.json();
    } catch {
      useEmbedded = true;
    }
  }
  throw new Error('Chapters unavailable in sandbox mode');
}

function isOffline() {
  return useEmbedded;
}

// --- Reading Progress (seed with demo data for embedded novels) ---
const INITIAL_PROGRESS = {
  1: { chapterNum: 847, chapterTitle: "Nightmare's Edge", timestamp: Date.now() - 3600000 },
  6: { chapterNum: 312, chapterTitle: "The Fool's Gambit", timestamp: Date.now() - 7200000 }
};

// --- Palette ---
const GENRE_COLORS = {
  fantasy: '#8B6914',
  action: '#A0522D',
  romance: '#8B3A62',
  'sci-fi': '#4A6B8A',
  horror: '#6B3A3A',
  adventure: '#3A6B5A',
  mystery: '#5A4A6B',
  drama: '#6B5B4B',
  comedy: '#8B8B3A',
  martial: '#7A4A3A',
  xuanhuan: '#6B5A8A',
  wuxia: '#5A6B4A',
  reincarnation: '#4A6B6B',
  system: '#6B6B4A',
  supernatural: '#5A4A6B',
  shounen: '#6B4A3A'
};

function getBookColor(genres) {
  if (!genres?.length) return '#6B6459';
  for (const g of genres) {
    const low = g.toLowerCase();
    for (const [key, val] of Object.entries(GENRE_COLORS)) {
      if (low.includes(key)) return val;
    }
  }
  const hash = genres[0]?.split('').reduce((a, c) => a + c.charCodeAt(0), 0) || 0;
  const hues = ['#8B6914', '#4A6B8A', '#6B5B4B', '#5A4A6B', '#3A6B5A', '#8B3A62', '#7A4A3A'];
  return hues[hash % hues.length];
}

function getBookEmoji(genres) {
  if (!genres?.length) return '📖';
  const g = genres[0]?.toLowerCase() || '';
  if (g.includes('fantasy') || g.includes('xuanhuan')) return '⚔️';
  if (g.includes('action') || g.includes('martial')) return '🔥';
  if (g.includes('romance')) return '💜';
  if (g.includes('sci')) return '🚀';
  if (g.includes('horror')) return '🌑';
  if (g.includes('adventure')) return '🗺️';
  if (g.includes('mystery')) return '🔮';
  if (g.includes('drama')) return '🎭';
  if (g.includes('comedy')) return '😄';
  if (g.includes('supernatural')) return '👻';
  return '📖';
}

// --- Shared UI ---

const MazePattern = () => (
  <svg
    width="100%"
    height="100%"
    style={{ position: 'absolute', top: 0, left: 0, opacity: 0.025, pointerEvents: 'none' }}
  >
    <defs>
      <pattern id="maze" x="0" y="0" width="60" height="60" patternUnits="userSpaceOnUse">
        <path
          d="M0 30h20v-20h20v40h-10v-10h-10v20h40v-40h-20v-10h-20v10h10v10h-30z"
          fill="none"
          stroke="currentColor"
          strokeWidth="0.5"
        />
      </pattern>
    </defs>
    <rect width="100%" height="100%" fill="url(#maze)" />
  </svg>
);

function Spinner({ size = 20 }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', padding: 40 }}>
      <div
        style={{
          width: size,
          height: size,
          border: '2px solid #2A2722',
          borderTopColor: '#C4A44A',
          borderRadius: '50%',
          animation: 'spin 0.8s linear infinite'
        }}
      />
    </div>
  );
}

function ErrorMsg({ message, onRetry }) {
  return (
    <div style={{ textAlign: 'center', padding: '48px 24px', animation: 'fadeUp 0.4s ease' }}>
      <div style={{ fontSize: 32, marginBottom: 12, opacity: 0.4 }}>⚠</div>
      <div
        style={{
          fontSize: 13,
          color: '#6B6459',
          fontFamily: "'IBM Plex Mono', monospace",
          marginBottom: 20,
          lineHeight: 1.6
        }}
      >
        {message}
      </div>
      {onRetry && (
        <button
          onClick={onRetry}
          style={{
            padding: '10px 24px',
            borderRadius: 20,
            border: '1px solid #2A2722',
            background: 'transparent',
            color: '#C4A44A',
            fontSize: 13,
            cursor: 'pointer',
            fontFamily: "'IBM Plex Mono', monospace"
          }}
        >
          Try Again
        </button>
      )}
    </div>
  );
}

function SearchInput({ value, onChange, placeholder, autoFocus }) {
  return (
    <div style={{ position: 'relative' }}>
      <span
        style={{
          position: 'absolute',
          left: 14,
          top: '50%',
          transform: 'translateY(-50%)',
          color: '#4A4640',
          fontSize: 14,
          pointerEvents: 'none'
        }}
      >
        ⌕
      </span>
      <input
        type="text"
        autoFocus={autoFocus}
        placeholder={placeholder || 'Search...'}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        style={{
          width: '100%',
          padding: '12px 16px 12px 38px',
          borderRadius: 12,
          border: '1px solid #2A2722',
          background: '#1A1816',
          color: '#E8DCC8',
          fontSize: 14,
          fontFamily: "'Cormorant Garamond', serif",
          outline: 'none',
          transition: 'border-color 0.3s ease',
          boxSizing: 'border-box'
        }}
        onFocus={(e) => (e.target.style.borderColor = '#3A3530')}
        onBlur={(e) => (e.target.style.borderColor = '#2A2722')}
      />
    </div>
  );
}

function CoverImage({ novel, size = 'md' }) {
  const color = getBookColor(novel.genres);
  const emoji = getBookEmoji(novel.genres);
  const sizes = {
    sm: { w: 44, h: 60, r: 6, fs: 20 },
    md: { w: 52, h: 70, r: 6, fs: 24 },
    lg: { w: 140, h: 190, r: 12, fs: 56 },
    tile: { w: 48, h: 64, r: 6, fs: 22 }
  };
  const s = sizes[size] || sizes.md;
  if (novel.imageUrl) {
    return (
      <img
        src={novel.imageUrl}
        alt=""
        style={{
          width: s.w,
          height: s.h,
          borderRadius: s.r,
          objectFit: 'cover',
          border: `1px solid ${color}25`,
          flexShrink: 0,
          ...(size === 'lg' ? { boxShadow: `0 20px 60px ${color}20, 0 0 100px ${color}08` } : {})
        }}
      />
    );
  }
  return (
    <div
      style={{
        width: s.w,
        height: s.h,
        borderRadius: s.r,
        flexShrink: 0,
        background: `linear-gradient(145deg, ${color}30, ${color}${size === 'lg' ? '20' : '10'})`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: s.fs,
        border: `1px solid ${color}${size === 'lg' ? '30' : '20'}`,
        ...(size === 'lg' ? { boxShadow: `0 20px 60px ${color}20, 0 0 100px ${color}08` } : {})
      }}
    >
      {emoji}
    </div>
  );
}

// Reusable novel card with full details (used in Browse All and search results)
function NovelCardFull({ novel, onClick, index = 0 }) {
  return (
    <div
      onClick={onClick}
      style={{
        background: '#1A1816',
        borderRadius: 14,
        padding: 16,
        cursor: 'pointer',
        border: '1px solid #2A2722',
        position: 'relative',
        overflow: 'hidden',
        animation: `fadeUp 0.4s ease ${index * 0.06}s both`,
        transition: 'transform 0.2s ease, border-color 0.3s ease'
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.transform = 'scale(1.02)';
        e.currentTarget.style.borderColor = '#3A3530';
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.transform = 'scale(1)';
        e.currentTarget.style.borderColor = '#2A2722';
      }}
    >
      {novel.rank && (
        <div
          style={{
            position: 'absolute',
            top: 8,
            right: 10,
            fontSize: 9,
            color: '#4A4640',
            fontFamily: "'IBM Plex Mono', monospace"
          }}
        >
          #{novel.rank}
        </div>
      )}
      <div style={{ marginBottom: 12 }}>
        <CoverImage novel={novel} size="tile" />
      </div>
      <div
        style={{
          fontFamily: "'Cormorant Garamond', serif",
          fontSize: 15,
          color: '#E8DCC8',
          fontWeight: 500,
          lineHeight: 1.25,
          marginBottom: 4,
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          display: '-webkit-box',
          WebkitLineClamp: 2,
          WebkitBoxOrient: 'vertical'
        }}
      >
        {novel.title}
      </div>
      <div
        style={{
          fontSize: 11,
          color: '#6B6459',
          fontFamily: "'IBM Plex Mono', monospace",
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
          marginBottom: 8
        }}
      >
        {novel.author || 'Unknown'}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap' }}>
        {novel.rating != null && (
          <span
            style={{ fontSize: 10, color: '#C4A44A', fontFamily: "'IBM Plex Mono', monospace" }}
          >
            ★ {novel.rating}
          </span>
        )}
        {novel.status && (
          <span
            style={{
              fontSize: 8,
              padding: '2px 6px',
              borderRadius: 6,
              border: `1px solid ${novel.status === 'Ongoing' || novel.status === 'ONGOING' ? '#3A6B5A' : '#6B5B4B'}35`,
              color:
                novel.status === 'Ongoing' || novel.status === 'ONGOING' ? '#5A9B7A' : '#8B7B6B',
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            {novel.status}
          </span>
        )}
      </div>
      {novel.totalChapters && (
        <div
          style={{
            fontSize: 9,
            color: '#3A3530',
            fontFamily: "'IBM Plex Mono', monospace",
            marginTop: 4
          }}
        >
          {novel.totalChapters} chapters
        </div>
      )}
    </div>
  );
}

// ==================== SCREENS ====================

function HomeScreen({ onOpenNovel, progress }) {
  const [novels, setNovels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [showAll, setShowAll] = useState(false);
  const debounceRef = useRef(null);

  const load = useCallback(async (s = '') => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchNovels({ limit: 100, search: s });
      setNovels(res.data || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);
  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedSearch(search), 400);
    return () => clearTimeout(debounceRef.current);
  }, [search]);
  useEffect(() => {
    load(debouncedSearch);
  }, [debouncedSearch, load]);

  // Continue reading: use the already-loaded novels list + progress object
  const continueReading = novels
    .filter((n) => progress[n._id])
    .sort((a, b) => (progress[b._id]?.timestamp || 0) - (progress[a._id]?.timestamp || 0));

  const INITIAL_COUNT = 6;
  const displayNovels = debouncedSearch || showAll ? novels : novels.slice(0, INITIAL_COUNT);

  return (
    <div style={{ padding: '0 0 100px 0', animation: 'fadeUp 0.6s ease' }}>
      {/* Header */}
      <div style={{ padding: '60px 24px 12px' }}>
        <div
          style={{
            fontFamily: "'Cormorant Garamond', serif",
            fontSize: 28,
            fontWeight: 300,
            color: '#E8DCC8',
            letterSpacing: '0.08em'
          }}
        >
          Asterion
        </div>
      </div>

      {/* Search */}
      <div style={{ padding: '12px 24px 8px' }}>
        <SearchInput value={search} onChange={setSearch} placeholder="Search novels..." />
      </div>

      {loading && novels.length === 0 ? (
        <Spinner />
      ) : error ? (
        <ErrorMsg message={error} onRetry={() => load(debouncedSearch)} />
      ) : novels.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '48px 24px' }}>
          <div style={{ fontSize: 36, marginBottom: 12, opacity: 0.3 }}>📚</div>
          <div style={{ fontSize: 13, color: '#4A4640', fontFamily: "'IBM Plex Mono', monospace" }}>
            {debouncedSearch ? 'No novels match your search' : 'No novels found'}
          </div>
        </div>
      ) : (
        <>
          {/* Continue Reading */}
          {!debouncedSearch && continueReading.length > 0 && (
            <div style={{ padding: '20px 24px 8px' }}>
              <div
                style={{
                  fontSize: 10,
                  color: '#6B6459',
                  letterSpacing: '0.2em',
                  textTransform: 'uppercase',
                  marginBottom: 14,
                  fontFamily: "'IBM Plex Mono', monospace"
                }}
              >
                Continue Reading
              </div>
              {continueReading.map((novel, i) => {
                const color = getBookColor(novel.genres);
                const prog = progress[novel._id];
                const totalCh = parseInt(String(novel.totalChapters).replace(/[^0-9]/g, '')) || 1;
                const pct = Math.min(100, Math.round((prog.chapterNum / totalCh) * 100));
                return (
                  <div
                    key={novel._id}
                    onClick={() => onOpenNovel(novel)}
                    style={{
                      background: 'linear-gradient(135deg, #1A1816 0%, #1E1C19 100%)',
                      borderRadius: 16,
                      padding: 18,
                      marginBottom: 10,
                      cursor: 'pointer',
                      border: '1px solid #2A2722',
                      position: 'relative',
                      overflow: 'hidden',
                      animation: `fadeUp 0.4s ease ${i * 0.08}s both`,
                      transition: 'transform 0.2s ease, border-color 0.3s ease'
                    }}
                    onMouseEnter={(e) => {
                      e.currentTarget.style.transform = 'translateY(-1px)';
                      e.currentTarget.style.borderColor = '#3A3530';
                    }}
                    onMouseLeave={(e) => {
                      e.currentTarget.style.transform = 'translateY(0)';
                      e.currentTarget.style.borderColor = '#2A2722';
                    }}
                  >
                    <div
                      style={{
                        position: 'absolute',
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 2,
                        background: `linear-gradient(90deg, ${color}00, ${color}, ${color}00)`,
                        opacity: 0.5
                      }}
                    />
                    <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
                      <CoverImage novel={novel} size="md" />
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div
                          style={{
                            fontFamily: "'Cormorant Garamond', serif",
                            fontSize: 17,
                            color: '#E8DCC8',
                            fontWeight: 500,
                            lineHeight: 1.2,
                            overflow: 'hidden',
                            textOverflow: 'ellipsis',
                            whiteSpace: 'nowrap'
                          }}
                        >
                          {novel.title}
                        </div>
                        <div
                          style={{
                            fontSize: 11,
                            color: '#6B6459',
                            marginTop: 3,
                            fontFamily: "'IBM Plex Mono', monospace"
                          }}
                        >
                          Ch. {prog.chapterNum} · {prog.chapterTitle || ''}
                        </div>
                        <div
                          style={{ marginTop: 10, display: 'flex', alignItems: 'center', gap: 10 }}
                        >
                          <div
                            style={{
                              flex: 1,
                              height: 3,
                              background: '#2A2722',
                              borderRadius: 2,
                              overflow: 'hidden'
                            }}
                          >
                            <div
                              style={{
                                width: `${pct}%`,
                                height: '100%',
                                background: `linear-gradient(90deg, ${color}, ${color}AA)`,
                                borderRadius: 2,
                                transition: 'width 0.5s ease'
                              }}
                            />
                          </div>
                          <span
                            style={{
                              fontSize: 10,
                              color: '#6B6459',
                              fontFamily: "'IBM Plex Mono', monospace"
                            }}
                          >
                            {pct}%
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {/* Browse All */}
          <div style={{ padding: '16px 24px' }}>
            <div
              style={{
                fontSize: 10,
                color: '#6B6459',
                letterSpacing: '0.2em',
                textTransform: 'uppercase',
                marginBottom: 16,
                fontFamily: "'IBM Plex Mono', monospace"
              }}
            >
              {debouncedSearch ? `Results for "${debouncedSearch}"` : 'Browse All'}
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
              {displayNovels.map((novel, i) => (
                <NovelCardFull
                  key={novel._id}
                  novel={novel}
                  onClick={() => onOpenNovel(novel)}
                  index={i}
                />
              ))}
            </div>

            {/* Show More */}
            {!debouncedSearch && !showAll && novels.length > INITIAL_COUNT && (
              <button
                onClick={() => setShowAll(true)}
                style={{
                  width: '100%',
                  padding: '14px',
                  borderRadius: 12,
                  marginTop: 16,
                  border: '1px solid #2A2722',
                  background: '#1A181840',
                  color: '#6B6459',
                  fontSize: 13,
                  cursor: 'pointer',
                  fontFamily: "'IBM Plex Mono', monospace",
                  transition: 'all 0.3s ease'
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.borderColor = '#3A3530';
                  e.currentTarget.style.color = '#C4A44A';
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.borderColor = '#2A2722';
                  e.currentTarget.style.color = '#6B6459';
                }}
              >
                Show More ({novels.length - INITIAL_COUNT} more)
              </button>
            )}
          </div>
        </>
      )}
    </div>
  );
}

function BookDetailScreen({ novel, onBack, onReadChapter, onViewChapters, allNovels }) {
  const [chapters, setChapters] = useState([]);
  const [loadingCh, setLoadingCh] = useState(true);
  const [expanded, setExpanded] = useState(false);
  const [localNovels, setLocalNovels] = useState([]);
  const color = getBookColor(novel.genres);
  const PREVIEW_COUNT = 5;

  useEffect(() => {
    setLoadingCh(true);
    setExpanded(false); // Reset synopsis expansion on novel switch
    fetchChapters(novel._id, { limit: PREVIEW_COUNT, offset: 0 })
      .then((res) => setChapters(res.data || []))
      .catch(() => {})
      .finally(() => setLoadingCh(false));
  }, [novel._id]);

  // Fetch own novel list if parent hasn't loaded yet
  useEffect(() => {
    if (!allNovels || allNovels.length === 0) {
      fetchNovels({ limit: 100 })
        .then((res) => setLocalNovels(res.data || []))
        .catch(() => {});
    }
  }, [allNovels]);

  const novelPool = allNovels && allNovels.length > 0 ? allNovels : localNovels;

  // "You'll like more of these" — novels sharing genres
  const similar = novelPool
    .filter((n) => n._id !== novel._id && n.genres?.some((g) => novel.genres?.includes(g)))
    .slice(0, 4);

  return (
    <div style={{ animation: 'fadeUp 0.5s ease', paddingBottom: 100 }}>
      {/* Hero */}
      <div
        style={{
          position: 'relative',
          padding: '60px 24px 40px',
          background: `linear-gradient(180deg, ${color}18 0%, #0D0C0B 100%)`
        }}
      >
        <MazePattern />
        <button
          onClick={onBack}
          style={{
            position: 'absolute',
            top: 54,
            left: 20,
            background: '#1A181680',
            border: '1px solid #2A2722',
            borderRadius: 20,
            padding: '6px 14px',
            color: '#6B6459',
            fontSize: 13,
            cursor: 'pointer',
            backdropFilter: 'blur(10px)',
            zIndex: 2
          }}
        >
          ← Back
        </button>
        <div
          style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 30 }}
        >
          <div style={{ marginBottom: 24 }}>
            <CoverImage novel={novel} size="lg" />
          </div>
          <div
            style={{
              fontFamily: "'Cormorant Garamond', serif",
              fontSize: 26,
              color: '#E8DCC8',
              fontWeight: 500,
              textAlign: 'center',
              lineHeight: 1.2,
              maxWidth: 300
            }}
          >
            {novel.title}
          </div>
          <div
            style={{
              fontSize: 13,
              color: '#6B6459',
              marginTop: 8,
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            {novel.author || 'Unknown'}
          </div>
        </div>
      </div>

      {/* Meta row — includes rank + rating */}
      <div
        style={{
          display: 'flex',
          justifyContent: 'center',
          gap: 24,
          padding: '24px 16px',
          borderBottom: '1px solid #1A1816',
          flexWrap: 'wrap'
        }}
      >
        {[
          novel.rank && { label: 'Rank', value: `#${novel.rank}` },
          novel.rating != null && { label: 'Rating', value: `★ ${novel.rating}` },
          novel.totalChapters && { label: 'Chapters', value: novel.totalChapters },
          novel.status && { label: 'Status', value: novel.status },
          novel.views && { label: 'Views', value: novel.views }
        ]
          .filter(Boolean)
          .map((m) => (
            <div key={m.label} style={{ textAlign: 'center' }}>
              <div
                style={{
                  fontSize: 15,
                  color: '#E8DCC8',
                  fontFamily: "'Cormorant Garamond', serif",
                  fontWeight: 600
                }}
              >
                {m.value}
              </div>
              <div
                style={{
                  fontSize: 9,
                  color: '#4A4640',
                  letterSpacing: '0.15em',
                  textTransform: 'uppercase',
                  marginTop: 4,
                  fontFamily: "'IBM Plex Mono', monospace"
                }}
              >
                {m.label}
              </div>
            </div>
          ))}
      </div>

      {/* Genres */}
      {novel.genres?.length > 0 && (
        <div style={{ padding: '20px 24px 8px', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {novel.genres.map((g) => (
            <span
              key={g}
              style={{
                display: 'inline-block',
                padding: '5px 12px',
                borderRadius: 14,
                border: `1px solid ${color}25`,
                color: `${color}CC`,
                fontSize: 11,
                fontFamily: "'IBM Plex Mono', monospace",
                background: `${color}08`
              }}
            >
              {g}
            </span>
          ))}
        </div>
      )}

      {/* Synopsis */}
      {novel.summary && (
        <div style={{ padding: '16px 24px 20px' }}>
          <div
            style={{
              fontSize: 10,
              color: '#4A4640',
              letterSpacing: '0.2em',
              textTransform: 'uppercase',
              marginBottom: 12,
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            Synopsis
          </div>
          <p
            style={{
              fontFamily: "'Cormorant Garamond', serif",
              fontSize: 16,
              color: '#A09888',
              lineHeight: 1.7,
              margin: 0,
              overflow: expanded ? 'visible' : 'hidden',
              display: expanded ? 'block' : '-webkit-box',
              WebkitLineClamp: expanded ? 'unset' : 4,
              WebkitBoxOrient: 'vertical'
            }}
          >
            {novel.summary}
          </p>
          {novel.summary.length > 200 && (
            <button
              onClick={() => setExpanded((v) => !v)}
              style={{
                background: 'none',
                border: 'none',
                color: '#C4A44A',
                fontSize: 12,
                cursor: 'pointer',
                padding: '8px 0',
                fontFamily: "'IBM Plex Mono', monospace"
              }}
            >
              {expanded ? 'Show less' : 'Read more'}
            </button>
          )}
        </div>
      )}

      {/* Start Reading */}
      {chapters.length > 0 && (
        <div style={{ padding: '4px 24px 20px' }}>
          <button
            onClick={() => onReadChapter(chapters[0])}
            style={{
              width: '100%',
              padding: '16px',
              borderRadius: 14,
              border: 'none',
              background: `linear-gradient(135deg, ${color}, ${color}CC)`,
              color: '#0D0C0B',
              fontFamily: "'Cormorant Garamond', serif",
              fontSize: 17,
              fontWeight: 600,
              cursor: 'pointer',
              letterSpacing: '0.05em',
              transition: 'transform 0.2s ease, box-shadow 0.3s ease',
              boxShadow: `0 4px 20px ${color}30`
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.transform = 'translateY(-1px)';
              e.currentTarget.style.boxShadow = `0 8px 30px ${color}40`;
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.transform = 'translateY(0)';
              e.currentTarget.style.boxShadow = `0 4px 20px ${color}30`;
            }}
          >
            Start Reading
          </button>
        </div>
      )}

      {/* Chapter preview — only shows first few + "View All Chapters" button */}
      <div style={{ padding: '8px 24px 12px' }}>
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginBottom: 14
          }}
        >
          <div
            style={{
              fontSize: 10,
              color: '#4A4640',
              letterSpacing: '0.2em',
              textTransform: 'uppercase',
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            Chapters
          </div>
        </div>

        {loadingCh ? (
          <Spinner size={16} />
        ) : chapters.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '20px 16px' }}>
            <div
              style={{ fontSize: 13, color: '#4A4640', fontFamily: "'IBM Plex Mono', monospace" }}
            >
              {isOffline() ? 'Chapters require a live API connection' : 'No chapters available yet'}
            </div>
          </div>
        ) : (
          <>
            <div style={{ borderRadius: 14, border: '1px solid #2A2722', overflow: 'hidden' }}>
              {chapters.map((ch, i) => (
                <div
                  key={ch._id || i}
                  onClick={() => onReadChapter(ch)}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: '13px 16px',
                    cursor: 'pointer',
                    borderBottom: i < chapters.length - 1 ? '1px solid #1A1816' : 'none',
                    background: 'transparent',
                    transition: 'background 0.2s ease'
                  }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = '#1A1816')}
                  onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
                >
                  <div
                    style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 1, minWidth: 0 }}
                  >
                    <span
                      style={{
                        fontSize: 10,
                        color: '#4A4640',
                        fontFamily: "'IBM Plex Mono', monospace",
                        flexShrink: 0,
                        width: 36
                      }}
                    >
                      {ch.chapterNumber != null ? `#${ch.chapterNumber}` : ''}
                    </span>
                    <span
                      style={{
                        fontFamily: "'Cormorant Garamond', serif",
                        fontSize: 15,
                        color: '#C8B8A0',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap'
                      }}
                    >
                      {ch.title || `Chapter ${ch.chapterNumber}`}
                    </span>
                  </div>
                  <span style={{ color: '#2A2722', fontSize: 14, marginLeft: 8 }}>›</span>
                </div>
              ))}
            </div>

            {/* View All Chapters button */}
            <button
              onClick={onViewChapters}
              style={{
                width: '100%',
                padding: '14px',
                borderRadius: 12,
                marginTop: 12,
                border: '1px solid #2A2722',
                background: 'transparent',
                color: '#C4A44A',
                fontSize: 13,
                cursor: 'pointer',
                fontFamily: "'IBM Plex Mono', monospace",
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 8,
                transition: 'all 0.3s ease'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.borderColor = '#8B6914';
                e.currentTarget.style.background = '#8B691408';
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.borderColor = '#2A2722';
                e.currentTarget.style.background = 'transparent';
              }}
            >
              <span>View All Chapters</span>
              <span style={{ fontSize: 11 }}>→</span>
            </button>
          </>
        )}
      </div>

      {/* You'll Like More of These */}
      {similar.length > 0 && (
        <div style={{ padding: '24px 24px 8px' }}>
          <div
            style={{
              fontSize: 10,
              color: '#6B6459',
              letterSpacing: '0.2em',
              textTransform: 'uppercase',
              marginBottom: 14,
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            You'll Like More of These
          </div>
          <div style={{ display: 'flex', gap: 12, overflowX: 'auto', paddingBottom: 8 }}>
            {similar.map((n, i) => {
              const c = getBookColor(n.genres);
              return (
                <div
                  key={n._id}
                  onClick={() => onBack('switchNovel', n)}
                  style={{
                    minWidth: 130,
                    cursor: 'pointer',
                    animation: `fadeUp 0.4s ease ${i * 0.06}s both`
                  }}
                >
                  <div style={{ marginBottom: 8 }}>
                    <CoverImage novel={n} size="tile" />
                  </div>
                  <div
                    style={{
                      fontFamily: "'Cormorant Garamond', serif",
                      fontSize: 13,
                      color: '#E8DCC8',
                      fontWeight: 500,
                      lineHeight: 1.25,
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      display: '-webkit-box',
                      WebkitLineClamp: 2,
                      WebkitBoxOrient: 'vertical'
                    }}
                  >
                    {n.title}
                  </div>
                  <div
                    style={{
                      fontSize: 10,
                      color: '#6B6459',
                      marginTop: 3,
                      fontFamily: "'IBM Plex Mono', monospace"
                    }}
                  >
                    {n.author || 'Unknown'}
                  </div>
                  {n.rating != null && (
                    <div
                      style={{
                        fontSize: 10,
                        color: '#C4A44A',
                        fontFamily: "'IBM Plex Mono', monospace",
                        marginTop: 4
                      }}
                    >
                      ★ {n.rating}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}

function ChaptersScreen({ novel, onBack, onReadChapter }) {
  const [chapters, setChapters] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [page, setPage] = useState(0);
  const [totalCount, setTotalCount] = useState(0);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const debounceRef = useRef(null);
  const color = getBookColor(novel.genres);
  const PER_PAGE = 30;

  const loadChapters = useCallback(
    async (pg = 0, searchTerm = '') => {
      setLoading(true);
      setError(null);
      try {
        // Note: the API doesn't have chapter search, so we fetch more and filter client-side
        const fetchLimit = searchTerm ? 100 : PER_PAGE;
        const fetchOffset = searchTerm ? 0 : pg * PER_PAGE;
        const res = await fetchChapters(novel._id, { limit: fetchLimit, offset: fetchOffset });
        let data = res.data || [];
        let count = res.meta?.count || data.length;
        if (searchTerm) {
          const q = searchTerm.toLowerCase();
          data = data.filter(
            (ch) =>
              (ch.title || '').toLowerCase().includes(q) || String(ch.chapterNumber).includes(q)
          );
          count = data.length;
          data = data.slice(pg * PER_PAGE, (pg + 1) * PER_PAGE);
        }
        setChapters(data);
        setTotalCount(count);
      } catch (e) {
        setError(e.message);
      } finally {
        setLoading(false);
      }
    },
    [novel._id]
  );

  useEffect(() => {
    loadChapters(page, debouncedSearch);
  }, [loadChapters, page, debouncedSearch]);

  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setDebouncedSearch(search);
      setPage(0);
    }, 400);
    return () => clearTimeout(debounceRef.current);
  }, [search]);

  const totalPages = Math.ceil(totalCount / PER_PAGE);

  return (
    <div style={{ animation: 'fadeUp 0.5s ease', paddingBottom: 100 }}>
      {/* Header */}
      <div
        style={{
          position: 'relative',
          padding: '60px 24px 20px',
          background: `linear-gradient(180deg, ${color}0C 0%, #0D0C0B 100%)`
        }}
      >
        <button
          onClick={onBack}
          style={{
            position: 'absolute',
            top: 54,
            left: 20,
            background: '#1A181680',
            border: '1px solid #2A2722',
            borderRadius: 20,
            padding: '6px 14px',
            color: '#6B6459',
            fontSize: 13,
            cursor: 'pointer',
            backdropFilter: 'blur(10px)',
            zIndex: 2
          }}
        >
          ← Back
        </button>
        <div style={{ paddingTop: 28 }}>
          <div
            style={{
              fontFamily: "'Cormorant Garamond', serif",
              fontSize: 22,
              fontWeight: 400,
              color: '#E8DCC8',
              marginBottom: 4
            }}
          >
            {novel.title}
          </div>
          <div style={{ fontSize: 11, color: '#4A4640', fontFamily: "'IBM Plex Mono', monospace" }}>
            {totalCount > 0 ? `${totalCount} chapters` : 'Chapters'}
          </div>
        </div>
      </div>

      {/* Search */}
      <div style={{ padding: '12px 24px 16px' }}>
        <SearchInput
          value={search}
          onChange={setSearch}
          placeholder="Search chapters by title or number..."
        />
      </div>

      {/* Pagination header */}
      {totalPages > 1 && (
        <div
          style={{
            padding: '0 24px 12px',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center'
          }}
        >
          <span
            style={{ fontSize: 10, color: '#4A4640', fontFamily: "'IBM Plex Mono', monospace" }}
          >
            Page {page + 1} of {totalPages}
          </span>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <button
              disabled={page === 0}
              onClick={() => setPage((p) => p - 1)}
              style={{
                background: 'none',
                border: '1px solid #2A2722',
                borderRadius: 8,
                width: 32,
                height: 32,
                color: page === 0 ? '#1A1816' : '#6B6459',
                cursor: page === 0 ? 'default' : 'pointer',
                fontSize: 12
              }}
            >
              ◂
            </button>
            <button
              disabled={page >= totalPages - 1}
              onClick={() => setPage((p) => p + 1)}
              style={{
                background: 'none',
                border: '1px solid #2A2722',
                borderRadius: 8,
                width: 32,
                height: 32,
                color: page >= totalPages - 1 ? '#1A1816' : '#6B6459',
                cursor: page >= totalPages - 1 ? 'default' : 'pointer',
                fontSize: 12
              }}
            >
              ▸
            </button>
          </div>
        </div>
      )}

      {/* Chapter List */}
      <div style={{ padding: '0 24px' }}>
        {loading ? (
          <Spinner size={16} />
        ) : error ? (
          <ErrorMsg message={error} onRetry={() => loadChapters(page, debouncedSearch)} />
        ) : chapters.length === 0 ? (
          <div
            style={{
              textAlign: 'center',
              padding: '40px 0',
              color: '#4A4640',
              fontSize: 13,
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            {debouncedSearch
              ? 'No chapters match your search'
              : isOffline()
                ? 'Chapters require a live API connection'
                : 'No chapters found'}
          </div>
        ) : (
          <div style={{ borderRadius: 14, border: '1px solid #2A2722', overflow: 'hidden' }}>
            {chapters.map((ch, i) => (
              <div
                key={ch._id || i}
                onClick={() => onReadChapter(ch)}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  padding: '14px 16px',
                  cursor: 'pointer',
                  borderBottom: i < chapters.length - 1 ? '1px solid #1A1816' : 'none',
                  background: 'transparent',
                  transition: 'background 0.2s ease'
                }}
                onMouseEnter={(e) => (e.currentTarget.style.background = '#1A1816')}
                onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
              >
                <div
                  style={{ display: 'flex', alignItems: 'center', gap: 10, flex: 1, minWidth: 0 }}
                >
                  <span
                    style={{
                      fontSize: 10,
                      color: '#4A4640',
                      fontFamily: "'IBM Plex Mono', monospace",
                      flexShrink: 0,
                      width: 40
                    }}
                  >
                    {ch.chapterNumber != null ? `#${ch.chapterNumber}` : ''}
                  </span>
                  <span
                    style={{
                      fontFamily: "'Cormorant Garamond', serif",
                      fontSize: 15,
                      color: '#C8B8A0',
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap'
                    }}
                  >
                    {ch.title || `Chapter ${ch.chapterNumber}`}
                  </span>
                </div>
                <span style={{ color: '#2A2722', fontSize: 14, marginLeft: 8 }}>›</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Bottom pagination */}
      {totalPages > 1 && !loading && chapters.length > 0 && (
        <div style={{ padding: '20px 24px', display: 'flex', justifyContent: 'center', gap: 8 }}>
          <button
            disabled={page === 0}
            onClick={() => {
              setPage((p) => p - 1);
              window.scrollTo(0, 0);
            }}
            style={{
              padding: '10px 20px',
              borderRadius: 10,
              border: '1px solid #2A2722',
              background: 'transparent',
              color: page === 0 ? '#2A2722' : '#6B6459',
              fontSize: 12,
              cursor: page === 0 ? 'default' : 'pointer',
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            ← Previous
          </button>
          <button
            disabled={page >= totalPages - 1}
            onClick={() => {
              setPage((p) => p + 1);
              window.scrollTo(0, 0);
            }}
            style={{
              padding: '10px 20px',
              borderRadius: 10,
              border: `1px solid ${page >= totalPages - 1 ? '#2A2722' : color + '50'}`,
              background: page >= totalPages - 1 ? 'transparent' : `${color}10`,
              color: page >= totalPages - 1 ? '#2A2722' : '#C4A44A',
              fontSize: 12,
              cursor: page >= totalPages - 1 ? 'default' : 'pointer',
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            Next →
          </button>
        </div>
      )}
    </div>
  );
}

function ReaderScreen({
  chapter,
  novel,
  onBack,
  onNextChapter,
  onPrevChapter,
  hasPrev,
  hasNext,
  onUpdateProgress
}) {
  const [showControls, setShowControls] = useState(true);
  const [fontSize, setFontSize] = useState(19);
  const controlTimeout = useRef(null);
  const color = getBookColor(novel?.genres);

  const toggleControls = () => {
    setShowControls((v) => !v);
    if (controlTimeout.current) clearTimeout(controlTimeout.current);
    controlTimeout.current = setTimeout(() => setShowControls(false), 4000);
  };

  useEffect(() => {
    controlTimeout.current = setTimeout(() => setShowControls(false), 3500);
    return () => clearTimeout(controlTimeout.current);
  }, []);

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [chapter]);

  // Track reading progress
  useEffect(() => {
    if (chapter?.chapterNumber && novel?._id) {
      onUpdateProgress(novel._id, chapter.chapterNumber, chapter.title);
    }
  }, [chapter, novel, onUpdateProgress]);

  const paragraphs = (chapter?.content || 'No content available.')
    .split(/\n+/)
    .map((p) => p.trim())
    .filter((p) => p.length > 0);

  return (
    <div
      onClick={toggleControls}
      style={{ minHeight: '100vh', background: '#0D0C0B', position: 'relative' }}
    >
      <div
        style={{
          position: 'sticky',
          top: 0,
          left: 0,
          right: 0,
          padding: '50px 24px 12px',
          background: 'linear-gradient(180deg, #0D0C0B 60%, #0D0C0B00)',
          opacity: showControls ? 1 : 0,
          transition: 'opacity 0.4s ease',
          pointerEvents: showControls ? 'all' : 'none',
          zIndex: 10,
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center'
        }}
      >
        <button
          onClick={(e) => {
            e.stopPropagation();
            onBack();
          }}
          style={{
            background: 'none',
            border: '1px solid #2A2722',
            borderRadius: 20,
            padding: '6px 14px',
            color: '#6B6459',
            fontSize: 13,
            cursor: 'pointer'
          }}
        >
          ← Back
        </button>
        <div
          style={{
            fontSize: 11,
            color: '#4A4640',
            fontFamily: "'IBM Plex Mono', monospace",
            maxWidth: 160,
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            textAlign: 'center'
          }}
        >
          {novel?.title}
        </div>
        <div style={{ display: 'flex', gap: 8 }} onClick={(e) => e.stopPropagation()}>
          <button
            onClick={() => setFontSize((s) => Math.max(14, s - 1))}
            style={{
              background: 'none',
              border: '1px solid #2A2722',
              borderRadius: 8,
              width: 32,
              height: 32,
              color: '#6B6459',
              cursor: 'pointer',
              fontSize: 14
            }}
          >
            A-
          </button>
          <button
            onClick={() => setFontSize((s) => Math.min(28, s + 1))}
            style={{
              background: 'none',
              border: '1px solid #2A2722',
              borderRadius: 8,
              width: 32,
              height: 32,
              color: '#6B6459',
              cursor: 'pointer',
              fontSize: 16
            }}
          >
            A+
          </button>
        </div>
      </div>

      <div style={{ padding: '20px 32px 10px', textAlign: 'center' }}>
        {chapter?.chapterNumber != null && (
          <div
            style={{
              fontSize: 10,
              color: '#3A3530',
              letterSpacing: '0.25em',
              textTransform: 'uppercase',
              fontFamily: "'IBM Plex Mono', monospace",
              marginBottom: 8
            }}
          >
            Chapter {chapter.chapterNumber}
          </div>
        )}
        <div
          style={{
            fontFamily: "'Cormorant Garamond', serif",
            fontSize: 22,
            color: '#6B6459',
            fontWeight: 300,
            fontStyle: 'italic',
            lineHeight: 1.3
          }}
        >
          {chapter?.title || 'Untitled'}
        </div>
        <div style={{ width: 40, height: 1, background: '#2A2722', margin: '16px auto' }} />
      </div>

      <div style={{ padding: '10px 32px 140px', maxWidth: 640, margin: '0 auto' }}>
        {paragraphs.map((para, i) => (
          <p
            key={i}
            style={{
              fontFamily: "'Cormorant Garamond', serif",
              fontSize,
              lineHeight: 1.85,
              color: '#C8B8A0',
              margin: '0 0 20px 0',
              textIndent: i > 0 ? '2em' : 0
            }}
          >
            {para}
          </p>
        ))}
        <div
          style={{
            display: 'flex',
            justifyContent: 'center',
            gap: 16,
            padding: '40px 0 20px',
            borderTop: '1px solid #1A1816',
            marginTop: 20
          }}
        >
          {hasPrev && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onPrevChapter();
              }}
              style={{
                padding: '12px 24px',
                borderRadius: 12,
                border: '1px solid #2A2722',
                background: 'transparent',
                color: '#6B6459',
                fontSize: 14,
                cursor: 'pointer',
                fontFamily: "'Cormorant Garamond', serif"
              }}
            >
              ← Previous
            </button>
          )}
          {hasNext && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onNextChapter();
              }}
              style={{
                padding: '12px 24px',
                borderRadius: 12,
                border: `1px solid ${color}50`,
                background: `${color}10`,
                color: '#C4A44A',
                fontSize: 14,
                cursor: 'pointer',
                fontFamily: "'Cormorant Garamond', serif"
              }}
            >
              Next Chapter →
            </button>
          )}
        </div>
      </div>

      <div
        style={{
          position: 'fixed',
          bottom: 0,
          left: 0,
          right: 0,
          padding: '16px 24px 34px',
          background: 'linear-gradient(0deg, #0D0C0B, #0D0C0B 60%, #0D0C0B00)',
          opacity: showControls ? 1 : 0,
          transition: 'opacity 0.4s ease',
          pointerEvents: showControls ? 'all' : 'none',
          display: 'flex',
          justifyContent: 'center',
          gap: 24,
          zIndex: 11
        }}
        onClick={(e) => e.stopPropagation()}
      >
        {hasPrev && (
          <button
            onClick={onPrevChapter}
            style={{
              background: 'none',
              border: '1px solid #2A2722',
              borderRadius: 20,
              padding: '8px 20px',
              color: '#6B6459',
              fontSize: 12,
              cursor: 'pointer',
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            ◂ Prev
          </button>
        )}
        {hasNext && (
          <button
            onClick={onNextChapter}
            style={{
              background: 'none',
              border: `1px solid ${color}50`,
              borderRadius: 20,
              padding: '8px 20px',
              color: '#C4A44A',
              fontSize: 12,
              cursor: 'pointer',
              fontFamily: "'IBM Plex Mono', monospace"
            }}
          >
            Next ▸
          </button>
        )}
      </div>
    </div>
  );
}

function LibraryScreen({ onOpenNovel }) {
  const [novels, setNovels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const debounceRef = useRef(null);

  const load = useCallback(async (s = '') => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchNovels({ limit: 100, search: s });
      setNovels(res.data || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);
  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedSearch(search), 400);
    return () => clearTimeout(debounceRef.current);
  }, [search]);
  useEffect(() => {
    load(debouncedSearch);
  }, [debouncedSearch, load]);

  return (
    <div style={{ padding: '60px 24px 100px', animation: 'fadeUp 0.5s ease' }}>
      <div
        style={{
          fontFamily: "'Cormorant Garamond', serif",
          fontSize: 28,
          fontWeight: 300,
          color: '#E8DCC8',
          letterSpacing: '0.05em',
          marginBottom: 16
        }}
      >
        Library
      </div>
      <div style={{ marginBottom: 20 }}>
        <SearchInput
          value={search}
          onChange={setSearch}
          placeholder="Search by title or author..."
        />
      </div>
      {loading && novels.length === 0 ? (
        <Spinner />
      ) : error ? (
        <ErrorMsg message={error} onRetry={() => load(debouncedSearch)} />
      ) : novels.length === 0 ? (
        <div
          style={{
            textAlign: 'center',
            padding: '40px 0',
            color: '#4A4640',
            fontSize: 13,
            fontFamily: "'IBM Plex Mono', monospace"
          }}
        >
          {debouncedSearch ? 'No results' : 'Library is empty'}
        </div>
      ) : (
        novels.map((novel, i) => {
          const color = getBookColor(novel.genres);
          return (
            <div
              key={novel._id}
              onClick={() => onOpenNovel(novel)}
              style={{
                display: 'flex',
                gap: 16,
                padding: '16px 0',
                borderBottom: '1px solid #1A1816',
                cursor: 'pointer',
                animation: `fadeUp 0.4s ease ${i * 0.04}s both`
              }}
            >
              <CoverImage novel={novel} size="sm" />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontFamily: "'Cormorant Garamond', serif",
                    fontSize: 16,
                    color: '#E8DCC8',
                    fontWeight: 500,
                    lineHeight: 1.2,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap'
                  }}
                >
                  {novel.title}
                </div>
                <div
                  style={{
                    fontSize: 11,
                    color: '#6B6459',
                    marginTop: 3,
                    fontFamily: "'IBM Plex Mono', monospace"
                  }}
                >
                  {novel.author || 'Unknown'}
                  {novel.genres?.length ? ` · ${novel.genres[0]}` : ''}
                </div>
                <div style={{ display: 'flex', gap: 8, marginTop: 6, alignItems: 'center' }}>
                  {novel.rating != null && (
                    <span
                      style={{
                        fontSize: 10,
                        color: '#C4A44A',
                        fontFamily: "'IBM Plex Mono', monospace"
                      }}
                    >
                      ★ {novel.rating}
                    </span>
                  )}
                  {novel.status && (
                    <span
                      style={{
                        fontSize: 9,
                        color: '#4A4640',
                        fontFamily: "'IBM Plex Mono', monospace"
                      }}
                    >
                      {novel.status}
                    </span>
                  )}
                </div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center' }}>
                <span style={{ color: '#2A2722', fontSize: 16 }}>›</span>
              </div>
            </div>
          );
        })
      )}
    </div>
  );
}

function RankingsScreen({ onOpenNovel }) {
  const [novels, setNovels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [sortBy, setSortBy] = useState('rank');

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetchNovels({ limit: 100 });
      setNovels(res.data || []);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const sorted = [...novels].sort((a, b) => {
    if (sortBy === 'rank') return (parseInt(a.rank) || 9999) - (parseInt(b.rank) || 9999);
    if (sortBy === 'rating') return (b.rating || 0) - (a.rating || 0);
    if (sortBy === 'views') {
      const p = (v) => parseInt(String(v || '0').replace(/[^0-9]/g, '')) || 0;
      return p(b.views) - p(a.views);
    }
    return 0;
  });

  const medals = ['🥇', '🥈', '🥉'];

  return (
    <div style={{ padding: '60px 24px 100px', animation: 'fadeUp 0.5s ease' }}>
      <div
        style={{
          fontFamily: "'Cormorant Garamond', serif",
          fontSize: 28,
          fontWeight: 300,
          color: '#E8DCC8',
          letterSpacing: '0.05em',
          marginBottom: 6
        }}
      >
        Rankings
      </div>
      <div
        style={{
          fontSize: 11,
          color: '#4A4640',
          fontFamily: "'IBM Plex Mono', monospace",
          marginBottom: 20
        }}
      >
        {novels.length > 0 ? `${novels.length} novels ranked` : ''}
      </div>
      <div
        style={{ display: 'flex', gap: 8, marginBottom: 24, overflowX: 'auto', paddingBottom: 4 }}
      >
        {[
          { key: 'rank', label: 'By Rank' },
          { key: 'rating', label: 'By Rating' },
          { key: 'views', label: 'By Views' }
        ].map((s) => (
          <button
            key={s.key}
            onClick={() => setSortBy(s.key)}
            style={{
              padding: '8px 16px',
              borderRadius: 20,
              whiteSpace: 'nowrap',
              border: `1px solid ${sortBy === s.key ? '#8B6914' : '#2A2722'}`,
              background: sortBy === s.key ? '#8B691412' : 'transparent',
              color: sortBy === s.key ? '#C4A44A' : '#6B6459',
              fontSize: 12,
              cursor: 'pointer',
              fontFamily: "'IBM Plex Mono', monospace",
              transition: 'all 0.3s ease'
            }}
          >
            {s.label}
          </button>
        ))}
      </div>
      {loading ? (
        <Spinner />
      ) : error ? (
        <ErrorMsg message={error} onRetry={load} />
      ) : sorted.length === 0 ? (
        <div
          style={{
            textAlign: 'center',
            padding: '48px 0',
            color: '#4A4640',
            fontSize: 13,
            fontFamily: "'IBM Plex Mono', monospace"
          }}
        >
          No novels found
        </div>
      ) : (
        sorted.map((novel, i) => {
          const isTop3 = i < 3;
          return (
            <div
              key={novel._id}
              onClick={() => onOpenNovel(novel)}
              style={{
                display: 'flex',
                gap: 14,
                padding: isTop3 ? '18px 16px' : '14px 0',
                cursor: 'pointer',
                alignItems: 'center',
                background: isTop3 ? '#1A181680' : 'transparent',
                borderRadius: isTop3 ? 14 : 0,
                marginBottom: isTop3 ? 8 : 0,
                border: isTop3 ? '1px solid #2A2722' : 'none',
                borderBottom: !isTop3 ? '1px solid #1A1816' : undefined,
                animation: `fadeUp 0.4s ease ${i * 0.04}s both`,
                transition: 'background 0.2s ease'
              }}
              onMouseEnter={(e) =>
                (e.currentTarget.style.background = isTop3 ? '#1E1C19' : '#1A181640')
              }
              onMouseLeave={(e) =>
                (e.currentTarget.style.background = isTop3 ? '#1A181680' : 'transparent')
              }
            >
              <div
                style={{
                  width: 36,
                  textAlign: 'center',
                  flexShrink: 0,
                  fontFamily: "'Cormorant Garamond', serif",
                  fontSize: isTop3 ? 20 : 14,
                  color: isTop3 ? '#C4A44A' : '#3A3530',
                  fontWeight: isTop3 ? 600 : 400
                }}
              >
                {isTop3 ? (
                  medals[i]
                ) : (
                  <span style={{ fontFamily: "'IBM Plex Mono', monospace", fontSize: 11 }}>
                    {i + 1}
                  </span>
                )}
              </div>
              <CoverImage novel={novel} size={isTop3 ? 'md' : 'sm'} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div
                  style={{
                    fontFamily: "'Cormorant Garamond', serif",
                    fontSize: isTop3 ? 17 : 15,
                    color: '#E8DCC8',
                    fontWeight: 500,
                    lineHeight: 1.2,
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap'
                  }}
                >
                  {novel.title}
                </div>
                <div
                  style={{
                    fontSize: 11,
                    color: '#6B6459',
                    marginTop: 3,
                    fontFamily: "'IBM Plex Mono', monospace"
                  }}
                >
                  {novel.author || 'Unknown'}
                </div>
                <div
                  style={{
                    display: 'flex',
                    gap: 10,
                    marginTop: 6,
                    alignItems: 'center',
                    flexWrap: 'wrap'
                  }}
                >
                  {novel.rating != null && (
                    <span
                      style={{
                        fontSize: 11,
                        color: '#C4A44A',
                        fontFamily: "'IBM Plex Mono', monospace"
                      }}
                    >
                      ★ {novel.rating}
                    </span>
                  )}
                  {novel.views && (
                    <span
                      style={{
                        fontSize: 10,
                        color: '#4A4640',
                        fontFamily: "'IBM Plex Mono', monospace"
                      }}
                    >
                      {novel.views} views
                    </span>
                  )}
                  {novel.status && (
                    <span
                      style={{
                        fontSize: 9,
                        padding: '2px 7px',
                        borderRadius: 8,
                        border: `1px solid ${novel.status === 'Ongoing' ? '#3A6B5A' : '#6B5B4B'}40`,
                        color: novel.status === 'Ongoing' ? '#5A9B7A' : '#8B7B6B',
                        fontFamily: "'IBM Plex Mono', monospace"
                      }}
                    >
                      {novel.status}
                    </span>
                  )}
                </div>
              </div>
              <span style={{ color: '#2A2722', fontSize: 16, flexShrink: 0 }}>›</span>
            </div>
          );
        })
      )}
    </div>
  );
}

function ProfileScreen({ novels: novelsProp }) {
  const [readingGoal, setReadingGoal] = useState(30);
  const [darkMode, setDarkMode] = useState(true);
  const [notificationsOn, setNotificationsOn] = useState(true);
  const [fontSizePref, setFontSizePref] = useState('medium');
  const [localNovels, setLocalNovels] = useState([]);

  useEffect(() => {
    if (!novelsProp || novelsProp.length === 0) {
      fetchNovels({ limit: 100 })
        .then((res) => setLocalNovels(res.data || []))
        .catch(() => {});
    }
  }, [novelsProp]);

  const novels = novelsProp && novelsProp.length > 0 ? novelsProp : localNovels;

  const totalNovels = novels.length;
  const ongoing = novels.filter((n) => n.status === 'Ongoing').length;
  const completed = novels.filter((n) => n.status === 'Completed').length;
  const totalChapters = novels.reduce(
    (sum, n) => sum + (parseInt(String(n.totalChapters).replace(/[^0-9]/g, '')) || 0),
    0
  );
  const avgRating =
    novels.length > 0
      ? (novels.reduce((sum, n) => sum + (n.rating || 0), 0) / novels.length).toFixed(1)
      : '—';

  const Toggle = ({ on, onToggle }) => (
    <div
      onClick={onToggle}
      style={{
        width: 44,
        height: 24,
        borderRadius: 12,
        cursor: 'pointer',
        background: on ? '#8B6914' : '#2A2722',
        transition: 'background 0.3s ease',
        position: 'relative',
        border: `1px solid ${on ? '#C4A44A30' : '#3A3530'}`
      }}
    >
      <div
        style={{
          width: 18,
          height: 18,
          borderRadius: '50%',
          background: on ? '#E8DCC8' : '#4A4640',
          position: 'absolute',
          top: 2,
          left: on ? 22 : 2,
          transition: 'left 0.3s ease, background 0.3s ease'
        }}
      />
    </div>
  );

  const SettingsRow = ({ label, sublabel, right, noBorder }) => (
    <div
      style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: '16px 0',
        borderBottom: noBorder ? 'none' : '1px solid #1A1816'
      }}
    >
      <div>
        <div style={{ fontSize: 15, color: '#C8B8A0', fontFamily: "'Cormorant Garamond', serif" }}>
          {label}
        </div>
        {sublabel && (
          <div
            style={{
              fontSize: 11,
              color: '#4A4640',
              fontFamily: "'IBM Plex Mono', monospace",
              marginTop: 3
            }}
          >
            {sublabel}
          </div>
        )}
      </div>
      {right}
    </div>
  );

  return (
    <div style={{ padding: '60px 24px 120px', animation: 'fadeUp 0.5s ease' }}>
      <div
        style={{
          fontFamily: "'Cormorant Garamond', serif",
          fontSize: 28,
          fontWeight: 300,
          color: '#E8DCC8',
          letterSpacing: '0.05em',
          marginBottom: 32
        }}
      >
        Profile
      </div>

      {/* Avatar */}
      <div style={{ textAlign: 'center', marginBottom: 36 }}>
        <div
          style={{
            width: 80,
            height: 80,
            borderRadius: '50%',
            margin: '0 auto 16px',
            background: 'linear-gradient(135deg, #8B691425, #C4A44A18)',
            border: '1px solid #2A2722',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            position: 'relative'
          }}
        >
          <span
            style={{
              fontFamily: "'Cormorant Garamond', serif",
              fontSize: 32,
              color: '#C4A44A',
              fontWeight: 300
            }}
          >
            A
          </span>
          <div
            style={{
              position: 'absolute',
              bottom: -2,
              right: -2,
              width: 22,
              height: 22,
              borderRadius: '50%',
              background: '#0D0C0B',
              border: '1px solid #2A2722',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              fontSize: 11
            }}
          >
            📖
          </div>
        </div>
        <div
          style={{
            fontFamily: "'Cormorant Garamond', serif",
            fontSize: 22,
            color: '#E8DCC8',
            fontWeight: 400
          }}
        >
          Reader
        </div>
        <div
          style={{
            fontSize: 11,
            color: '#4A4640',
            fontFamily: "'IBM Plex Mono', monospace",
            marginTop: 4
          }}
        >
          Member since 2024
        </div>
      </div>

      {/* Stats */}
      <div
        style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10, marginBottom: 32 }}
      >
        {[
          { value: totalNovels, label: 'Novels' },
          { value: totalChapters.toLocaleString(), label: 'Chapters' },
          { value: avgRating, label: 'Avg Rating' }
        ].map((s) => (
          <div
            key={s.label}
            style={{
              background: '#1A1816',
              borderRadius: 14,
              padding: '18px 10px',
              textAlign: 'center',
              border: '1px solid #2A2722'
            }}
          >
            <div
              style={{
                fontFamily: "'Cormorant Garamond', serif",
                fontSize: 22,
                color: '#E8DCC8',
                fontWeight: 500
              }}
            >
              {s.value}
            </div>
            <div
              style={{
                fontSize: 9,
                color: '#4A4640',
                letterSpacing: '0.15em',
                textTransform: 'uppercase',
                marginTop: 6,
                fontFamily: "'IBM Plex Mono', monospace"
              }}
            >
              {s.label}
            </div>
          </div>
        ))}
      </div>

      {/* Status */}
      <div
        style={{
          background: '#1A1816',
          borderRadius: 14,
          padding: '18px 20px',
          border: '1px solid #2A2722',
          marginBottom: 32
        }}
      >
        <div
          style={{
            fontSize: 10,
            color: '#4A4640',
            letterSpacing: '0.15em',
            textTransform: 'uppercase',
            fontFamily: "'IBM Plex Mono', monospace",
            marginBottom: 14
          }}
        >
          Reading Status
        </div>
        <div style={{ display: 'flex', gap: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 8, height: 8, borderRadius: '50%', background: '#5A9B7A' }} />
            <span
              style={{ fontSize: 13, color: '#A09888', fontFamily: "'Cormorant Garamond', serif" }}
            >
              {ongoing} Ongoing
            </span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ width: 8, height: 8, borderRadius: '50%', background: '#8B6914' }} />
            <span
              style={{ fontSize: 13, color: '#A09888', fontFamily: "'Cormorant Garamond', serif" }}
            >
              {completed} Completed
            </span>
          </div>
        </div>
        {totalNovels > 0 && (
          <div
            style={{
              height: 4,
              borderRadius: 2,
              background: '#2A2722',
              marginTop: 14,
              overflow: 'hidden',
              display: 'flex'
            }}
          >
            <div
              style={{
                width: `${(ongoing / totalNovels) * 100}%`,
                height: '100%',
                background: '#5A9B7A'
              }}
            />
            <div
              style={{
                width: `${(completed / totalNovels) * 100}%`,
                height: '100%',
                background: '#8B6914'
              }}
            />
          </div>
        )}
      </div>

      {/* Reading Preferences */}
      <div
        style={{
          fontSize: 10,
          color: '#4A4640',
          letterSpacing: '0.2em',
          textTransform: 'uppercase',
          marginBottom: 12,
          fontFamily: "'IBM Plex Mono', monospace"
        }}
      >
        Reading Preferences
      </div>
      <div
        style={{
          background: '#1A1816',
          borderRadius: 14,
          padding: '4px 20px',
          border: '1px solid #2A2722',
          marginBottom: 24
        }}
      >
        <SettingsRow
          label="Font Size"
          sublabel={fontSizePref.charAt(0).toUpperCase() + fontSizePref.slice(1)}
          right={
            <div style={{ display: 'flex', gap: 6 }}>
              {['small', 'medium', 'large'].map((sz) => (
                <button
                  key={sz}
                  onClick={() => setFontSizePref(sz)}
                  style={{
                    width: 32,
                    height: 32,
                    borderRadius: 8,
                    cursor: 'pointer',
                    border: `1px solid ${fontSizePref === sz ? '#8B6914' : '#2A2722'}`,
                    background: fontSizePref === sz ? '#8B691418' : 'transparent',
                    color: fontSizePref === sz ? '#C4A44A' : '#4A4640',
                    fontSize: sz === 'small' ? 12 : sz === 'medium' ? 15 : 18,
                    fontFamily: "'Cormorant Garamond', serif",
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center'
                  }}
                >
                  A
                </button>
              ))}
            </div>
          }
        />
        <SettingsRow
          label="Reading Goal"
          sublabel={`${readingGoal} chapters / week`}
          right={
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <button
                onClick={() => setReadingGoal((g) => Math.max(5, g - 5))}
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: 8,
                  border: '1px solid #2A2722',
                  background: 'transparent',
                  color: '#6B6459',
                  cursor: 'pointer',
                  fontSize: 14
                }}
              >
                −
              </button>
              <span
                style={{
                  fontSize: 14,
                  color: '#E8DCC8',
                  fontFamily: "'IBM Plex Mono', monospace",
                  minWidth: 24,
                  textAlign: 'center'
                }}
              >
                {readingGoal}
              </span>
              <button
                onClick={() => setReadingGoal((g) => Math.min(100, g + 5))}
                style={{
                  width: 28,
                  height: 28,
                  borderRadius: 8,
                  border: '1px solid #2A2722',
                  background: 'transparent',
                  color: '#6B6459',
                  cursor: 'pointer',
                  fontSize: 14
                }}
              >
                +
              </button>
            </div>
          }
        />
        <SettingsRow
          label="Dark Mode"
          sublabel="Optimized for night reading"
          noBorder
          right={<Toggle on={darkMode} onToggle={() => setDarkMode((v) => !v)} />}
        />
      </div>

      {/* Notifications */}
      <div
        style={{
          fontSize: 10,
          color: '#4A4640',
          letterSpacing: '0.2em',
          textTransform: 'uppercase',
          marginBottom: 12,
          fontFamily: "'IBM Plex Mono', monospace"
        }}
      >
        Notifications
      </div>
      <div
        style={{
          background: '#1A1816',
          borderRadius: 14,
          padding: '4px 20px',
          border: '1px solid #2A2722',
          marginBottom: 24
        }}
      >
        <SettingsRow
          label="New Chapters"
          sublabel="Get notified when novels update"
          right={<Toggle on={notificationsOn} onToggle={() => setNotificationsOn((v) => !v)} />}
        />
        <SettingsRow
          label="Siri Shortcuts"
          sublabel="Quick access to reading"
          noBorder
          right={<span style={{ fontSize: 14, color: '#2A2722' }}>›</span>}
        />
      </div>

      {/* About */}
      <div
        style={{
          fontSize: 10,
          color: '#4A4640',
          letterSpacing: '0.2em',
          textTransform: 'uppercase',
          marginBottom: 12,
          fontFamily: "'IBM Plex Mono', monospace"
        }}
      >
        About
      </div>
      <div
        style={{
          background: '#1A1816',
          borderRadius: 14,
          padding: '4px 20px',
          border: '1px solid #2A2722',
          marginBottom: 24
        }}
      >
        {['Widget Setup', 'Rate Asterion', 'Privacy Policy', 'Terms of Service'].map(
          (item, i, arr) => (
            <SettingsRow
              key={item}
              label={item}
              noBorder={i === arr.length - 1}
              right={<span style={{ fontSize: 14, color: '#2A2722' }}>›</span>}
            />
          )
        )}
      </div>

      <div style={{ textAlign: 'center', padding: '16px 0 8px' }}>
        <div
          style={{
            fontFamily: "'Cormorant Garamond', serif",
            fontSize: 16,
            color: '#3A3530',
            fontWeight: 300,
            letterSpacing: '0.08em'
          }}
        >
          Asterion
        </div>
        <div
          style={{
            fontSize: 10,
            color: '#2A2722',
            fontFamily: "'IBM Plex Mono', monospace",
            marginTop: 4
          }}
        >
          v1.0.0
        </div>
      </div>
    </div>
  );
}

// ==================== MAIN APP ====================

export default function Asterion() {
  const [screen, setScreen] = useState('home');
  const [selectedNovel, setSelectedNovel] = useState(null);
  const [selectedChapter, setSelectedChapter] = useState(null);
  const [chapterList, setChapterList] = useState([]);
  const [tab, setTab] = useState('home');
  const [previousTab, setPreviousTab] = useState('home');
  const [readerEnteredFrom, setReaderEnteredFrom] = useState('detail');
  const [loadingChapter, setLoadingChapter] = useState(false);
  const [offlineMode, setOfflineMode] = useState(false);
  const [allNovels, setAllNovels] = useState([]);
  const [progress, setProgressState] = useState(INITIAL_PROGRESS);

  const updateProgress = useCallback((novelId, chapterNum, chapterTitle) => {
    setProgressState((prev) => ({
      ...prev,
      [novelId]: { chapterNum, chapterTitle, timestamp: Date.now() }
    }));
  }, []);

  useEffect(() => {
    fetchNovels({ limit: 100 })
      .then((res) => setAllNovels(res.data || []))
      .catch(() => {});
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => setOfflineMode(isOffline()), 2000);
    return () => clearTimeout(timer);
  }, []); // Run once, not every render

  const openNovel = (novel) => {
    setPreviousTab(tab);
    setSelectedNovel(novel);
    setScreen('detail');
  };

  const readChapter = async (ch) => {
    setReaderEnteredFrom(screen); // Remember where we came from
    setLoadingChapter(true);
    try {
      const full = await fetchChapter(ch._id);
      setSelectedChapter(full.data || full);
      const res = await fetchChapters(selectedNovel._id, { limit: 100, offset: 0 });
      setChapterList(res.data || []);
      setScreen('reader');
    } catch {
      setSelectedChapter(ch);
      setScreen('reader');
    }
    setLoadingChapter(false);
  };

  const navigateChapter = async (direction) => {
    if (!selectedChapter || !chapterList.length) return;
    const idx = chapterList.findIndex((c) => c._id === selectedChapter._id);
    const next = idx + direction;
    if (next >= 0 && next < chapterList.length) {
      setLoadingChapter(true);
      try {
        const full = await fetchChapter(chapterList[next]._id);
        setSelectedChapter(full.data || full);
      } catch {
        setSelectedChapter(chapterList[next]);
      }
      setLoadingChapter(false);
    }
  };

  const currentIdx = chapterList.findIndex((c) => c._id === selectedChapter?._id);

  const goBack = () => {
    setScreen(previousTab);
    setTab(previousTab);
  };
  const navigate = (t) => {
    setTab(t);
    setScreen(t);
  };

  const handleDetailBack = (action, novel) => {
    if (action === 'switchNovel' && novel) {
      setSelectedNovel(novel);
      setScreen('detail');
      window.scrollTo(0, 0);
    } else {
      goBack();
    }
  };

  return (
    <div
      style={{
        maxWidth: 430,
        margin: '0 auto',
        minHeight: '100vh',
        background: '#0D0C0B',
        color: '#E8DCC8',
        position: 'relative',
        fontFamily: "'Cormorant Garamond', serif",
        boxShadow: '0 0 80px #00000080',
        overflow: 'hidden'
      }}
    >
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,300;0,400;0,500;0,600;1,300;1,400&family=IBM+Plex+Mono:wght@300;400;500&display=swap');
        * { box-sizing: border-box; -webkit-font-smoothing: antialiased; }
        body { margin: 0; background: #050504; }
        ::-webkit-scrollbar { width: 0; height: 0; }
        @keyframes fadeUp { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: translateY(0); } }
        @keyframes spin { to { transform: rotate(360deg); } }
      `}</style>

      <MazePattern />

      {loadingChapter && (
        <div
          style={{
            position: 'fixed',
            inset: 0,
            background: '#0D0C0BDD',
            zIndex: 100,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 16
          }}
        >
          <Spinner size={24} />
          <div style={{ fontSize: 12, color: '#4A4640', fontFamily: "'IBM Plex Mono', monospace" }}>
            Loading chapter…
          </div>
        </div>
      )}

      {offlineMode && screen !== 'reader' && (
        <div
          style={{
            position: 'fixed',
            top: 0,
            left: '50%',
            transform: 'translateX(-50%)',
            maxWidth: 430,
            width: '100%',
            zIndex: 30,
            padding: '48px 20px 8px',
            background: 'linear-gradient(180deg, #0D0C0B, #0D0C0B00)'
          }}
        >
          <div
            style={{
              padding: '8px 14px',
              borderRadius: 10,
              background: '#1A181890',
              border: '1px solid #2A2722',
              backdropFilter: 'blur(12px)',
              display: 'flex',
              alignItems: 'center',
              gap: 8
            }}
          >
            <span style={{ fontSize: 10, opacity: 0.6 }}>📡</span>
            <span
              style={{
                fontSize: 10,
                color: '#6B6459',
                fontFamily: "'IBM Plex Mono', monospace",
                flex: 1
              }}
            >
              Sandbox mode — showing cached data
            </span>
          </div>
        </div>
      )}

      <div style={{ position: 'relative', zIndex: 1, minHeight: '100vh' }}>
        {screen === 'home' && <HomeScreen onOpenNovel={openNovel} progress={progress} />}
        {screen === 'detail' && selectedNovel && (
          <BookDetailScreen
            novel={selectedNovel}
            onBack={handleDetailBack}
            onReadChapter={readChapter}
            onViewChapters={() => setScreen('chapters')}
            allNovels={allNovels}
          />
        )}
        {screen === 'chapters' && selectedNovel && (
          <ChaptersScreen
            novel={selectedNovel}
            onBack={() => setScreen('detail')}
            onReadChapter={readChapter}
          />
        )}
        {screen === 'reader' && selectedChapter && (
          <ReaderScreen
            chapter={selectedChapter}
            novel={selectedNovel}
            onBack={() => setScreen(readerEnteredFrom)}
            onNextChapter={() => navigateChapter(1)}
            onPrevChapter={() => navigateChapter(-1)}
            hasPrev={currentIdx > 0}
            hasNext={currentIdx < chapterList.length - 1}
            onUpdateProgress={updateProgress}
          />
        )}
        {screen === 'library' && <LibraryScreen onOpenNovel={openNovel} />}
        {screen === 'rankings' && <RankingsScreen onOpenNovel={openNovel} />}
        {screen === 'profile' && <ProfileScreen novels={allNovels} />}
      </div>

      {!['reader', 'chapters'].includes(screen) && (
        <div
          style={{
            position: 'fixed',
            bottom: 0,
            left: '50%',
            transform: 'translateX(-50%)',
            width: '100%',
            maxWidth: 430,
            background: 'linear-gradient(0deg, #0D0C0B, #0D0C0BF0 70%, #0D0C0B00)',
            padding: '12px 0 28px',
            zIndex: 20
          }}
        >
          <div
            style={{
              display: 'flex',
              justifyContent: 'space-around',
              maxWidth: 340,
              margin: '0 auto'
            }}
          >
            {[
              { id: 'home', icon: '◈', label: 'Discover' },
              { id: 'rankings', icon: '♛', label: 'Rankings' },
              { id: 'library', icon: '▤', label: 'Library' },
              { id: 'profile', icon: '○', label: 'Profile' }
            ].map((t) => (
              <button
                key={t.id}
                onClick={() => navigate(t.id)}
                style={{
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  gap: 4,
                  color: tab === t.id ? '#C4A44A' : '#4A4640',
                  transition: 'color 0.3s ease',
                  padding: '4px 16px'
                }}
              >
                <span style={{ fontSize: 18, lineHeight: 1 }}>{t.icon}</span>
                <span
                  style={{
                    fontSize: 9,
                    letterSpacing: '0.1em',
                    fontFamily: "'IBM Plex Mono', monospace"
                  }}
                >
                  {t.label}
                </span>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
