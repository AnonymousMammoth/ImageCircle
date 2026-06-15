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
    },

    updateUser(user) {
        this.user = user || this.user;
    }
};
