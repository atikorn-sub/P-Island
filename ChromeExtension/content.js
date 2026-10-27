// Islet for YouTube Music: reports playback to Islet and runs its playback commands.
// Talks only to this extension's service worker, which relays to Islet on ws://127.0.0.1:47811.

// The page can hold more than one <video>; the player's own is the one that's playing.
function mainVideo() {
  return document.querySelector('ytmusic-player video, video.html5-main-video') || document.querySelector('video');
}

function seconds(text) {
  return text.split(':').reduce((total, part) => total * 60 + Number(part), 0);
}

// Length and position as the player bar shows them. The <video>'s own duration can be far longer
// than the song (it was ~26 min for a 4 min track), so the bar is the source of truth.
function barTimes(bar) {
  const slider = bar?.querySelector('#progress-bar');
  const max = Number(slider?.getAttribute('aria-valuemax'));
  const now = Number(slider?.getAttribute('aria-valuenow'));
  if (max > 0) return { duration: max, position: Number.isFinite(now) ? now : null };
  const match = (bar?.querySelector('.time-info')?.textContent || '').match(/([\d:]+)\s*\/\s*([\d:]+)/);
  if (match) return { duration: seconds(match[2]), position: seconds(match[1]) };
  return null;
}

function readState() {
  const video = mainVideo();
  const meta = navigator.mediaSession && navigator.mediaSession.metadata;
  const bar = document.querySelector('ytmusic-player-bar');
  const title = (meta && meta.title) || bar?.querySelector('.title')?.textContent?.trim() || '';
  if (!video || !title) return null;
  const artist = (meta && meta.artist) || bar?.querySelector('.byline')?.textContent?.split('•')[0]?.trim() || '';
  const artwork = meta && meta.artwork && meta.artwork.length
    ? meta.artwork[meta.artwork.length - 1].src
    : bar?.querySelector('img')?.src || '';
  const times = barTimes(bar);
  const duration = times?.duration || (Number.isFinite(video.duration) ? video.duration : 0);
  // The video's clock is smoother; use it unless it disagrees with the bar's length.
  const position = video.currentTime <= duration + 1 ? video.currentTime : (times?.position ?? 0);
  return {
    playing: !video.paused,
    title,
    artist,
    album: (meta && meta.album) || '',
    duration,
    position: position || 0,
    artwork,
  };
}

let alive = true;

function send(state) {
  if (!alive) return;
  try {
    chrome.runtime.sendMessage({ type: 'state', state }).catch(() => {});
  } catch (_) {
    alive = false; // the extension was reloaded; this copy of the script is orphaned
  }
}

function report() {
  let state = null;
  try { state = readState(); } catch (_) {}
  send(state);
}

function run(command) {
  const video = mainVideo();
  switch (command.command) {
    case 'playPause': {
      const button = document.querySelector('#play-pause-button');
      if (button) button.click();
      else if (video) video.paused ? video.play() : video.pause();
      break;
    }
    case 'next':
      document.querySelector('.next-button')?.click();
      break;
    case 'previous':
      document.querySelector('.previous-button')?.click();
      break;
    case 'seek':
      if (video && typeof command.value === 'number') video.currentTime = command.value;
      break;
  }
  setTimeout(report, 250);
}

chrome.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === 'command') run(msg);
});

// Media events don't bubble, so listen in the capture phase.
for (const name of ['play', 'pause', 'seeked', 'loadedmetadata']) {
  document.addEventListener(name, report, true);
}
window.addEventListener('pagehide', () => send(null));
setInterval(report, 1000);
report();
