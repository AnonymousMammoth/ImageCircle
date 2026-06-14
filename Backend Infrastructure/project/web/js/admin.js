/**
 * Circle Admin Panel
 * Pure vanilla JS. No frameworks. No external dependencies.
 * JWT stored in memory only — lost on refresh by design.
 */

/* ---------- State ---------- */
let jwtToken = null;
let currentUser = null;
let users = [];
let stats = {};

/* ---------- DOM refs ---------- */
const $ = (sel) => document.querySelector(sel);
const loginSection = $('#login-section');
const appSection    = $('#app-section');
const loginForm     = $('#login-form');
const loginError    = $('#login-error');
const logoutBtn     = $('#logout-btn');
const adminUsername = $('#admin-username');
const createUserBtn = $('#create-user-btn');
const usersTbody    = $('#users-tbody');
const usersError    = $('#users-error');
const modalOverlay  = $('#modal-overlay');
const modalContent  = $('#modal-content');
const modalCloseBtn = $('#modal-close-btn');

/* ---------- XSS Prevention ---------- */
function escapeHtml(str) {
    if (str == null) return '';
    const div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML;
}

/* ---------- Date formatting ---------- */
function formatDate(isoString) {
    if (!isoString) return '-';
    const d = new Date(isoString);
    if (isNaN(d)) return '-';
    return d.toLocaleDateString(undefined, {
        year: 'numeric', month: 'short', day: 'numeric'
    });
}

/* ---------- API Client ---------- */
async function apiCall(method, path, body) {
    const opts = {
        method,
        credentials: 'include',
        headers: {
            'Content-Type': 'application/json',
        },
    };
    if (jwtToken) {
        opts.headers['Authorization'] = 'Bearer ' + jwtToken;
    }
    if (body) {
        opts.body = JSON.stringify(body);
    }
    const response = await fetch('/api' + path, opts);
    if (response.status === 401) {
        jwtToken = null;
        currentUser = null;
        showLogin();
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
        throw new Error(msg);
    }
    const contentType = response.headers.get('Content-Type') || '';
    if (contentType.includes('application/json')) {
        return response.json();
    }
    return null;
}

/* ---------- Login / Logout ---------- */
async function login(username, password) {
    try {
        const data = await apiCall('POST', '/auth/login', { username, password });
        if (!data || !data.user || !data.token) {
            throw new Error('Invalid response from server');
        }
        if (!data.user.is_admin) {
            throw new Error('Admin access required');
        }
        jwtToken = data.token;
        currentUser = data.user;
        showApp();
    } catch (err) {
        loginError.textContent = escapeHtml(err.message);
    }
}

async function logout() {
    try {
        await apiCall('POST', '/auth/logout');
    } catch (_) {
        /* best-effort */
    } finally {
        jwtToken = null;
        currentUser = null;
        showLogin();
    }
}

/* ---------- UI State ---------- */
function showLogin() {
    appSection.classList.add('hidden');
    loginSection.classList.remove('hidden');
    loginForm.reset();
    loginError.textContent = '';
}

function showApp() {
    loginSection.classList.add('hidden');
    appSection.classList.remove('hidden');
    adminUsername.textContent = escapeHtml(currentUser ? currentUser.username : '');
    loadStats();
    loadUsers();
}

/* ---------- Modal ---------- */
function showModal(contentHtml) {
    modalContent.innerHTML = contentHtml;
    modalOverlay.classList.remove('hidden');
}

function hideModal() {
    modalOverlay.classList.add('hidden');
    modalContent.innerHTML = '';
}

/* ---------- Stats ---------- */
async function loadStats() {
    try {
        stats = await apiCall('GET', '/users/stats') || {};
        $('#stat-users').textContent = escapeHtml(String(stats.user_count ?? stats.total_users ?? '-'));
        $('#stat-posts').textContent = escapeHtml(String(stats.post_count ?? stats.total_posts ?? '-'));
        $('#stat-stories').textContent = escapeHtml(String(stats.story_count ?? stats.active_stories ?? '-'));
    } catch (err) {
        $('#stat-users').textContent = '-';
        $('#stat-posts').textContent = '-';
        $('#stat-stories').textContent = '-';
    }
}

/* ---------- Users Table ---------- */
async function loadUsers() {
    try {
        usersError.textContent = '';
        users = await apiCall('GET', '/users') || [];
        renderUsers();
    } catch (err) {
        usersError.textContent = escapeHtml(err.message);
        usersTbody.innerHTML = '';
    }
}

function renderUsers() {
    usersTbody.innerHTML = '';
    if (!users.length) {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td colspan="5" style="text-align:center;color:var(--text-secondary)">No users found</td>';
        usersTbody.appendChild(tr);
        return;
    }
    for (const user of users) {
        const tr = document.createElement('tr');
        const isAdmin = !!user.is_admin;
        const badgeClass = isAdmin ? 'badge-admin' : 'badge-user';
        const badgeText  = isAdmin ? 'Admin' : 'User';
        const userId = escapeHtml(String(user.id));
        const username = escapeHtml(user.username);
        const displayName = escapeHtml(user.display_name);

        tr.innerHTML = `
            <td>${username}</td>
            <td>${displayName}</td>
            <td><span class="badge ${badgeClass}">${badgeText}</span></td>
            <td>${escapeHtml(formatDate(user.created_at))}</td>
            <td>
                <div class="user-actions">
                    <button class="btn btn-secondary btn-small" data-action="reset" data-id="${userId}">Reset Password</button>
                    <button class="btn btn-secondary btn-small" data-action="toggle-admin" data-id="${userId}">${isAdmin ? 'Revoke Admin' : 'Make Admin'}</button>
                    <button class="btn btn-danger btn-small" data-action="delete" data-id="${userId}">Delete</button>
                </div>
            </td>
        `;
        usersTbody.appendChild(tr);
    }
}

