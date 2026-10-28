// Runs in the page's own JavaScript world, where YouTube Music's elements keep their data.
// Rows further down the queue haven't loaded their <img> yet, so this copies each row's cover URL
// onto the row as an attribute that content.js (which can't see that data) reads.

function findThumbnails(obj, depth) {
  if (!obj || typeof obj !== 'object' || depth > 6) return null;
  if (Array.isArray(obj.thumbnails) && obj.thumbnails.length && obj.thumbnails[0].url) return obj.thumbnails;
  for (const key of Object.keys(obj)) {
    const found = findThumbnails(obj[key], depth + 1);
    if (found) return found;
  }
  return null;
}

function tagCovers() {
  for (const row of document.querySelectorAll('ytmusic-player-queue-item')) {
    const thumbs = findThumbnails(row.data || row.__data?.data, 0);
    if (!thumbs) continue;
    // The notch shows 30 pt covers: the smallest one that's still sharp at 2x.
    let url = (thumbs.find((t) => (t.width || 0) >= 60) || thumbs[thumbs.length - 1]).url;
    if (url.startsWith('//')) url = 'https:' + url;
    if (row.getAttribute('data-pisland-art') !== url) row.setAttribute('data-pisland-art', url);
  }
}

setInterval(tagCovers, 1000);
