// Relays YouTube Music state to Islet over a local WebSocket, and Islet's commands back to the tab.
// Islet pings every 20 s, which keeps this service worker alive while Islet is running.

const ISLET_URL = 'ws://127.0.0.1:47811';

let socket = null;
let lastClose = 0;
let pending = null;   // latest message waiting for the socket to open
let playerTab = null; // the YouTube Music tab Islet is following

function connect() {
  if (socket || Date.now() - lastClose < 3000) return;
  const ws = new WebSocket(ISLET_URL);
  socket = ws;
  ws.onopen = () => {
    if (pending) ws.send(pending);
    pending = null;
  };
  ws.onmessage = (event) => {
    let msg;
    try { msg = JSON.parse(event.data); } catch (_) { return; }
    if (msg.type !== 'command' || playerTab === null) return;
    if (msg.command === 'focus') {
      focusTab(playerTab);
    } else {
      chrome.tabs.sendMessage(playerTab, msg).catch(() => {});
    }
  };
  ws.onclose = () => {
    if (socket === ws) socket = null;
    lastClose = Date.now();
  };
}

// Brings the playing YouTube Music tab and its window to the front.
async function focusTab(tabId) {
  try {
    const tab = await chrome.tabs.update(tabId, { active: true });
    await chrome.windows.update(tab.windowId, { focused: true });
  } catch (_) {}
}

function forward(state) {
  const text = JSON.stringify({ type: 'state', state });
  if (socket && socket.readyState === WebSocket.OPEN) {
    socket.send(text);
  } else {
    pending = text;
    connect();
  }
}

chrome.runtime.onMessage.addListener((msg, sender) => {
  if (msg?.type !== 'state' || !sender.tab) return;
  const tab = sender.tab.id;
  // Follow whichever tab is playing; ignore other idle YouTube Music tabs.
  if (msg.state && (msg.state.playing || playerTab === null)) playerTab = tab;
  if (tab !== playerTab) return;
  forward(msg.state);
  if (!msg.state) playerTab = null;
});

chrome.tabs.onRemoved.addListener((tab) => {
  if (tab !== playerTab) return;
  playerTab = null;
  forward(null);
});
