/**
 * Simple hash-based router for the SPA.
 */

const router = {
    currentRoute: '',
    params: {},
    _resolveTimer: null,
    _lastHash: '',

    init() {
        window.addEventListener('hashchange', () => this.resolve());
        window.addEventListener('popstate', () => this.resolve());
        this.resolve();
    },

    resolve() {
        const hash = window.location.hash || '#/';
        if (this._lastHash === hash) return;
        this._lastHash = hash;

        if (this._resolveTimer) clearTimeout(this._resolveTimer);
        this._resolveTimer = setTimeout(() => {
            const clean = hash.replace(/^#/, '') || '/';
            const [path, query] = clean.split('?');
            this.currentRoute = path;
            this.params = {};

            const parts = path.split('/').filter(Boolean);
            if (parts.length >= 2 && parts[0] === 'profile') {
                this.params.id = parts[1];
            }

            const event = new CustomEvent('circle:route', {
                detail: { path, query, params: this.params, parts }
            });
            window.dispatchEvent(event);
        }, 30);
    },

    navigate(path) {
        window.location.hash = path;
    },

    replace(path) {
        window.location.replace(window.location.href.split('#')[0] + path);
    },

    back() {
        window.history.back();
    },

    getPath() {
        return this.currentRoute;
    }
};
