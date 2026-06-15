/**
 * Global application state. JWT is kept in memory only (lost on refresh).
 */

const state = {
    token: null,
    user: null,
    serverURL: '',
    lastPassword: '',
    requiresPasswordChange: false,
    isLoadingAuth: true,

    get isAuthenticated() {
        return !!this.token;
    },

    get isAdmin() {
        return !!this.user && !!this.user.is_admin;
    },

    setAuth(data, password) {
        this.token = data.token || null;
        this.user = data.user || null;
        this.lastPassword = password || '';
        this.requiresPasswordChange = !!(this.user && this.user.password_change_required);
    },

    clearAuth() {
        this.token = null;
        this.user = null;
        this.lastPassword = '';
        this.requiresPasswordChange = false;
    },

    updateUser(user) {
        this.user = user || this.user;
    }
};
