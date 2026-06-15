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
    if (!date) return '';
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

function authenticatedMediaUrl(url) {
    return url || null;
}

// Fetches a media URL with the stored bearer token and same-origin credentials,
// returning a blob URL suitable for <img src> or <video src>. This works around
// Safari/PWA quirks where subresource requests may not carry the session cookie.
async function loadAuthenticatedMedia(url) {
    if (!url) return null;
    const headers = {};
    if (state.token) {
        headers['Authorization'] = 'Bearer ' + state.token;
    }
    const response = await fetch(url, { credentials: 'same-origin', headers });
    if (!response.ok) throw new Error('status ' + response.status);
    const blob = await response.blob();
    return URL.createObjectURL(blob);
}

function avatarUrl(user) {
    if (!user) return null;
    let url = null;
    if (user.avatar_url && user.avatar_url.trim()) url = user.avatar_url;
    else if (user.avatarUrl && user.avatarUrl.trim()) url = user.avatarUrl;
    else if (user.avatar_filename && user.avatar_filename.trim()) {
        url = '/media/' + user.id + '/' + user.avatar_filename;
    }
    return authenticatedMediaUrl(url);
}

function renderAvatar(user, size, options) {
    options = options || {};
    const url = avatarUrl(user);
    const sizePx = size || 40;
    const initial = initials(user && user.username ? user.username : '');
    const wrapper = createEl('div', { className: 'avatar', style: 'width:' + sizePx + 'px;height:' + sizePx + 'px;' });
    if (url) {
        const img = createEl('img', {
            alt: user && user.username ? user.username : '',
            loading: options.eager ? 'eager' : 'lazy'
        });
        wrapper.appendChild(img);
        loadAuthenticatedImage(url, img, wrapper, initial);
    } else {
        wrapper.textContent = initial;
        wrapper.classList.add('avatar-placeholder');
    }
    return wrapper;
}

// Loads an authenticated image through fetch so the Authorization header / cookie
// is reliably sent, then sets a blob URL on the <img>. This avoids Safari/PWA
// quirks where <img> subresources may not carry the session cookie.
async function loadAuthenticatedImage(url, img, wrapper, fallbackInitial) {
    try {
        const headers = {};
        if (state.token) {
            headers['Authorization'] = 'Bearer ' + state.token;
        }
        const response = await fetch(url, { credentials: 'same-origin', headers });
        if (!response.ok) throw new Error('status ' + response.status);
        const blob = await response.blob();
        img.src = URL.createObjectURL(blob);
        img.onload = function() {
            wrapper.classList.remove('avatar-placeholder');
        };
    } catch (err) {
        img.remove();
        wrapper.textContent = fallbackInitial;
        wrapper.classList.add('avatar-placeholder');
        console.warn('Failed to load avatar:', url, err);
    }
}

function usernameDisplay(user) {
    if (!user) return '';
    return user.display_name || user.username;
}

/* ---------- Media helpers ---------- */

function postMediaUrl(post) {
    if (!post) return null;
    let url = null;
    if (post.media_url && post.media_url.trim()) url = post.media_url;
    else if (post.mediaUrl && post.mediaUrl.trim()) url = post.mediaUrl;
    else if (post.media_filename && post.media_filename.trim()) {
        url = '/media/' + post.user_id + '/' + post.media_filename;
    }
    return authenticatedMediaUrl(url);
}

function postThumbnailUrl(post) {
    if (!post) return null;
    let url = null;
    if (post.thumbnail_url && post.thumbnail_url.trim()) url = post.thumbnail_url;
    else if (post.thumbnailUrl && post.thumbnailUrl.trim()) url = post.thumbnailUrl;
    else if (post.thumbnail_filename && post.thumbnail_filename.trim()) {
        url = '/media/' + post.user_id + '/' + post.thumbnail_filename;
    }
    return authenticatedMediaUrl(url) || postMediaUrl(post);
}

function storyMediaUrl(story) {
    if (!story) return null;
    let url = null;
    if (story.media_url && story.media_url.trim()) url = story.media_url;
    else if (story.mediaUrl && story.mediaUrl.trim()) url = story.mediaUrl;
    else if (story.media_filename && story.media_filename.trim()) {
        url = '/media/' + story.user_id + '/' + story.media_filename;
    }
    return authenticatedMediaUrl(url);
}

function storyThumbnailUrl(story) {
    if (!story) return null;
    let url = null;
    if (story.thumbnail_url && story.thumbnail_url.trim()) url = story.thumbnail_url;
    else if (story.thumbnailUrl && story.thumbnailUrl.trim()) url = story.thumbnailUrl;
    else if (story.thumbnail_filename && story.thumbnail_filename.trim()) {
        url = '/media/' + story.user_id + '/' + story.thumbnail_filename;
    }
    return authenticatedMediaUrl(url) || storyMediaUrl(story);
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

function validatePasswordStrength(password) {
    if (!password || password.length < 8) {
        return 'Password must be at least 8 characters long.';
    }
    let hasUpper = false;
    let hasLower = false;
    let hasDigit = false;
    for (let i = 0; i < password.length; i++) {
        const c = password.charCodeAt(i);
        if (c >= 65 && c <= 90) hasUpper = true;
        else if (c >= 97 && c <= 122) hasLower = true;
        else if (c >= 48 && c <= 57) hasDigit = true;
    }
    const missing = [];
    if (!hasUpper) missing.push('uppercase letter');
    if (!hasLower) missing.push('lowercase letter');
    if (!hasDigit) missing.push('digit');
    if (missing.length > 0) {
        return 'Password must contain at least one ' + missing.join(', ') + '.';
    }
    return null;
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

function canManageContent(userId, currentUser) {
    if (!currentUser) return false;
    // Admin deletion/management of other users' content now happens only in the
    // admin moderation panel, so this helper is owner-only in the main UI.
    return String(currentUser.id) === String(userId);
}

function createMountToken() {
    let active = true;
    return {
        isActive() { return active; },
        cancel() { active = false; },
        guard(fn) {
            return function(...args) {
                if (!active) return;
                return fn.apply(this, args);
            };
        }
    };
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
