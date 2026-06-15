/**
 * API client wrappers. All calls use fetch with credentials: 'same-origin'
 * and Authorization: Bearer <token> when authenticated.
 */

async function apiRequest(method, path, options) {
    options = options || {};
    const opts = {
        method,
        credentials: 'same-origin',
        headers: {}
    };

    if (state.token) {
        opts.headers['Authorization'] = 'Bearer ' + state.token;
    }

    if (options.headers) {
        Object.assign(opts.headers, options.headers);
    }

    if (options.body) {
        opts.body = options.body;
    }

    const response = await fetch('/api' + path, opts);

    if (response.status === 401) {
        state.clearAuth();
        // Don't fire the auth-required event while restoreSession is still trying
        // a cookie or persisted token, otherwise a transient 401 during refresh
        // immediately kicks the user to the login screen.
        if (!state.isLoadingAuth && !state.authRequiredFired) {
            state.authRequiredFired = true;
            window.dispatchEvent(new CustomEvent('circle:authrequired'));
        }
        throw new Error('Session expired. Please sign in again.');
    }

    if (!response.ok) {
        let msg = 'Request failed';
        try {
            const data = await response.json();
            msg = data.error || data.message || msg;
        } catch (_) {
            msg = response.statusText || msg;
        }
        const err = new Error(msg);
        err.status = response.status;
        throw err;
    }

    const contentType = response.headers.get('Content-Type') || '';
    if (contentType.includes('application/json')) {
        return response.json();
    }
    return null;
}

async function apiGet(path) {
    return apiRequest('GET', path, {});
}

async function apiPost(path, body) {
    return apiRequest('POST', path, {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
    });
}

async function apiDelete(path) {
    return apiRequest('DELETE', path, {});
}

async function apiMultipart(path, formData, progressCallback) {
    const xhr = new XMLHttpRequest();
    return new Promise((resolve, reject) => {
        xhr.open('POST', '/api' + path, true);
        if (state.token) {
            xhr.setRequestHeader('Authorization', 'Bearer ' + state.token);
        }
        xhr.withCredentials = true;

        xhr.upload.onprogress = function(e) {
            if (e.lengthComputable && progressCallback) {
                progressCallback(e.loaded / e.total);
            }
        };

        xhr.onload = function() {
            if (xhr.status === 401) {
                state.clearAuth();
                if (!state.authRequiredFired) {
                    state.authRequiredFired = true;
                    window.dispatchEvent(new CustomEvent('circle:authrequired'));
                }
                reject(new Error('Session expired. Please sign in again.'));
                return;
            }
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    const data = xhr.responseText ? JSON.parse(xhr.responseText) : null;
                    resolve(data);
                } catch (e) {
                    resolve(null);
                }
            } else {
                let msg = 'Upload failed';
                try {
                    const data = JSON.parse(xhr.responseText);
                    msg = data.error || data.message || msg;
                } catch (_) {}
                const err = new Error(msg);
                err.status = xhr.status;
                reject(err);
            }
        };

        xhr.onerror = () => reject(new Error('Network error'));
        xhr.onabort = () => reject(new Error('Upload cancelled'));

        xhr.send(formData);
    });
}

/* ---------- Auth endpoints ---------- */

async function login(username, password) {
    const data = await apiPost('/auth/login', { username, password });
    return data;
}

async function changePassword(currentPassword, newPassword) {
    return apiPost('/auth/change-password', { current_password: currentPassword, new_password: newPassword });
}

async function logout() {
    return apiRequest('POST', '/auth/logout', {});
}

async function fetchMe() {
    return apiGet('/users/me');
}

/* ---------- Users ---------- */

async function searchUsers(query) {
    const encoded = encodeURIComponent(query);
    const data = await apiGet('/users/search?q=' + encoded);
    return data && data.users ? data.users : [];
}

async function fetchUserPosts(userId) {
    return apiGet('/users/' + userId + '/posts');
}

async function markNotificationsRead() {
    return apiRequest('POST', '/notifications/read', {});
}

async function updateDisplayName(displayName) {
    return apiRequest('PUT', '/users/me', {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ display_name: displayName })
    });
}

async function uploadAvatar(file, progressCallback) {
    const formData = new FormData();
    formData.append('avatar', file, file.name);
    return apiMultipart('/users/me/avatar', formData, progressCallback);
}

/* ---------- Posts ---------- */

async function fetchFeed(page, limit) {
    page = page || 1;
    limit = limit || 15;
    const data = await apiGet('/posts?page=' + page + '&limit=' + limit);
    return data && data.posts ? data.posts : [];
}

async function fetchPost(postId) {
    return apiGet('/posts/' + postId);
}

async function createTextPost(caption) {
    return apiPost('/posts', { caption });
}

async function createMediaPost(file, caption, thumbnailFile, progressCallback) {
    const formData = new FormData();
    if (caption != null) formData.append('caption', caption);
    formData.append('media', file, file.name);
    if (thumbnailFile) formData.append('thumbnail', thumbnailFile, thumbnailFile.name);
    return apiMultipart('/posts', formData, progressCallback);
}

async function deletePost(postId) {
    return apiDelete('/posts/' + postId);
}

async function toggleLike(postId) {
    return apiPost('/posts/' + postId + '/like');
}

async function fetchComments(postId) {
    const data = await apiGet('/posts/' + postId + '/comments');
    return data && data.comments ? data.comments : [];
}

async function createComment(postId, text) {
    return apiPost('/posts/' + postId + '/comments', { text });
}

async function deleteComment(commentId) {
    return apiDelete('/comments/' + commentId);
}

/* ---------- Notifications ---------- */

async function fetchNotifications() {
    const data = await apiGet('/notifications');
    return data && data.notifications ? data.notifications : [];
}

async function fetchUnreadNotificationCount() {
    const data = await apiGet('/notifications/unread-count');
    return data && typeof data.count === 'number' ? data.count : 0;
}

/* ---------- Stories ---------- */

async function fetchStories() {
    const data = await apiGet('/stories');
    return data && data.stories ? data.stories : [];
}

async function fetchUserStories(userId) {
    const data = await apiGet('/users/' + userId + '/stories');
    return data && data.stories ? data.stories : [];
}

async function markStoryViewed(storyId) {
    return apiRequest('POST', '/stories/' + storyId + '/view', {});
}

async function deleteStory(storyId) {
    return apiDelete('/stories/' + storyId);
}

async function createStory(file, mediaType, thumbnailFile, progressCallback) {
    const formData = new FormData();
    formData.append('media_type', mediaType);
    formData.append('media', file, file.name);
    if (thumbnailFile) formData.append('thumbnail', thumbnailFile, thumbnailFile.name);
    return apiMultipart('/stories', formData, progressCallback);
}