/* ---------- Actions ---------- */
async function createUser() {
    const formHtml = `
        <h3>Create User</h3>
        <form id="create-user-form">
            <div class="form-group">
                <label for="new-username">Username</label>
                <input type="text" id="new-username" name="username" required autocomplete="off">
            </div>
            <div class="form-group">
                <label for="new-display-name">Display Name</label>
                <input type="text" id="new-display-name" name="display_name" required autocomplete="off">
            </div>
            <div id="create-user-error" class="error-text"></div>
            <button type="submit" class="btn btn-primary">Create</button>
        </form>
    `;
    showModal(formHtml);
    modalCloseBtn.classList.remove('hidden');

    $('#create-user-form').addEventListener('submit', async (e) => {
        e.preventDefault();
        const username = $('#new-username').value.trim();
        const displayName = $('#new-display-name').value.trim();
        const errEl = $('#create-user-error');
        errEl.textContent = '';

        try {
            const result = await apiCall('POST', '/users', {
                username,
                display_name: displayName,
            });
            const tempPass = result && result.temporary_password ? result.temporary_password : '';
            const createdUsername = escapeHtml(result && result.user ? result.user.username : username);

            modalContent.innerHTML = `
                <h3>User Created</h3>
                <p>User <strong>${createdUsername}</strong> has been created successfully.</p>
                ${tempPass ? `
                    <label style="display:block;margin-top:1rem;font-size:0.875rem;font-weight:500">Temporary Password</label>
                    <div class="temp-password-box">
                        <input type="text" id="temp-password" value="${escapeHtml(tempPass)}" readonly>
                        <button type="button" class="btn btn-secondary" id="copy-pass-btn">Copy</button>
                    </div>
                    <p style="font-size:0.8125rem;color:var(--text-secondary);margin-top:0.5rem">Share this password with the user. It will not be shown again.</p>
                ` : ''}
            `;
            if (tempPass) {
                $('#copy-pass-btn').addEventListener('click', () => {
                    const input = $('#temp-password');
                    input.select();
                    navigator.clipboard.writeText(input.value).catch(() => {});
                });
            }
            loadUsers();
        } catch (err) {
            errEl.textContent = escapeHtml(err.message);
        }
    });
}

async function resetPassword(userId) {
    const user = users.find(u => String(u.id) === String(userId));
    const username = user ? user.username : 'this user';
    const confirmed = confirm('Reset password for ' + username + '?');
    if (!confirmed) return;

    try {
        const result = await apiCall('POST', '/users/' + userId + '/reset-password');
        const tempPass = result && result.temporary_password ? result.temporary_password : '';
        showModal(`
            <h3>Password Reset</h3>
            <p>A new temporary password has been generated for <strong>${escapeHtml(username)}</strong>.</p>
            ${tempPass ? `
                <label style="display:block;margin-top:1rem;font-size:0.875rem;font-weight:500">Temporary Password</label>
                <div class="temp-password-box">
                    <input type="text" id="temp-password" value="${escapeHtml(tempPass)}" readonly>
                    <button type="button" class="btn btn-secondary" id="copy-pass-btn">Copy</button>
                </div>
                <p style="font-size:0.8125rem;color:var(--text-secondary);margin-top:0.5rem">Share this password with the user. It will not be shown again.</p>
            ` : ''}
        `);
        if (tempPass) {
            $('#copy-pass-btn').addEventListener('click', () => {
                const input = $('#temp-password');
                input.select();
                navigator.clipboard.writeText(input.value).catch(() => {});
            });
        }
        loadUsers();
    } catch (err) {
        usersError.textContent = escapeHtml(err.message);
    }
}

async function toggleAdmin(userId) {
    const user = users.find(u => String(u.id) === String(userId));
    const username = user ? user.username : 'this user';
    const action = user && user.is_admin ? 'revoke admin rights from' : 'grant admin rights to';
    const confirmed = confirm(action + ' ' + username + '?');
    if (!confirmed) return;

    try {
        await apiCall('POST', '/users/' + userId + '/toggle-admin');
        loadUsers();
    } catch (err) {
        usersError.textContent = escapeHtml(err.message);
    }
}

async function deleteUser(userId) {
    const user = users.find(u => String(u.id) === String(userId));
    const username = user ? user.username : 'this user';
    const confirmed = confirm('WARNING: This action cannot be undone.\n\nDelete user ' + username + ' and all their data?');
    if (!confirmed) return;

    try {
        await apiCall('DELETE', '/users/' + userId);
        loadUsers();
    } catch (err) {
        usersError.textContent = escapeHtml(err.message);
    }
}

/* ---------- Event delegation ---------- */
usersTbody.addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-action]');
    if (!btn) return;
    const action = btn.getAttribute('data-action');
    const userId = btn.getAttribute('data-id');
    if (!userId) return;

    if (action === 'reset')       resetPassword(userId);
    else if (action === 'toggle-admin') toggleAdmin(userId);
    else if (action === 'delete') deleteUser(userId);
});

/* ---------- Global listeners ---------- */
loginForm.addEventListener('submit', (e) => {
    e.preventDefault();
    const username = $('#login-username').value.trim();
    const password = $('#login-password').value;
    login(username, password);
});

logoutBtn.addEventListener('click', logout);
createUserBtn.addEventListener('click', createUser);
modalCloseBtn.addEventListener('click', hideModal);

modalOverlay.addEventListener('click', (e) => {
    if (e.target === modalOverlay) hideModal();
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !modalOverlay.classList.contains('hidden')) {
        hideModal();
    }
});

/* ---------- Init ---------- */
function init() {
    if (jwtToken) {
        showApp();
    } else {
        showLogin();
    }
}

init();
