// Islet for YouTube Music: reports playback to Islet and runs its playback commands.
// Talks only to this extension's service worker, which relays to Islet on ws://127.0.0.1:47811.

function readState() {
  const video = document.querySelector('video');
  const meta = navigator.mediaSession && navigator.mediaSession.metadata;
  const bar = document.querySelector('ytmusic-player-bar');
  const title = (meta && meta.title) || bar?.querySelector('.title')?.textContent?.trim() || '';
  if (!video || !title) return null;
  const artist = (meta && meta.artist) || bar?.querySelector('.byline')?.textContent?.split('•')[0]?.trim() || '';
  const artwork = meta && meta.artwork && meta.artwork.length
    ? meta.artwork[meta.artwork.length - 1].src
    : bar?.querySelector('img')?.src || '';
  return {
    playing: !video.paused,
    title,
    artist,
    album: (meta && meta.album) || '',
    duration: Number.isFinite(video.duration) ? video.duration : 0,
    position: video.currentTime || 0,
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
  const video = document.querySelector('video');
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
