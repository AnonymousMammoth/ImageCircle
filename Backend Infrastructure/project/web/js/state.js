/**
 * Global application state. JWT is kept in memory, but session can be restored
 * from the HttpOnly circle_session cookie via /api/users/me.
 */

const state = {
    token: null,
    user: null,
    cookieAuth: false,
    serverURL: '',
    requiresPasswordChange: false,
    isLoadingAuth: true,
    authRequiredFired: false,
    notificationCount: 0,

    get isAuthenticated() {
        return !!this.token || !!this.cookieAuth;
    },

    get isAdmin() {
        return !!this.user && !!this.user.is_admin;
    },

    setAuth(data) {
        this.token = data.token || null;
        this.user = data.user || null;
        this.cookieAuth = false;
        this.authRequiredFired = false;
        this.requiresPasswordChange = !!(this.user && this.user.password_change_required);
        this._persistToken();
    },

    setAuthFromCookie(user) {
        this.token = null;
        this.user = user || null;
        this.cookieAuth = true;
        this.authRequiredFired = false;
        this.requiresPasswordChange = !!(this.user && this.user.password_change_required);
    },

    clearAuth() {
        this.token = null;
        this.user = null;
        this.cookieAuth = false;
        this.requiresPasswordChange = false;
        try { localStorage.removeItem('circle_token'); } catch (_) {}
    },

    updateUser(user) {
        this.user = user || this.user;
    },

    setNotificationCount(count) {
        this.notificationCount = Math.max(0, parseInt(count, 10) || 0);
    },

    loadPersistedToken() {
        try {
            const t = localStorage.getItem('circle_token');
            return t || null;
        } catch (_) {
            return null;
        }
    },

    _persistToken() {
        try {
            if (this.token) {
                localStorage.setItem('circle_token', this.token);
            } else {
                localStorage.removeItem('circle_token');
            }
        } catch (_) {}
    }
};
