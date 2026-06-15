/**
 * Shared utilities for the ImageCircle web app.
 */

/* ---------- XSS Prevention ---------- */

function escapeHtml(str) {
    if (str == null) return '';
    const div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML;
}

function setText(el, text) {
    if (!el) return;
    el.textContent = text == null ? '' : String(text);
}

/* ---------- DOM helpers ---------- */

function $(sel, context) {
    return (context || document).querySelector(sel);
}

function $$(sel, context) {
    return Array.from((context || document).querySelectorAll(sel));
}

function createEl(tag, attrs, children) {
    const el = document.createElement(tag);
    if (attrs) {
        Object.keys(attrs).forEach(key => {
            if (key === 'text') {
                setText(el, attrs[key]);
            } else if (key === 'className') {
                el.className = attrs[key];
            } else if (key.startsWith('on') && typeof attrs[key] === 'function') {
                const eventName = key.slice(2).toLowerCase();
                el.addEventListener(eventName, attrs[key]);
            } else {
                el.setAttribute(key, attrs[key]);
            }
        });
    }
    if (children) {
        children.forEach(child => {
            if (child == null) return;
            if (typeof child === 'string') {
                el.appendChild(document.createTextNode(child));
            } else if (child instanceof Node) {
                el.appendChild(child);
            }
        });
    }
    return el;
}

function clearEl(el) {
    if (!el) return;
    while (el.firstChild) el.removeChild(el.firstChild);
}

/* ---------- Date formatting ---------- */

function parseISO8601(string) {
    if (!string) return null;
    const d = new Date(string);
    if (isNaN(d.getTime())) return null;
    return d;
}

function relativeTime(isoString) {
    const date = parseISO8601(isoString);
    if (!date) return isoString || '';
    const interval = (Date.now() - date.getTime()) / 1000;
    if (interval < 10) return 'just now';
    if (interval < 60) return Math.floor(interval) + 's';
    const minutes = Math.floor(interval / 60);
    if (minutes < 60) return minutes + 'm';
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return hours + 'h';
    const days = Math.floor(hours / 24);
    if (days < 7) return days + 'd';
    return date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

function formatDate(isoString) {
    const date = parseISO8601(isoString);
    if (!date) return '-';
    return date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

/* ---------- User helpers ---------- */

function initials(name) {
    if (!name) return '?';
    const parts = String(name).trim().split(/\s+/);
    if (parts.length > 1) {
        return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
    }
    return String(name).substring(0, 2).toUpperCase();
}

function avatarUrl(user) {
    if (!user) return null;
    if (user.avatar_url && user.avatar_url.trim()) return user.avatar_url;
    if (user.avatarUrl && user.avatarUrl.trim()) return user.avatarUrl;
    if (user.avatar_filename && user.avatar_filename.trim()) {
        return '/media/' + user.id + '/' + user.avatar_filename;
    }
    return null;
}

function renderAvatar(user, size) {
    const url = avatarUrl(user);
    const sizePx = size || 40;
    const initial = initials(user ? user.username : '');
    const wrapper = createEl('div', { className: 'avatar', style: 'width:' + sizePx + 'px;height:' + sizePx + 'px;' });
    if (url) {
        const img = createEl('img', {
            src: url,
            alt: user.username,
            loading: 'lazy'
        });
        img.onerror = function() {
            img.remove();
            wrapper.textContent = initial;
            wrapper.classList.add('avatar-placeholder');
        };
        img.onload = function() {
            wrapper.classList.remove('avatar-placeholder');
        };
        wrapper.appendChild(img);
    } else {
        wrapper.textContent = initial;
        wrapper.classList.add('avatar-placeholder');
    }
    return wrapper;
}

function usernameDisplay(user) {
    if (!user) return '';
    return user.display_name || user.username;
}

/* ---------- Media helpers ---------- */

function postMediaUrl(post) {
    if (!post) return null;
    if (post.media_url && post.media_url.trim()) return post.media_url;
    if (post.mediaUrl && post.mediaUrl.trim()) return post.mediaUrl;
    if (post.media_filename && post.media_filename.trim()) {
        return '/media/' + post.user_id + '/' + post.media_filename;
    }
    return null;
}

function postThumbnailUrl(post) {
    if (!post) return null;
    if (post.thumbnail_url && post.thumbnail_url.trim()) return post.thumbnail_url;
    if (post.thumbnailUrl && post.thumbnailUrl.trim()) return post.thumbnailUrl;
    if (post.thumbnail_filename && post.thumbnail_filename.trim()) {
        return '/media/' + post.user_id + '/' + post.thumbnail_filename;
    }
    return postMediaUrl(post);
}

function storyMediaUrl(story) {
    if (!story) return null;
    if (story.media_url && story.media_url.trim()) return story.media_url;
    if (story.mediaUrl && story.mediaUrl.trim()) return story.mediaUrl;
    if (story.media_filename && story.media_filename.trim()) {
        return '/media/' + story.user_id + '/' + story.media_filename;
    }
    return null;
}

function storyThumbnailUrl(story) {
    if (!story) return null;
    if (story.thumbnail_url && story.thumbnail_url.trim()) return story.thumbnail_url;
    if (story.thumbnailUrl && story.thumbnailUrl.trim()) return story.thumbnailUrl;
    if (story.thumbnail_filename && story.thumbnail_filename.trim()) {
        return '/media/' + story.user_id + '/' + story.thumbnail_filename;
    }
    return storyMediaUrl(story);
}

function isTextOnlyPost(post) {
    return !post || !post.media_filename || post.media_filename === '';
}

/* ---------- Misc ---------- */

function debounce(fn, wait) {
    let timeout;
    return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => fn.apply(this, args), wait);
    };
}

function escapeAttribute(str) {
    if (str == null) return '';
    return escapeHtml(str).replace(/"/g, '&quot;');
}

function clamp(val, min, max) {
    return Math.max(min, Math.min(max, val));
}

function groupStoriesByUser(stories) {
    const groups = {};
    for (const story of stories) {
        if (!groups[story.user.id]) {
            groups[story.user.id] = { user: story.user, stories: [] };
        }
        groups[story.user.id].stories.push(story);
    }
    for (const key of Object.keys(groups)) {
        groups[key].stories.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
    }
    return Object.values(groups).sort((a, b) => new Date(b.stories[0].created_at) - new Date(a.stories[0].created_at));
}

function isOwnContent(userId, currentUser) {
    if (!currentUser) return false;
    return String(currentUser.id) === String(userId);
}

/* ---------- Modal / sheet helpers ---------- */

function showAlert(message, title) {
    window.alert(title ? title + '\n\n' + message : message);
}

function confirmAction(message) {
    return window.confirm(message);
}

function stopEvent(e) {
    if (e) {
        e.preventDefault();
        e.stopPropagation();
    }
}
